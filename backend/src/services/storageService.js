const path = require('node:path');
const mime = require('mime-types');
const { v4: uuidv4 } = require('uuid');
const { env } = require('../config/env');
const { uploadToS3 } = require('../storage/s3Storage');
const { uploadToLocal } = require('../storage/localStorage');

const hasS3Config = Boolean(
  env.S3_BUCKET && env.S3_REGION && env.S3_ACCESS_KEY_ID && env.S3_SECRET_ACCESS_KEY,
);

const normalizeExtension = (originalName, mimeType) => {
  const fromMime = mime.extension(mimeType);

  if (fromMime) {
    return fromMime;
  }

  const ext = path.extname(originalName || '').replace('.', '').toLowerCase();
  return ext || 'bin';
};

const uploadBuffer = async ({ buffer, originalName, mimeType, folder = 'media' }) => {
  const extension = normalizeExtension(originalName, mimeType);
  const key = `pingy/${folder}/${Date.now()}-${uuidv4()}.${extension}`;

  let uploaded;
  if (hasS3Config) {
    try {
      uploaded = await uploadToS3({ key, buffer, mimeType });
    } catch (error) {
      console.error(
        `[storage] S3 upload failed for ${key}. Falling back to local storage. Reason: ${error.message}`,
      );
      uploaded = await uploadToLocal({ key, buffer, mimeType });
    }
  } else {
    uploaded = await uploadToLocal({ key, buffer, mimeType });
  }

  return {
    ...uploaded,
    mimeType,
    size: buffer.length,
    originalName,
  };
};

module.exports = {
  uploadBuffer,
  hasS3Config,
};
