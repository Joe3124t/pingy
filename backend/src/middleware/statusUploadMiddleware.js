const multer = require('multer');
const { env } = require('../config/env');
const { HttpError } = require('../utils/httpError');

const allowedStatusMimeTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'video/mp4',
  'video/quicktime',
  'video/x-m4v',
]);

const inferStatusContentType = (mimeType) => {
  const normalized = String(mimeType || '').toLowerCase();

  if (normalized.startsWith('image/')) {
    return 'image';
  }

  if (normalized.startsWith('video/')) {
    return 'video';
  }

  throw new HttpError(400, 'Status media must be an image or video');
};

const statusUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: env.MAX_FILE_SIZE_MB * 1024 * 1024,
  },
  fileFilter: (req, file, callback) => {
    if (!allowedStatusMimeTypes.has(String(file.mimetype || '').toLowerCase())) {
      return callback(new HttpError(400, `Unsupported status media type: ${file.mimetype}`));
    }

    return callback(null, true);
  },
});

module.exports = {
  statusUpload,
  inferStatusContentType,
};
