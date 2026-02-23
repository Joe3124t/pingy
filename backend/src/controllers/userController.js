const crypto = require('node:crypto');
const bcrypt = require('bcrypt');
const { asyncHandler } = require('../utils/asyncHandler');
const { HttpError } = require('../utils/httpError');
const { uploadBuffer } = require('../services/storageService');
const { env } = require('../config/env');
const {
  findUserById,
  findUserAuthById,
  findUserByPhoneWithPassword,
  listUsersVisibleToViewer,
  upsertUserContactHashes,
  isUsernameAvailable,
  setUserOnlineStatus,
  filterVisiblePresenceUserIds,
  updateUserProfile,
  updateUserPhoneNumber,
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
const { consumeRecoveryCodeHash } = require('../models/userTotpModel');
const { verifyTotpCode, decryptTotpSecret, hashRecoveryCode } = require('../crypto/totp');
const { signMediaUrl, signMediaUrlsInUser } = require('../services/mediaAccessService');
const { normalizePhoneNumber } = require('../utils/phone');
const {
  isWebPushConfigured,
  isAPNsConfigured,
  isPushDeliveryConfigured,
  getWebPushPublicKey,
} = require('../services/pushService');
const { getOnlineUserIds } = require('../services/presenceService');

const sha256Hex = (value) => crypto.createHash('sha256').update(String(value)).digest('hex');

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

const toISOStringSafe = (value) => {
  if (!value) {
    return null;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  const candidate = new Date(value);
  if (!Number.isNaN(candidate.getTime())) {
    return candidate.toISOString();
  }

  return null;
};

const emitPresenceUpdateToVisibleViewers = async ({
  req,
  subjectUserId,
  isOnline,
  lastSeen,
}) => {
  const io = req.app?.locals?.io;
  if (!io || !subjectUserId) {
    return;
  }

  const onlineViewerIds = getOnlineUserIds();
  if (!onlineViewerIds.length) {
    return;
  }

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

  const normalizedLastSeen = toISOStringSafe(lastSeen) || new Date().toISOString();

  checks.forEach((entry) => {
    if (!entry.canSee) {
      return;
    }

    io.to(`user:${entry.viewerUserId}`).emit('presence:update', {
      userId: subjectUserId,
      isOnline: Boolean(isOnline),
      lastSeen: isOnline ? null : normalizedLastSeen,
    });
  });
};

const getMySettings = asyncHandler(async (req, res) => {
  const user = await findUserById(req.user.id);
  const blockedUsers = await getBlockedUsersForUser(req.user.id);

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(user),
      deviceId: req.auth?.deviceId || null,
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

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(user),
      deviceId: req.auth?.deviceId || null,
    },
  });
});

const normalizeRecoveryCode = (value) =>
  String(value || '')
    .trim()
    .toUpperCase();

const changePhoneNumberController = asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const normalizedPhone = normalizePhoneNumber(req.body?.newPhoneNumber);
  const currentPassword = String(req.body?.currentPassword || '');
  const totpCode = req.body?.totpCode ? String(req.body.totpCode).trim() : '';
  const recoveryCode = req.body?.recoveryCode ? String(req.body.recoveryCode).trim() : '';

  const userAuth = await findUserAuthById(userId);
  if (!userAuth) {
    throw new HttpError(404, 'User not found');
  }

  if (String(userAuth.phoneNumber || '') === normalizedPhone) {
    throw new HttpError(400, 'New phone number must be different from current number');
  }

  const currentPasswordMatches = await bcrypt.compare(currentPassword, userAuth.passwordHash);
  if (!currentPasswordMatches) {
    throw new HttpError(401, 'Current password is incorrect');
  }

  if (env.TOTP_ENABLED && userAuth.totpEnabled && userAuth.totpSecretEnc) {
    if (!totpCode && !recoveryCode) {
      throw new HttpError(401, 'Authenticator code or recovery code is required');
    }

    let verified = false;

    if (totpCode) {
      const secret = decryptTotpSecret(userAuth.totpSecretEnc);
      verified = verifyTotpCode({ secret, code: totpCode });
    } else if (recoveryCode) {
      verified = await consumeRecoveryCodeHash({
        userId,
        codeHash: hashRecoveryCode(normalizeRecoveryCode(recoveryCode)),
      });
    }

    if (!verified) {
      throw new HttpError(401, 'Invalid authenticator code');
    }
  }

  const existing = await findUserByPhoneWithPassword(normalizedPhone);
  if (existing && existing.id !== userId) {
    throw new HttpError(409, 'Phone number is already in use');
  }

  let updatedUser;
  try {
    updatedUser = await updateUserPhoneNumber({
      userId,
      phoneNumber: normalizedPhone,
    });
  } catch (error) {
    if (error?.code === '23505') {
      throw new HttpError(409, 'Phone number is already in use');
    }
    throw error;
  }

  if (!updatedUser) {
    throw new HttpError(404, 'User not found');
  }

  await emitProfileUpdateToContacts(req, updatedUser);

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(updatedUser),
      deviceId: req.auth?.deviceId || null,
    },
    message: 'Phone number updated successfully',
  });
});

