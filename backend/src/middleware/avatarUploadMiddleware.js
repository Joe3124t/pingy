const multer = require('multer');
const { HttpError } = require('../utils/httpError');

const allowedAvatarMimeTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
]);

const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
  fileFilter: (req, file, callback) => {
    if (!allowedAvatarMimeTypes.has(file.mimetype)) {
      return callback(new HttpError(400, `Unsupported avatar MIME type: ${file.mimetype}`));
    }

    return callback(null, true);
  },
});

module.exports = {
  avatarUpload,
};
