const { verifyAccessToken } = require('../services/tokenService');
const { findUserAuthById } = require('../models/userModel');
const { HttpError } = require('../utils/httpError');

const extractBearerToken = (authorizationHeader = '') => {
  if (!authorizationHeader.startsWith('Bearer ')) {
    return null;
  }

  return authorizationHeader.slice('Bearer '.length).trim();
};

const authMiddleware = async (req, res, next) => {
  try {
    const token = extractBearerToken(req.headers.authorization || '');

    if (!token) {
      throw new HttpError(401, 'Missing access token');
    }

    const payload = verifyAccessToken(token);
    const user = await findUserAuthById(payload.sub);

    if (!user) {
      throw new HttpError(401, 'User no longer exists');
    }

    if (user.currentDeviceId && String(user.currentDeviceId) !== String(payload.deviceId || '')) {
      throw new HttpError(401, 'Session is no longer active on this device');
    }

    req.auth = {
      userId: user.id,
      deviceId: user.currentDeviceId || payload.deviceId || null,
    };

    delete user.passwordHash;
    delete user.currentDeviceId;
    delete user.totpSecretEnc;
    delete user.totpPendingSecretEnc;
    delete user.totpPendingExpiresAt;
    delete user.totpConfirmedAt;
    req.user = user;
    next();
  } catch (error) {
    next(new HttpError(401, 'Unauthorized'));
  }
};

module.exports = {
  authMiddleware,
  extractBearerToken,
};
