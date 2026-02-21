const { asyncHandler } = require('../utils/asyncHandler');
const { HttpError } = require('../utils/httpError');
const { uploadBuffer } = require('../services/storageService');
const {
  createConversationMessage,
  listConversationMessages,
  markConversationSeenForUser,
  markDeliveredIfRecipientOnline,
  sendPushToRecipientIfOffline,
} = require('../services/messageService');
const { toggleReactionForMessage } = require('../services/messageReactionService');
const { inferMessageType } = require('../middleware/uploadMiddleware');
const { uploadMessageSchema } = require('../schemas/messageSchemas');
const { signMediaUrlsInMessage } = require('../services/mediaAccessService');

const emitMessageCreated = (io, message) => {
  const signedMessage = signMediaUrlsInMessage(message);
  io.to(`conversation:${signedMessage.conversationId}`).emit('message:new', signedMessage);
  io.to(`user:${signedMessage.senderId}`).emit('message:new', signedMessage);
  io.to(`user:${signedMessage.recipientId}`).emit('message:new', signedMessage);
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

const listMessages = asyncHandler(async (req, res) => {
  const { conversationId } = req.params;
  const { limit = 40, before } = req.query;

  const messages = await listConversationMessages({
    userId: req.user.id,
    conversationId,
    limit,
    before: before ? new Date(before).toISOString() : null,
  });

  res.status(200).json({
    messages: messages.map((message) => signMediaUrlsInMessage(message)),
  });
});

const sendTextMessage = asyncHandler(async (req, res) => {
  const { conversationId } = req.params;
  const { body, clientId, replyToMessageId } = req.body;

  const message = await createConversationMessage({
    conversationId,
    senderId: req.user.id,
    replyToMessageId,
    type: 'text',
    body,
    clientId,
  });

  const deliveredUpdates = await markDeliveredIfRecipientOnline(message);
  const io = req.app.locals.io;

  emitMessageCreated(io, message);
  emitDeliveredUpdates(io, deliveredUpdates);
  await sendPushToRecipientIfOffline(message);

  res.status(201).json({
    message: signMediaUrlsInMessage(message),
  });
});

const sendUploadedMessage = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new HttpError(400, 'File is required');
  }

  const parsedBody = uploadMessageSchema.safeParse(req.body || {});

  if (!parsedBody.success) {
    throw new HttpError(400, 'Validation failed', parsedBody.error.issues);
  }

  const { conversationId } = req.params;
  const { type: requestedType, body, voiceDurationMs, clientId, replyToMessageId } = parsedBody.data;

  const resolvedType = inferMessageType(req.file.mimetype, requestedType);
  const uploaded = await uploadBuffer({
    buffer: req.file.buffer,
    originalName: req.file.originalname,
    mimeType: req.file.mimetype,
    folder: resolvedType,
  });

  const message = await createConversationMessage({
    conversationId,
    senderId: req.user.id,
    replyToMessageId,
    type: resolvedType,
    body,
    mediaUrl: uploaded.url,
    mediaName: req.file.originalname,
    mediaMime: req.file.mimetype,
    mediaSize: req.file.size,
    voiceDurationMs: resolvedType === 'voice' ? voiceDurationMs || 0 : null,
    clientId,
  });

  const deliveredUpdates = await markDeliveredIfRecipientOnline(message);
  const io = req.app.locals.io;

  emitMessageCreated(io, message);
  emitDeliveredUpdates(io, deliveredUpdates);
  await sendPushToRecipientIfOffline(message);

  res.status(201).json({
    message: signMediaUrlsInMessage(message),
  });
});

const markSeen = asyncHandler(async (req, res) => {
  const { conversationId } = req.params;
  const { messageIds } = req.body;

  const updates = await markConversationSeenForUser({
    userId: req.user.id,
    conversationId,
    messageIds,
  });

  emitSeenUpdates(req.app.locals.io, updates);

  res.status(200).json({
    updates,
  });
});

const toggleReaction = asyncHandler(async (req, res) => {
  const { messageId } = req.params;
  const { emoji } = req.body;

  const update = await toggleReactionForMessage({
    userId: req.user.id,
    messageId,
    emoji,
  });

  req.app.locals.io.to(`conversation:${update.conversationId}`).emit('message:reaction', update);
  req.app.locals.io.to(`user:${req.user.id}`).emit('message:reaction', update);

  res.status(200).json({ update });
});

module.exports = {
  listMessages,
  sendTextMessage,
  sendUploadedMessage,
  markSeen,
  toggleReaction,
  emitMessageCreated,
  emitDeliveredUpdates,
  emitSeenUpdates,
};
