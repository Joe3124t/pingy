const { query } = require('../config/db');

const createRefreshToken = async ({ id, userId, tokenHash, expiresAt }) => {
  await query(
    `
      INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at)
      VALUES ($1, $2, $3, $4)
    `,
    [id, userId, tokenHash, expiresAt],
  );
};

const findActiveRefreshTokenByHash = async (tokenHash) => {
  const result = await query(
    `
      SELECT
        id,
        user_id AS "userId",
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

module.exports = {
  createRefreshToken,
  findActiveRefreshTokenByHash,
  revokeRefreshTokenByHash,
  revokeRefreshTokensForUser,
};
