const {
  isUserInConversation,
  findConversationParticipants,
  touchConversationActivity,
  updateParticipantReadCursor,
} = require('../models/conversationModel');
const {
  findMessageById,
  findMessageByClientId,
  createMessage,
  listMessages,
  markMessagesDelivered,
  markMessagesSeen,
  countUnreadMessagesForUser,
} = require('../models/messageModel');
const { findUserById } = require('../models/userModel');
const { isUserOnline } = require('./presenceService');
const { sendMessagePushToUser } = require('./pushService');
const { sanitizeText } = require('../utils/sanitize');
const { HttpError } = require('../utils/httpError');
const { assertEncryptedPayload } = require('../crypto/e2ee');
const { assertUsersCanInteract } = require('./blockService');

const assertConversationAccess = async ({ conversationId, userId }) => {
  const allowed = await isUserInConversation({ conversationId, userId });

  if (!allowed) {
    throw new HttpError(403, 'You do not have access to this conversation');
  }
};

const resolveRecipientId = (participants, senderId) => {
  const recipientId = participants.find((participantId) => participantId !== senderId);

  if (!recipientId) {
    throw new HttpError(400, 'Conversation recipient not found');
  }

  return recipientId;
};

const createConversationMessage = async ({
  conversationId,
  senderId,
  replyToMessageId = null,
  type,
  body,
  isEncrypted = false,
  mediaUrl,
  mediaName,
  mediaMime,
  mediaSize,
  voiceDurationMs,
  clientId,
}) => {
  await assertConversationAccess({ conversationId, userId: senderId });

  const participants = await findConversationParticipants(conversationId);
  const recipientId = resolveRecipientId(participants, senderId);
  await assertUsersCanInteract({
    firstUserId: senderId,
    secondUserId: recipientId,
  });

  if (clientId) {
    const existing = await findMessageByClientId({
      conversationId,
      senderId,
      clientId,
    });

    if (existing) {
      return existing;
    }
  }

  let normalizedBody = null;
  let normalizedEncryptionFlag = false;

  if (type === 'text') {
    if (!isEncrypted || !body) {
      throw new HttpError(400, 'Encrypted text payload is required');
    }

    let parsedPayload = body;

    if (typeof body === 'string') {
      try {
        parsedPayload = JSON.parse(body);
      } catch {
        throw new HttpError(400, 'Invalid encrypted payload');
      }
    }

    const payload = assertEncryptedPayload(parsedPayload);
    normalizedBody = JSON.stringify(payload);
    normalizedEncryptionFlag = true;
  } else {
    normalizedBody = body ? sanitizeText(body, 500) : null;
  }

  if (type !== 'text' && !mediaUrl) {
    throw new HttpError(400, 'Media URL is required for media messages');
  }

  let normalizedReplyToMessageId = null;

  if (replyToMessageId) {
    const replyTarget = await findMessageById(replyToMessageId);

    if (!replyTarget || replyTarget.conversationId !== conversationId) {
      throw new HttpError(400, 'replyToMessageId must reference a message in the same conversation');
    }

    normalizedReplyToMessageId = replyTarget.id;
  }

  const message = await createMessage({
    conversationId,
    senderId,
    recipientId,
    replyToMessageId: normalizedReplyToMessageId,
    type,
    body: normalizedBody,
    isEncrypted: normalizedEncryptionFlag,
    mediaUrl,
    mediaName,
    mediaMime,
    mediaSize,
    voiceDurationMs,
    clientId,
  });

  await touchConversationActivity(conversationId, message.createdAt);

  return message;
};

const listConversationMessages = async ({ userId, conversationId, limit, before }) => {
  await assertConversationAccess({ conversationId, userId });

  return listMessages({
    userId,
    conversationId,
    limit,
    before,
  });
};

const markConversationDeliveredForUser = async ({ userId, conversationId, messageIds }) => {
  await assertConversationAccess({ conversationId, userId });

  return markMessagesDelivered({
    recipientId: userId,
    conversationId,
    messageIds,
  });
};

const markAllDeliveredForUser = async (userId) => {
  return markMessagesDelivered({
    recipientId: userId,
  });
};

const markConversationSeenForUser = async ({ userId, conversationId, messageIds }) => {
  await assertConversationAccess({ conversationId, userId });
  const user = await findUserById(userId);

  if (!user?.readReceiptsEnabled) {
    return [];
  }

  const updates = await markMessagesSeen({
    recipientId: userId,
    conversationId,
    messageIds,
  });

  if (updates.length > 0) {
    const lastUpdate = updates[updates.length - 1];

    await updateParticipantReadCursor({
      conversationId,
      userId,
      messageId: lastUpdate.id,
    });
  }

  return updates;
};

const markDeliveredIfRecipientOnline = async (message) => {
  if (!isUserOnline(message.recipientId)) {
    return [];
  }

  return markMessagesDelivered({
    recipientId: message.recipientId,
    messageIds: [message.id],
  });
};

const sendPushToRecipientIfOffline = async (message) => {
  if (!message?.recipientId || isUserOnline(message.recipientId)) {
    return {
      sent: 0,
      attempted: 0,
      skipped: true,
    };
  }

  try {
    const unreadCount = await countUnreadMessagesForUser(message.recipientId);

    return await sendMessagePushToUser({
      recipientUserId: message.recipientId,
      message,
      badgeCount: unreadCount,
    });
  } catch {
    return {
      sent: 0,
      attempted: 0,
      skipped: true,
    };
  }
};

module.exports = {
  assertConversationAccess,
  createConversationMessage,
  listConversationMessages,
  markConversationDeliveredForUser,
  markAllDeliveredForUser,
  markConversationSeenForUser,
  markDeliveredIfRecipientOnline,
  sendPushToRecipientIfOffline,
};
