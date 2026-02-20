const multer = require('multer');
const { env } = require('../config/env');
const { HttpError } = require('../utils/httpError');

const MIME_BY_TYPE = {
  image: new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
  video: new Set(['video/mp4', 'video/quicktime', 'video/x-m4v']),
  file: new Set([
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ]),
  voice: new Set([
    'audio/webm',
    'audio/ogg',
    'audio/mpeg',
    'audio/mp4',
    'audio/wav',
    'audio/x-wav',
    'audio/wave',
  ]),
};

const allAllowedMimeTypes = new Set([
  ...MIME_BY_TYPE.image,
  ...MIME_BY_TYPE.video,
  ...MIME_BY_TYPE.file,
  ...MIME_BY_TYPE.voice,
]);

const inferMessageType = (mimeType, requestedType) => {
  if (requestedType === 'voice') {
    if (!MIME_BY_TYPE.voice.has(mimeType)) {
      throw new HttpError(400, 'Voice uploads must be an audio format');
    }

    return 'voice';
  }

  if (MIME_BY_TYPE.image.has(mimeType)) {
    return 'image';
  }

  if (MIME_BY_TYPE.video.has(mimeType)) {
    return 'video';
  }

  if (MIME_BY_TYPE.voice.has(mimeType)) {
    return 'voice';
  }

  if (MIME_BY_TYPE.file.has(mimeType)) {
    return 'file';
  }

  throw new HttpError(400, 'Unsupported file type');
};

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: env.MAX_FILE_SIZE_MB * 1024 * 1024,
  },
  fileFilter: (req, file, callback) => {
    if (!allAllowedMimeTypes.has(file.mimetype)) {
      return callback(new HttpError(400, `Unsupported MIME type: ${file.mimetype}`));
    }

    return callback(null, true);
  },
});

module.exports = {
  upload,
  inferMessageType,
  allAllowedMimeTypes,
};
