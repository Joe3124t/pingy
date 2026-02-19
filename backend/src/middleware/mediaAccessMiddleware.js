const { verifyLocalMediaSignature } = require('../services/mediaAccessService');

const signedMediaAccessMiddleware = (req, res, next) => {
  const path = `/uploads${req.path || ''}`;
  const { exp, sig } = req.query || {};

  const ok = verifyLocalMediaSignature({
    path,
    expiresAt: exp,
    signature: sig,
  });

  if (!ok) {
    res.status(403).json({
      message: 'Media link expired or invalid',
    });
    return;
  }

  next();
};

module.exports = {
  signedMediaAccessMiddleware,
};
