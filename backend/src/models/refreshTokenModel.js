const { query } = require('../config/db');

const createRefreshToken = async ({ id, userId, deviceId, tokenHash, expiresAt }) => {
  await query(
    `
      INSERT INTO refresh_tokens (id, user_id, device_id, token_hash, expires_at)
      VALUES ($1, $2, $3, $4, $5)
    `,
    [id, userId, deviceId, tokenHash, expiresAt],
  );
};

const findActiveRefreshTokenByHash = async (tokenHash) => {
  const result = await query(
    `
      SELECT
        id,
        user_id AS "userId",
        device_id AS "deviceId",
        token_hash AS "tokenHash",
        expires_at AS "expiresAt",
        revoked_at AS "revokedAt",
        replaced_by_hash AS "replacedByHash"
      FROM refresh_tokens
      WHERE token_hash = $1
      LIMIT 1
    `,
    [tokenHash],
  );

  const token = result.rows[0];

  if (!token) {
    return null;
  }

  if (token.revokedAt || new Date(token.expiresAt).getTime() <= Date.now()) {
    return null;
  }

  return token;
};

const revokeRefreshTokenByHash = async ({ tokenHash, replacedByHash = null }) => {
  await query(
    `
      UPDATE refresh_tokens
      SET
        revoked_at = NOW(),
        replaced_by_hash = COALESCE($2, replaced_by_hash)
      WHERE token_hash = $1
        AND revoked_at IS NULL
    `,
    [tokenHash, replacedByHash],
  );
};

const revokeRefreshTokensForUser = async (userId) => {
  await query(
    `
      UPDATE refresh_tokens
      SET revoked_at = NOW()
      WHERE user_id = $1
        AND revoked_at IS NULL
    `,
    [userId],
  );
};

const revokeRefreshTokensForUserExceptDevice = async ({ userId, keepDeviceId }) => {
  await query(
    `
      UPDATE refresh_tokens
      SET revoked_at = NOW()
      WHERE user_id = $1
        AND revoked_at IS NULL
        AND device_id <> $2
    `,
    [userId, keepDeviceId],
  );
};

module.exports = {
  createRefreshToken,
  findActiveRefreshTokenByHash,
  revokeRefreshTokenByHash,
  revokeRefreshTokensForUser,
  revokeRefreshTokensForUserExceptDevice,
};
