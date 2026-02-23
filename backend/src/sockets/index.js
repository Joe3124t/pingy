const { Server } = require('socket.io');
const { allowedOrigins } = require('../config/env');
const { verifyAccessToken } = require('../services/tokenService');
const {
  findUserAuthById,
  setUserOnlineStatus,
  filterVisiblePresenceUserIds,
} = require('../models/userModel');
const {
  addSocketConnection,
  removeSocketConnection,
  getOnlineUserIds,
} = require('../services/presenceService');
const {
  assertConversationAccess,
  createConversationMessage,
  markConversationSeenForUser,
  markAllDeliveredForUser,
  markConversationDeliveredForUser,
  markDeliveredIfRecipientOnline,
  sendPushToRecipientIfOffline,
} = require('../services/messageService');
const { findConversationParticipants } = require('../models/conversationModel');
const { assertUsersCanInteract } = require('../services/blockService');
const { signMediaUrlsInMessage } = require('../services/mediaAccessService');

const parseSocketToken = (socket) => {
  const authToken = socket.handshake.auth?.token;

  if (authToken) {
    return String(authToken).replace(/^Bearer\s+/i, '').trim();
  }

  const headerToken = socket.handshake.headers.authorization;

  if (headerToken && headerToken.startsWith('Bearer ')) {
    return headerToken.slice('Bearer '.length).trim();
  }

  return null;
};

const emitDeliveredUpdates = (io, updates) => {
  updates.forEach((update) => {
    io.to(`conversation:${update.conversationId}`).emit('message:delivered', update);
    io.to(`user:${update.senderId}`).emit('message:delivered', update);
  });
};

const emitSeenUpdates = (io, updates) => {
  updates.forEach((update) => {
    io.to(`conversation:${update.conversationId}`).emit('message:seen', update);
    io.to(`user:${update.senderId}`).emit('message:seen', update);
  });
};

const emitMessageCreated = (io, message) => {
  const signedMessage = signMediaUrlsInMessage(message);

  io.to(`conversation:${signedMessage.conversationId}`).emit('message:new', signedMessage);
  io.to(`user:${signedMessage.senderId}`).emit('message:new', signedMessage);
  io.to(`user:${signedMessage.recipientId}`).emit('message:new', signedMessage);
};

const allowedCallEndStatuses = new Set(['ended', 'missed', 'declined']);

const normalizeCallStatus = (socketEventName, rawStatus) => {
  if (socketEventName === 'call:invite') {
    return 'ringing';
  }
  if (socketEventName === 'call:accept') {
    return 'connected';
  }
  if (socketEventName === 'call:decline') {
    return 'declined';
  }
  if (socketEventName === 'call:end') {
    const normalized = String(rawStatus || '').trim().toLowerCase();
    return allowedCallEndStatuses.has(normalized) ? normalized : 'ended';
  }
  return null;
};

const emitCallSignal = (io, signal) => {
  const eventName = `call:${signal.status}`;
  io.to(`user:${signal.fromUserId}`).emit(eventName, signal);
  io.to(`user:${signal.toUserId}`).emit(eventName, signal);
  io.to(`conversation:${signal.conversationId}`).emit(eventName, signal);
};

