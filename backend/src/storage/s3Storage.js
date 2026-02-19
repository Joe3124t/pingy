const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { env } = require('../config/env');

const endpoint = env.S3_ENDPOINT ? env.S3_ENDPOINT.replace(/\/$/, '') : undefined;
let s3Client = null;

const getS3Client = () => {
  if (s3Client) {
    return s3Client;
  }

  s3Client = new S3Client({
    region: env.S3_REGION,
    endpoint,
    forcePathStyle: Boolean(endpoint),
    credentials:
      env.S3_ACCESS_KEY_ID && env.S3_SECRET_ACCESS_KEY
        ? {
            accessKeyId: env.S3_ACCESS_KEY_ID,
            secretAccessKey: env.S3_SECRET_ACCESS_KEY,
          }
        : undefined,
  });

  return s3Client;
};

const buildPublicUrl = (key) => {
  if (env.S3_PUBLIC_BASE_URL) {
    const base = env.S3_PUBLIC_BASE_URL.replace(/\/$/, '');
    return `${base}/${key}`;
  }

  if (endpoint) {
    return `${endpoint}/${env.S3_BUCKET}/${key}`;
  }

  return `https://${env.S3_BUCKET}.s3.${env.S3_REGION}.amazonaws.com/${key}`;
};

const uploadToS3 = async ({ key, buffer, mimeType }) => {
  await getS3Client().send(
    new PutObjectCommand({
      Bucket: env.S3_BUCKET,
      Key: key,
      Body: buffer,
      ContentType: mimeType,
    }),
  );

  return {
    url: buildPublicUrl(key),
    provider: 's3',
    key,
  };
};

module.exports = {
  uploadToS3,
};