const uploadAvatar = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new HttpError(400, 'Avatar file is required');
  }

  if (!req.file.mimetype || !req.file.mimetype.startsWith('image/')) {
    throw new HttpError(400, 'Avatar must be a valid image format');
  }

  let uploaded;
  try {
    uploaded = await uploadBuffer({
      buffer: req.file.buffer,
      originalName: req.file.originalname || `avatar-${Date.now()}`,
      mimeType: req.file.mimetype,
      folder: 'avatars',
    });
  } catch (error) {
    throw new HttpError(500, 'Avatar upload failed. Please retry with another image.');
  }

  const user = await setUserAvatar({
    userId: req.user.id,
    avatarUrl: uploaded.url,
  });

  await emitProfileUpdateToContacts(req, user);

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(user),
      deviceId: req.auth?.deviceId || null,
    },
  });
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
      deviceId: req.auth?.deviceId || null,
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

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(user),
      deviceId: req.auth?.deviceId || null,
    },
  });
});

const updateMyPresenceController = asyncHandler(async (req, res) => {
  const isOnline = Boolean(req.body?.isOnline);
  const user = await setUserOnlineStatus({
    userId: req.user.id,
    isOnline,
  });

  await emitPresenceUpdateToVisibleViewers({
    req,
    subjectUserId: req.user.id,
    isOnline,
    lastSeen: user?.lastSeen || null,
  });

  res.status(200).json({
    ok: true,
    presence: {
      isOnline,
      lastSeen: isOnline ? null : toISOStringSafe(user?.lastSeen) || new Date().toISOString(),
    },
  });
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
      deviceId: req.auth?.deviceId || null,
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

const syncContactsController = asyncHandler(async (req, res) => {
  const contacts = req.body?.contacts || [];
  const labelByHash = new Map();

  contacts.forEach((entry) => {
    const hash = String(entry.hash || '').toLowerCase();
    const label = String(entry.label || '').trim();
    if (!hash || !label) {
      return;
    }
    if (!labelByHash.has(hash)) {
      labelByHash.set(hash, label);
    }
  });

  if (labelByHash.size === 0) {
    res.status(200).json({ matches: [] });
    return;
  }

  await upsertUserContactHashes({
    userId: req.user.id,
    contacts: Array.from(labelByHash.entries()).map(([hash, label]) => ({ hash, label })),
  });

  const users = await listUsersVisibleToViewer({
    viewerUserId: req.user.id,
    limit: 5000,
  });

  const matches = [];

  users.forEach((user) => {
    if (!user?.phoneNumber) {
      return;
    }

    let normalizedPhone;
    try {
      normalizedPhone = normalizePhoneNumber(user.phoneNumber);
    } catch {
      return;
    }

    const hash = sha256Hex(normalizedPhone);
    const contactName = labelByHash.get(hash);
    if (!contactName) {
      return;
    }

    const signedUser = signMediaUrlsInUser(user);
    matches.push({
      hash,
      contactName,
      user: {
        id: signedUser.id,
        username: signedUser.username,
        avatarUrl: signedUser.avatarUrl || null,
        bio: signedUser.bio || null,
        isOnline: Boolean(signedUser.isOnline),
        lastSeen: signedUser.lastSeen || null,
      },
    });
  });

  res.status(200).json({ matches });
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
    enabled: isPushDeliveryConfigured(),
    apnsEnabled: isAPNsConfigured(),
    webPushEnabled: isWebPushConfigured(),
    publicKey: getWebPushPublicKey(),
  });
});

const saveMyPushSubscriptionController = asyncHandler(async (req, res) => {
  if (!isPushDeliveryConfigured()) {
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
  changePhoneNumberController,
  uploadAvatar,
  uploadDefaultWallpaper,
  updatePrivacySettings,
  updateMyPresenceController,
  updateChatSettings,
  blockUserController,
  unblockUserController,
  listBlockedUsersController,
  syncContactsController,
  deleteMyAccount,
  getPushPublicKeyController,
  saveMyPushSubscriptionController,
  deleteMyPushSubscriptionController,
};