const toISOStringSafe = (value) => {
  if (!value) {
    return null;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  const parsed = new Date(value);
  if (!Number.isNaN(parsed.getTime())) {
    return parsed.toISOString();
  }

  return null;
};

const emitPresenceSnapshot = async (socket, userId) => {
  const onlineUserIds = getOnlineUserIds();
  const visibleOnlineUserIds = await filterVisiblePresenceUserIds({
    viewerUserId: userId,
    candidateUserIds: onlineUserIds,
  });

  socket.emit('presence:snapshot', {
    onlineUserIds: visibleOnlineUserIds,
  });
};

const emitPresenceUpdateToVisibleViewers = async ({
  io,
  subjectUserId,
  isOnline,
  lastSeen,
}) => {
  const onlineViewerIds = getOnlineUserIds();

  const checks = await Promise.all(
    onlineViewerIds.map(async (viewerUserId) => {
      const visible = await filterVisiblePresenceUserIds({
        viewerUserId,
        candidateUserIds: [subjectUserId],
      });

      return {
        viewerUserId,
        canSee: visible.length > 0,
      };
    }),
  );

  checks.forEach((entry) => {
    if (!entry.canSee) {
      return;
    }

    io.to(`user:${entry.viewerUserId}`).emit('presence:update', {
      userId: subjectUserId,
      isOnline,
      lastSeen: isOnline ? null : toISOStringSafe(lastSeen) || new Date().toISOString(),
    });
  });
};

const createSocketServer = (server) => {
  const io = new Server(server, {
    cors: {
      origin: allowedOrigins,
      methods: ['GET', 'POST'],
      credentials: true,
    },
    maxHttpBufferSize: 2e6,
  });

  io.use(async (socket, next) => {
    try {
      const token = parseSocketToken(socket);

      if (!token) {
        throw new Error('Missing socket token');
      }

      const payload = verifyAccessToken(token);
      const user = await findUserAuthById(payload.sub);

      if (!user) {
        throw new Error('Socket user not found');
      }

      if (user.currentDeviceId && String(user.currentDeviceId) !== String(payload.deviceId || '')) {
        throw new Error('Socket session no longer active on this device');
      }

      delete user.passwordHash;
      delete user.currentDeviceId;
      socket.data.user = user;
      next();
    } catch (error) {
      next(new Error('Unauthorized'));
    }
  });

  io.on('connection', async (socket) => {
    const user = socket.data.user;
    socket.join(`user:${user.id}`);

    const status = addSocketConnection(user.id, socket.id);

    if (!status.wasOnline) {
      const updatedUser = await setUserOnlineStatus({ userId: user.id, isOnline: true });
      await emitPresenceUpdateToVisibleViewers({
        io,
        subjectUserId: user.id,
        isOnline: true,
        lastSeen: updatedUser?.lastSeen || null,
      });
    }

    await emitPresenceSnapshot(socket, user.id);

    const deliveredOnConnect = await markAllDeliveredForUser(user.id);
    emitDeliveredUpdates(io, deliveredOnConnect);

    socket.on('conversation:join', async (payload = {}, acknowledge) => {
      try {
        const { conversationId } = payload;
        await assertConversationAccess({ conversationId, userId: user.id });
        socket.join(`conversation:${conversationId}`);

        const updates = await markConversationDeliveredForUser({
          userId: user.id,
          conversationId,
        });

        emitDeliveredUpdates(io, updates);

        if (typeof acknowledge === 'function') {
          acknowledge({ ok: true });
        }
      } catch (error) {
        if (typeof acknowledge === 'function') {
          acknowledge({ ok: false, message: error.message || 'Could not join conversation' });
        }
      }
    });

    socket.on('conversation:leave', (payload = {}) => {
      const { conversationId } = payload;

      if (conversationId) {
        socket.leave(`conversation:${conversationId}`);
      }
    });

    socket.on('message:send', async (payload = {}, acknowledge) => {
      try {
        const conversationId = String(payload.conversationId || '').trim();
        const body = String(payload.body || '').trim();

        if (!conversationId || !body) {
          throw new Error('Text message body is required');
        }

        const message = await createConversationMessage({
          conversationId,
          senderId: user.id,
          replyToMessageId: payload.replyToMessageId ? String(payload.replyToMessageId) : undefined,
          type: 'text',
          body,
          clientId: payload.clientId ? String(payload.clientId) : undefined,
        });

        emitMessageCreated(io, message);

        const deliveredUpdates = await markDeliveredIfRecipientOnline(message);
        emitDeliveredUpdates(io, deliveredUpdates);
        await sendPushToRecipientIfOffline(message);

        if (typeof acknowledge === 'function') {
          acknowledge({ ok: true, message: signMediaUrlsInMessage(message) });
        }
      } catch (error) {
        if (typeof acknowledge === 'function') {
          acknowledge({ ok: false, message: error.message || 'Message send failed' });
        }
      }
    });

    socket.on('typing:start', async (payload = {}) => {
      try {
        const conversationId = String(payload.conversationId || '').trim();

        if (!conversationId) {
          return;
        }

        await assertConversationAccess({ conversationId, userId: user.id });

        socket.to(`conversation:${conversationId}`).emit('typing:start', {
          conversationId,
          userId: user.id,
          username: user.username,
        });
      } catch (error) {
        // Ignore unauthorized typing signals.
      }
    });

    socket.on('typing:stop', async (payload = {}) => {
      try {
        const conversationId = String(payload.conversationId || '').trim();

        if (!conversationId) {
          return;
        }

        await assertConversationAccess({ conversationId, userId: user.id });

        socket.to(`conversation:${conversationId}`).emit('typing:stop', {
          conversationId,
          userId: user.id,
          username: user.username,
        });
      } catch (error) {
        // Ignore unauthorized typing signals.
      }
    });

    socket.on('message:seen', async (payload = {}, acknowledge) => {
      try {
        const conversationId = String(payload.conversationId || '').trim();

        if (!conversationId) {
          throw new Error('conversationId is required');
        }

        const updates = await markConversationSeenForUser({
          userId: user.id,
          conversationId,
          messageIds: Array.isArray(payload.messageIds) ? payload.messageIds : undefined,
        });

        emitSeenUpdates(io, updates);

        if (typeof acknowledge === 'function') {
          acknowledge({ ok: true, updates });
        }
      } catch (error) {
        if (typeof acknowledge === 'function') {
          acknowledge({ ok: false, message: error.message || 'Failed to mark seen' });
        }
      }
    });

    const handleCallSignal = async (socketEventName, payload = {}, acknowledge) => {
      try {
        const conversationId = String(payload.conversationId || '').trim();
        const toUserId = String(payload.toUserId || '').trim();
        const callId = String(payload.callId || '').trim();
        const status = normalizeCallStatus(socketEventName, payload.status);

        if (!conversationId || !toUserId || !callId || !status) {
          throw new Error('Invalid call signal payload');
        }

        await assertConversationAccess({ conversationId, userId: user.id });

        const participants = await findConversationParticipants(conversationId);
        if (!participants.includes(toUserId) || toUserId === user.id) {
          throw new Error('Call recipient is not part of this conversation');
        }

        await assertUsersCanInteract({
          firstUserId: user.id,
          secondUserId: toUserId,
        });

        const signal = {
          callId,
          conversationId,
          fromUserId: user.id,
          toUserId,
          status,
          createdAt: new Date().toISOString(),
        };

        emitCallSignal(io, signal);

        if (typeof acknowledge === 'function') {
          acknowledge({ ok: true, signal });
        }
      } catch (error) {
        if (typeof acknowledge === 'function') {
          acknowledge({ ok: false, message: error.message || 'Call signal failed' });
        }
      }
    };

    socket.on('call:invite', (payload = {}, acknowledge) =>
      handleCallSignal('call:invite', payload, acknowledge));
    socket.on('call:accept', (payload = {}, acknowledge) =>
      handleCallSignal('call:accept', payload, acknowledge));
    socket.on('call:decline', (payload = {}, acknowledge) =>
      handleCallSignal('call:decline', payload, acknowledge));
    socket.on('call:end', (payload = {}, acknowledge) =>
      handleCallSignal('call:end', payload, acknowledge));

    socket.on('disconnect', async () => {
      const removed = removeSocketConnection(user.id, socket.id);

      if (!removed.isNowOnline) {
        const updatedUser = await setUserOnlineStatus({
          userId: user.id,
          isOnline: false,
        });

        await emitPresenceUpdateToVisibleViewers({
          io,
          subjectUserId: user.id,
          isOnline: false,
          lastSeen: updatedUser?.lastSeen || new Date().toISOString(),
        });
      }
    });
  });

  return io;
};

module.exports = {
  createSocketServer,
};
