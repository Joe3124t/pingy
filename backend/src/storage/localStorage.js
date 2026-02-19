const fs = require('node:fs/promises');
const path = require('node:path');

const uploadsRoot = path.resolve(process.cwd(), 'uploads');

const uploadToLocal = async ({ key, buffer }) => {
  const fullPath = path.resolve(uploadsRoot, key);
  const directory = path.dirname(fullPath);

  await fs.mkdir(directory, { recursive: true });
  await fs.writeFile(fullPath, buffer);

  return {
    provider: 'local',
    key,
    url: `/uploads/${key.replace(/\\/g, '/')}`,
  };
};

module.exports = {
  uploadToLocal,
};
