const { verifyAccessToken } = require('../services/tokenService');
const { findUserById } = require('../models/userModel');
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
    const user = await findUserById(payload.sub);

    if (!user) {
      throw new HttpError(401, 'User no longer exists');
    }

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
