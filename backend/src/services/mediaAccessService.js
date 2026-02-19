const crypto = require('node:crypto');
const { env } = require('../config/env');

const remoteMediaPrefix = 'remote:';

const normalizeMediaPath = (mediaUrl) => {
  if (!mediaUrl) {
    return null;
  }

  try {
    const url = new URL(mediaUrl);
    return url.pathname;
  } catch {
    return mediaUrl.startsWith('/') ? mediaUrl : `/${mediaUrl}`;
  }
};

const isHttpMediaUrl = (value) => /^https?:\/\//i.test(String(value || ''));

const buildSignatureSecret = () => env.MEDIA_ACCESS_SECRET || env.ACCESS_TOKEN_SECRET;

const createMediaSignature = ({ path, expiresAt }) => {
  const payload = `${path}|${expiresAt}`;
  return crypto.createHmac('sha256', buildSignatureSecret()).update(payload).digest('hex');
};

const decodeRemoteMediaToken = (mediaToken) => {
  try {
    const decoded = Buffer.from(String(mediaToken), 'base64url').toString('utf8');
    return isHttpMediaUrl(decoded) ? decoded : null;
  } catch {
    return null;
  }
};

const signLocalMediaUrl = (mediaUrl, ttlSeconds = env.MEDIA_URL_TTL_SECONDS) => {
  const path = normalizeMediaPath(mediaUrl);

  if (!path || !path.startsWith('/uploads/')) {
    return mediaUrl;
  }

  const expiresAt = Math.floor(Date.now() / 1000) + ttlSeconds;
  const signature = createMediaSignature({ path, expiresAt });
  const separator = path.includes('?') ? '&' : '?';

  return `${path}${separator}exp=${expiresAt}&sig=${signature}`;
};

const signRemoteMediaUrl = (mediaUrl, ttlSeconds = env.MEDIA_URL_TTL_SECONDS) => {
  if (!isHttpMediaUrl(mediaUrl)) {
    return mediaUrl;
  }

  const expiresAt = Math.floor(Date.now() / 1000) + ttlSeconds;
  const mediaToken = Buffer.from(String(mediaUrl), 'utf8').toString('base64url');
  const signature = createMediaSignature({
    path: `${remoteMediaPrefix}${mediaToken}`,
    expiresAt,
  });

  return `/api/media/access?m=${encodeURIComponent(mediaToken)}&exp=${expiresAt}&sig=${signature}`;
};

const verifyLocalMediaSignature = ({ path, expiresAt, signature }) => {
  if (!path || !expiresAt || !signature) {
    return false;
  }

  const now = Math.floor(Date.now() / 1000);
  const expires = Number(expiresAt);

  if (!Number.isFinite(expires) || expires < now) {
    return false;
  }

  const expected = createMediaSignature({ path, expiresAt: expires });
  const expectedBuffer = Buffer.from(expected);
  const givenBuffer = Buffer.from(String(signature));

  if (expectedBuffer.length !== givenBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(expectedBuffer, givenBuffer);
};

const verifyRemoteMediaSignature = ({ mediaToken, expiresAt, signature }) => {
  if (!mediaToken || !expiresAt || !signature) {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  const expires = Number(expiresAt);

  if (!Number.isFinite(expires) || expires < now) {
    return null;
  }

  const expected = createMediaSignature({
    path: `${remoteMediaPrefix}${mediaToken}`,
    expiresAt: expires,
  });
  const expectedBuffer = Buffer.from(expected);
  const givenBuffer = Buffer.from(String(signature));

  if (expectedBuffer.length !== givenBuffer.length) {
    return null;
  }

  if (!crypto.timingSafeEqual(expectedBuffer, givenBuffer)) {
    return null;
  }

  return decodeRemoteMediaToken(mediaToken);
};

const signMediaUrlsInMessage = (message) => {
  if (!message || !message.mediaUrl) {
    return message;
  }

  return {
    ...message,
    mediaUrl: signLocalMediaUrl(message.mediaUrl),
  };
};

const signMediaUrl = (value) => {
  const normalizedPath = normalizeMediaPath(value);

  if (normalizedPath && normalizedPath.startsWith('/uploads/')) {
    return signLocalMediaUrl(value);
  }

  if (isHttpMediaUrl(value)) {
    return signRemoteMediaUrl(value);
  }

  return value;
};

const signMediaUrlsInUser = (user) => {
  if (!user || !user.avatarUrl) {
    return user;
  }

  return {
    ...user,
    avatarUrl: signLocalMediaUrl(user.avatarUrl),
  };
};

module.exports = {
  signLocalMediaUrl,
  verifyLocalMediaSignature,
  verifyRemoteMediaSignature,
  signRemoteMediaUrl,
  signMediaUrl,
  signMediaUrlsInMessage,
  signMediaUrlsInUser,
};
