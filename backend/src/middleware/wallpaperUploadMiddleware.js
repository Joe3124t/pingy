const multer = require('multer');
const { HttpError } = require('../utils/httpError');

const allowedWallpaperMimeTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

const wallpaperUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024,
  },
  fileFilter: (req, file, callback) => {
    if (!allowedWallpaperMimeTypes.has(file.mimetype)) {
      return callback(new HttpError(400, `Unsupported wallpaper MIME type: ${file.mimetype}`));
    }

    return callback(null, true);
  },
});

module.exports = {
  wallpaperUpload,
  allowedWallpaperMimeTypes,
};
