const { asyncHandler } = require('../utils/asyncHandler');
const { HttpError } = require('../utils/httpError');
const { uploadBuffer } = require('../services/storageService');
const {
  findUserById,
  isUsernameAvailable,
  updateUserProfile,
  setUserAvatar,
  updateUserPrivacySettings,
  updateUserChatSettings,
  deleteUserById,
} = require('../models/userModel');
const {
  upsertUserPushSubscription,
  deleteUserPushSubscriptionByEndpoint,
} = require('../models/pushSubscriptionModel');
const { listConversationIdsForUser } = require('../models/conversationModel');
const {
  blockTargetUser,
  unblockTargetUser,
  getBlockedUsersForUser,
} = require('../services/blockService');
const { signMediaUrl, signMediaUrlsInUser } = require('../services/mediaAccessService');
const { isWebPushConfigured, getWebPushPublicKey } = require('../services/pushService');

const emitProfileUpdateToContacts = async (req, user) => {
  const io = req.app?.locals?.io;

  if (!io || !user?.id) {
    return;
  }

  const payload = {
    userId: user.id,
    username: user.username,
    avatarUrl: signMediaUrl(user.avatarUrl),
  };

  io.to(`user:${user.id}`).emit('profile:update', payload);

  const conversationIds = await listConversationIdsForUser(user.id);

  conversationIds.forEach((conversationId) => {
    io.to(`conversation:${conversationId}`).emit('profile:update', payload);
  });
};

const getMySettings = asyncHandler(async (req, res) => {
  const user = await findUserById(req.user.id);
  const blockedUsers = await getBlockedUsersForUser(req.user.id);

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(user),
      defaultWallpaperUrl: signMediaUrl(user?.defaultWallpaperUrl),
    },
    blockedUsers: blockedUsers.map((entry) => signMediaUrlsInUser(entry)),
  });
});

const updateProfileSettings = asyncHandler(async (req, res) => {
  const { username, bio } = req.body;

  if (username) {
    const available = await isUsernameAvailable({
      username,
      excludeUserId: req.user.id,
    });

    if (!available) {
      throw new HttpError(409, 'Username is already in use');
    }
  }

  const user = await updateUserProfile({
    userId: req.user.id,
    username,
    bio,
  });

  await emitProfileUpdateToContacts(req, user);

  res.status(200).json({ user: signMediaUrlsInUser(user) });
});

const uploadAvatar = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new HttpError(400, 'Avatar file is required');
  }

  const uploaded = await uploadBuffer({
    buffer: req.file.buffer,
    originalName: req.file.originalname,
    mimeType: req.file.mimetype,
    folder: 'avatars',
  });

  const user = await setUserAvatar({
    userId: req.user.id,
    avatarUrl: uploaded.url,
  });

  await emitProfileUpdateToContacts(req, user);

  res.status(200).json({ user: signMediaUrlsInUser(user) });
});

const uploadDefaultWallpaper = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new HttpError(400, 'Wallpaper file is required');
  }

  const uploaded = await uploadBuffer({
    buffer: req.file.buffer,
    originalName: req.file.originalname,
    mimeType: req.file.mimetype,
    folder: 'wallpapers/default',
  });

  const user = await updateUserChatSettings({
    userId: req.user.id,
    defaultWallpaperUrl: uploaded.url,
    hasDefaultWallpaperUrl: true,
  });

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(user),
      defaultWallpaperUrl: signMediaUrl(user?.defaultWallpaperUrl),
    },
  });
});

const updatePrivacySettings = asyncHandler(async (req, res) => {
  const { showOnlineStatus, readReceiptsEnabled } = req.body;

  const user = await updateUserPrivacySettings({
    userId: req.user.id,
    showOnlineStatus,
    readReceiptsEnabled,
  });

  res.status(200).json({ user: signMediaUrlsInUser(user) });
});

const updateChatSettings = asyncHandler(async (req, res) => {
  const { themeMode, defaultWallpaperUrl } = req.body;
  const hasDefaultWallpaperUrl = Object.prototype.hasOwnProperty.call(
    req.body || {},
    'defaultWallpaperUrl',
  );

  const user = await updateUserChatSettings({
    userId: req.user.id,
    themeMode,
    defaultWallpaperUrl,
    hasDefaultWallpaperUrl,
  });

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(user),
      defaultWallpaperUrl: signMediaUrl(user?.defaultWallpaperUrl),
    },
  });
});

const blockUserController = asyncHandler(async (req, res) => {
  await blockTargetUser({
    blockerId: req.user.id,
    blockedId: req.params.userId,
  });

  const blockedUsers = await getBlockedUsersForUser(req.user.id);

  res.status(200).json({
    blockedUsers: blockedUsers.map((entry) => signMediaUrlsInUser(entry)),
  });
});

const unblockUserController = asyncHandler(async (req, res) => {
  await unblockTargetUser({
    blockerId: req.user.id,
    blockedId: req.params.userId,
  });

  const blockedUsers = await getBlockedUsersForUser(req.user.id);

  res.status(200).json({
    blockedUsers: blockedUsers.map((entry) => signMediaUrlsInUser(entry)),
  });
});

const listBlockedUsersController = asyncHandler(async (req, res) => {
  const blockedUsers = await getBlockedUsersForUser(req.user.id);

  res.status(200).json({
    blockedUsers: blockedUsers.map((entry) => signMediaUrlsInUser(entry)),
  });
});

const deleteMyAccount = asyncHandler(async (req, res) => {
  const deleted = await deleteUserById(req.user.id);

  if (!deleted) {
    throw new HttpError(404, 'User not found');
  }

  res.status(204).send();
});

const getPushPublicKeyController = asyncHandler(async (req, res) => {
  res.status(200).json({
    enabled: isWebPushConfigured(),
    publicKey: getWebPushPublicKey(),
  });
});

const saveMyPushSubscriptionController = asyncHandler(async (req, res) => {
  if (!isWebPushConfigured()) {
    throw new HttpError(503, 'Push notifications are not configured on server');
  }

  const subscription = req.body?.subscription;

  await upsertUserPushSubscription({
    userId: req.user.id,
    endpoint: subscription.endpoint,
    p256dh: subscription.keys.p256dh,
    auth: subscription.keys.auth,
    userAgent: req.headers['user-agent'] || null,
  });

  res.status(200).json({ ok: true });
});

const deleteMyPushSubscriptionController = asyncHandler(async (req, res) => {
  const endpoint = String(req.body?.endpoint || '').trim();

  if (!endpoint) {
    throw new HttpError(400, 'Subscription endpoint is required');
  }

  await deleteUserPushSubscriptionByEndpoint({
    userId: req.user.id,
    endpoint,
  });

  res.status(200).json({ ok: true });
});

module.exports = {
  getMySettings,
  updateProfileSettings,
  uploadAvatar,
  uploadDefaultWallpaper,
  updatePrivacySettings,
  updateChatSettings,
  blockUserController,
  unblockUserController,
  listBlockedUsersController,
  deleteMyAccount,
  getPushPublicKeyController,
  saveMyPushSubscriptionController,
  deleteMyPushSubscriptionController,
};
