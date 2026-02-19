const { asyncHandler } = require('../utils/asyncHandler');
const { findUserById } = require('../models/userModel');
const { findUserPublicKey, upsertUserPublicKey } = require('../models/userKeyModel');
const { HttpError } = require('../utils/httpError');

const upsertMyPublicKey = asyncHandler(async (req, res) => {
  const { publicKeyJwk, algorithm } = req.body;

  const key = await upsertUserPublicKey({
    userId: req.user.id,
    deviceId: req.auth?.deviceId || null,
    publicKeyJwk,
    algorithm: algorithm || 'ECDH-Curve25519',
  });

  res.status(200).json({ key });
});

const getUserPublicKey = asyncHandler(async (req, res) => {
  const { userId } = req.params;
  const user = await findUserById(userId);

  if (!user) {
    throw new HttpError(404, 'User not found');
  }

  const key = await findUserPublicKey(userId);

  if (!key) {
    throw new HttpError(404, 'Public key not found');
  }

  res.status(200).json({ key });
});

const getMyPublicKey = asyncHandler(async (req, res) => {
  const key = await findUserPublicKey(req.user.id);

  res.status(200).json({
    key: key || null,
  });
});

module.exports = {
  upsertMyPublicKey,
  getUserPublicKey,
  getMyPublicKey,
};
