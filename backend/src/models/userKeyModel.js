const { query } = require('../config/db');

const upsertUserPublicKey = async ({
  userId,
  deviceId = null,
  publicKeyJwk,
  algorithm = 'ECDH-Curve25519',
}) => {
  const result = await query(
    `
      INSERT INTO user_public_keys (user_id, device_id, public_key_jwk, algorithm, created_at, updated_at)
      VALUES ($1, $2, $3::jsonb, $4, NOW(), NOW())
      ON CONFLICT (user_id)
      DO UPDATE SET
        device_id = EXCLUDED.device_id,
        public_key_jwk = EXCLUDED.public_key_jwk,
        algorithm = EXCLUDED.algorithm,
        updated_at = NOW()
      RETURNING
        user_id AS "userId",
        device_id AS "deviceId",
        public_key_jwk AS "publicKeyJwk",
        algorithm,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [userId, deviceId, JSON.stringify(publicKeyJwk), algorithm],
  );

  return result.rows[0] || null;
};

const findUserPublicKey = async (userId) => {
  const result = await query(
    `
      SELECT
        user_id AS "userId",
        device_id AS "deviceId",
        public_key_jwk AS "publicKeyJwk",
        algorithm,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM user_public_keys
      WHERE user_id = $1
      LIMIT 1
    `,
    [userId],
  );

  return result.rows[0] || null;
};

const deleteUserPublicKey = async (userId) => {
  await query(
    `
      DELETE FROM user_public_keys
      WHERE user_id = $1
    `,
    [userId],
  );
};

module.exports = {
  upsertUserPublicKey,
  findUserPublicKey,
  deleteUserPublicKey,
};
