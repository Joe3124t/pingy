const { query } = require('../config/db');

const upsertUserPublicKey = async ({ userId, publicKeyJwk, algorithm = 'ECDH-P256' }) => {
  const result = await query(
    `
      INSERT INTO user_public_keys (user_id, public_key_jwk, algorithm, created_at, updated_at)
      VALUES ($1, $2::jsonb, $3, NOW(), NOW())
      ON CONFLICT (user_id)
      DO UPDATE SET
        public_key_jwk = EXCLUDED.public_key_jwk,
        algorithm = EXCLUDED.algorithm,
        updated_at = NOW()
      RETURNING
        user_id AS "userId",
        public_key_jwk AS "publicKeyJwk",
        algorithm,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [userId, JSON.stringify(publicKeyJwk), algorithm],
  );

  return result.rows[0] || null;
};

const findUserPublicKey = async (userId) => {
  const result = await query(
    `
      SELECT
        user_id AS "userId",
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

module.exports = {
  upsertUserPublicKey,
  findUserPublicKey,
};
