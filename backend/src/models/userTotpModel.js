const { v4: uuidv4 } = require('uuid');
const { query, withTransaction } = require('../config/db');

const getUserTotpState = async (userId) => {
  const result = await query(
    `
      SELECT
        id AS "userId",
        totp_enabled AS "totpEnabled",
        totp_secret_enc AS "totpSecretEnc",
        totp_pending_secret_enc AS "totpPendingSecretEnc",
        totp_pending_expires_at AS "totpPendingExpiresAt",
        totp_confirmed_at AS "totpConfirmedAt"
      FROM users
      WHERE id = $1
      LIMIT 1
    `,
    [userId],
  );

  return result.rows[0] || null;
};

const setUserTotpPendingSecret = async ({ userId, encryptedSecret, expiresAt }) => {
  await query(
    `
      UPDATE users
      SET
        totp_pending_secret_enc = $2,
        totp_pending_expires_at = $3,
        updated_at = NOW()
      WHERE id = $1
    `,
    [userId, encryptedSecret, expiresAt],
  );
};

const activateUserTotpSecret = async ({ userId, encryptedSecret, confirmedAt = new Date() }) => {
  await query(
    `
      UPDATE users
      SET
        totp_enabled = TRUE,
        totp_secret_enc = $2,
        totp_pending_secret_enc = NULL,
        totp_pending_expires_at = NULL,
        totp_confirmed_at = $3,
        updated_at = NOW()
      WHERE id = $1
    `,
    [userId, encryptedSecret, confirmedAt],
  );
};

const clearUserTotpPendingSecret = async (userId) => {
  await query(
    `
      UPDATE users
      SET
        totp_pending_secret_enc = NULL,
        totp_pending_expires_at = NULL,
        updated_at = NOW()
      WHERE id = $1
    `,
    [userId],
  );
};

const disableUserTotp = async (userId) => {
  await withTransaction(async (client) => {
    await client.query(
      `
        UPDATE users
        SET
          totp_enabled = FALSE,
          totp_secret_enc = NULL,
          totp_pending_secret_enc = NULL,
          totp_pending_expires_at = NULL,
          totp_confirmed_at = NULL,
          updated_at = NOW()
        WHERE id = $1
      `,
      [userId],
    );

    await client.query(
      `
        DELETE FROM user_totp_recovery_codes
        WHERE user_id = $1
      `,
      [userId],
    );
  });
};

const replaceUserRecoveryCodeHashes = async ({ userId, hashes }) => {
  const uniqueHashes = Array.from(new Set((hashes || []).filter(Boolean)));

  await withTransaction(async (client) => {
    await client.query(
      `
        DELETE FROM user_totp_recovery_codes
        WHERE user_id = $1
      `,
      [userId],
    );

    for (const hash of uniqueHashes) {
      await client.query(
        `
          INSERT INTO user_totp_recovery_codes (
            id,
            user_id,
            code_hash,
            created_at
          )
          VALUES ($1, $2, $3, NOW())
        `,
        [uuidv4(), userId, hash],
      );
    }
  });
};

const consumeRecoveryCodeHash = async ({ userId, codeHash }) => {
  const result = await query(
    `
      UPDATE user_totp_recovery_codes
      SET consumed_at = NOW()
      WHERE user_id = $1
        AND code_hash = $2
        AND consumed_at IS NULL
      RETURNING id
    `,
    [userId, codeHash],
  );

  return Boolean(result.rows[0]);
};

const countAvailableRecoveryCodes = async (userId) => {
  const result = await query(
    `
      SELECT COUNT(*)::int AS "count"
      FROM user_totp_recovery_codes
      WHERE user_id = $1
        AND consumed_at IS NULL
    `,
    [userId],
  );

  return Number(result.rows[0]?.count || 0);
};

module.exports = {
  getUserTotpState,
  setUserTotpPendingSecret,
  activateUserTotpSecret,
  clearUserTotpPendingSecret,
  disableUserTotp,
  replaceUserRecoveryCodeHashes,
  consumeRecoveryCodeHash,
  countAvailableRecoveryCodes,
};
