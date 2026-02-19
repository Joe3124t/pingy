const { query } = require('../config/db');

const createPasswordResetCode = async ({ id, userId, codeHash, expiresAt }) => {
  await query(
    `
      INSERT INTO password_reset_codes (id, user_id, code_hash, expires_at)
      VALUES ($1, $2, $3, $4)
    `,
    [id, userId, codeHash, expiresAt],
  );
};

const consumeActivePasswordResetCodesForUser = async (userId) => {
  await query(
    `
      UPDATE password_reset_codes
      SET consumed_at = NOW()
      WHERE user_id = $1
        AND consumed_at IS NULL
        AND expires_at > NOW()
    `,
    [userId],
  );
};

const findLatestActivePasswordResetCodeForUser = async (userId) => {
  const result = await query(
    `
      SELECT
        id,
        user_id AS "userId",
        code_hash AS "codeHash",
        attempts,
        expires_at AS "expiresAt",
        consumed_at AS "consumedAt",
        created_at AS "createdAt"
      FROM password_reset_codes
      WHERE user_id = $1
        AND consumed_at IS NULL
        AND expires_at > NOW()
      ORDER BY created_at DESC
      LIMIT 1
    `,
    [userId],
  );

  return result.rows[0] || null;
};

const consumePasswordResetCode = async (id) => {
  await query(
    `
      UPDATE password_reset_codes
      SET consumed_at = NOW()
      WHERE id = $1
        AND consumed_at IS NULL
    `,
    [id],
  );
};

const registerFailedPasswordResetAttempt = async ({ id, maxAttempts }) => {
  const result = await query(
    `
      UPDATE password_reset_codes
      SET
        attempts = attempts + 1,
        consumed_at = CASE
          WHEN attempts + 1 >= $2 THEN NOW()
          ELSE consumed_at
        END
      WHERE id = $1
      RETURNING attempts
    `,
    [id, maxAttempts],
  );

  return Number(result.rows[0]?.attempts || 0);
};

module.exports = {
  createPasswordResetCode,
  consumeActivePasswordResetCodesForUser,
  findLatestActivePasswordResetCodeForUser,
  consumePasswordResetCode,
  registerFailedPasswordResetAttempt,
};
