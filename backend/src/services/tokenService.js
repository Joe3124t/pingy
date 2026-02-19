const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { env } = require('../config/env');

const signAccessToken = ({ id, username, phoneNumber, deviceId }) => {
  return jwt.sign(
    {
      sub: id,
      username,
      phoneNumber,
      deviceId,
    },
    env.ACCESS_TOKEN_SECRET,
    {
      expiresIn: env.ACCESS_TOKEN_TTL,
    },
  );
};

const verifyAccessToken = (token) => jwt.verify(token, env.ACCESS_TOKEN_SECRET);

const generateRefreshToken = () => {
  const randomPart = crypto.randomBytes(48).toString('hex');
  return `${uuidv4()}-${randomPart}`;
};

const hashRefreshToken = (refreshToken) => {
  return crypto.createHmac('sha256', env.REFRESH_TOKEN_SECRET).update(refreshToken).digest('hex');
};

const getRefreshTokenExpiryDate = () => {
  const expires = new Date();
  expires.setDate(expires.getDate() + env.REFRESH_TOKEN_DAYS);
  return expires;
};

module.exports = {
  signAccessToken,
  verifyAccessToken,
  generateRefreshToken,
  hashRefreshToken,
  getRefreshTokenExpiryDate,
};
