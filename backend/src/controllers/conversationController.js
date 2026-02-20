const { asyncHandler } = require('../utils/asyncHandler');
const {
  createOrGetDirectConversation,
  listConversationsForUser,
  findConversationForUser,
  softDeleteConversation,
  softDeleteConversationForEveryone,
  isUserInConversation,
  setConversationWallpaperSettings,
  resetConversationWallpaperSettings,
} = require('../models/conversationModel');
const { findUserById, searchUsers } = require('../models/userModel');
const { assertUsersCanInteract } = require('../services/blockService');
const { signMediaUrl, signMediaUrlsInUser } = require('../services/mediaAccessService');
const { HttpError } = require('../utils/httpError');
const { uploadBuffer } = require('../services/storageService');
const { normalizePhoneNumber } = require('../utils/phone');

const emitConversationWallpaperUpdate = (req, { conversationId, wallpaperUrl, blurIntensity }) => {
  const io = req.app?.locals?.io;

  if (!io || !conversationId) {
    return;
  }

  io.to(`conversation:${conversationId}`).emit('conversation:wallpaper', {
    conversationId,
    wallpaperUrl: signMediaUrl(wallpaperUrl),
    blurIntensity: Number(blurIntensity || 0),
  });
};

const parseBlurIntensity = (value) => {
  if (value === undefined || value === null || String(value).trim() === '') {
    return 0;
  }

  const numeric = Number(value);

  if (!Number.isInteger(numeric) || numeric < 0 || numeric > 20) {
    throw new HttpError(400, 'blurIntensity must be an integer between 0 and 20');
  }

  return numeric;
};

const listConversations = asyncHandler(async (req, res) => {
  const conversations = (await listConversationsForUser(req.user.id)).map((conversation) => ({
    ...conversation,
    participantAvatarUrl: signMediaUrl(conversation.participantAvatarUrl),
    wallpaperUrl: signMediaUrl(conversation.wallpaperUrl),
  }));

  res.status(200).json({
    conversations,
  });
});

const createDirectConversation = asyncHandler(async (req, res) => {
  const { recipientId } = req.body;

  if (recipientId === req.user.id) {
    throw new HttpError(400, 'You cannot create a conversation with yourself');
  }

  const recipient = await findUserById(recipientId);

  if (!recipient) {
    throw new HttpError(404, 'Recipient not found');
  }

  await assertUsersCanInteract({
    firstUserId: req.user.id,
    secondUserId: recipientId,
  });

  const conversation = await createOrGetDirectConversation({
    userId: req.user.id,
    recipientId,
  });

  const hydratedConversation = await findConversationForUser({
    conversationId: conversation.id,
    userId: req.user.id,
  });

  if (!hydratedConversation) {
    throw new HttpError(500, 'Conversation created but hydration failed');
  }

  res.status(201).json({
    conversation: {
      ...hydratedConversation,
      participantAvatarUrl: signMediaUrl(hydratedConversation.participantAvatarUrl),
      wallpaperUrl: signMediaUrl(hydratedConversation.wallpaperUrl),
    },
  });
});

const searchUsersController = asyncHandler(async (req, res) => {
  const { query: queryText, limit = 15 } = req.query;
  const phoneNumber = normalizePhoneNumber(queryText);

  const users = await searchUsers({
    currentUserId: req.user.id,
    phoneNumber,
    limit,
  });

  res.status(200).json({
    users: users.map((user) => signMediaUrlsInUser(user)),
  });
});

const deleteConversation = asyncHandler(async (req, res) => {
  const { conversationId } = req.params;
  const scope = req.query.scope === 'both' ? 'both' : 'self';

  const isParticipant = await isUserInConversation({
    conversationId,
    userId: req.user.id,
  });

  if (!isParticipant) {
    throw new HttpError(403, 'You do not have access to this conversation');
  }

  if (scope === 'both') {
    await softDeleteConversationForEveryone({
      conversationId,
    });
  } else {
    await softDeleteConversation({
      conversationId,
      userId: req.user.id,
    });
  }

  res.status(204).send();
});

const updateConversationWallpaper = asyncHandler(async (req, res) => {
  const { conversationId } = req.params;
  const { wallpaperUrl, blurIntensity } = req.body;

  const isParticipant = await isUserInConversation({
    conversationId,
    userId: req.user.id,
  });

  if (!isParticipant) {
    throw new HttpError(403, 'You do not have access to this conversation');
  }

  const settings = await setConversationWallpaperSettings({
    conversationId,
    wallpaperUrl,
    blurIntensity,
  });

  emitConversationWallpaperUpdate(req, {
    conversationId,
    wallpaperUrl: settings?.wallpaperUrl || null,
    blurIntensity: settings?.blurIntensity || 0,
  });

  res.status(200).json({
    settings: {
      ...settings,
      wallpaperUrl: signMediaUrl(settings?.wallpaperUrl),
    },
  });
});

const resetConversationWallpaper = asyncHandler(async (req, res) => {
  const { conversationId } = req.params;

  const isParticipant = await isUserInConversation({
    conversationId,
    userId: req.user.id,
  });

  if (!isParticipant) {
    throw new HttpError(403, 'You do not have access to this conversation');
  }

  await resetConversationWallpaperSettings({
    conversationId,
  });

  emitConversationWallpaperUpdate(req, {
    conversationId,
    wallpaperUrl: null,
    blurIntensity: 0,
  });

  res.status(204).send();
});

const uploadConversationWallpaper = asyncHandler(async (req, res) => {
  const { conversationId } = req.params;

  const isParticipant = await isUserInConversation({
    conversationId,
    userId: req.user.id,
  });

  if (!isParticipant) {
    throw new HttpError(403, 'You do not have access to this conversation');
  }

  if (!req.file) {
    throw new HttpError(400, 'Wallpaper file is required');
  }

  const uploaded = await uploadBuffer({
    buffer: req.file.buffer,
    originalName: req.file.originalname,
    mimeType: req.file.mimetype,
    folder: 'wallpapers/conversations',
  });

  const settings = await setConversationWallpaperSettings({
    conversationId,
    wallpaperUrl: uploaded.url,
    blurIntensity: parseBlurIntensity(req.body?.blurIntensity),
  });

  emitConversationWallpaperUpdate(req, {
    conversationId,
    wallpaperUrl: settings?.wallpaperUrl || null,
    blurIntensity: settings?.blurIntensity || 0,
  });

  res.status(200).json({
    settings: {
      ...settings,
      wallpaperUrl: signMediaUrl(settings?.wallpaperUrl),
    },
  });
});

module.exports = {
  listConversations,
  createDirectConversation,
  searchUsersController,
  deleteConversation,
  updateConversationWallpaper,
  resetConversationWallpaper,
  uploadConversationWallpaper,
};
