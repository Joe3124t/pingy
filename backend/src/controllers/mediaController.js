const { asyncHandler } = require('../utils/asyncHandler');
const { HttpError } = require('../utils/httpError');
const { verifyRemoteMediaSignature } = require('../services/mediaAccessService');

const accessSignedMedia = asyncHandler(async (req, res) => {
  const { m, exp, sig } = req.query || {};
  const remoteUrl = verifyRemoteMediaSignature({
    mediaToken: m,
    expiresAt: exp,
    signature: sig,
  });

  if (!remoteUrl) {
    throw new HttpError(403, 'Media link expired or invalid');
  }

  res.setHeader('Cache-Control', 'private, max-age=60');
  res.redirect(302, remoteUrl);
});

module.exports = {
  accessSignedMedia,
};
