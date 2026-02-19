const { query } = require('../config/db');

const createPhoneOtpCode = async ({ id, phoneNumber, purpose, codeHash, expiresAt }) => {
  await query(
    `
      INSERT INTO phone_otp_codes (id, phone_number, purpose, code_hash, expires_at)
      VALUES ($1, $2, $3, $4, $5)
    `,
    [id, phoneNumber, purpose, codeHash, expiresAt],
  );
};

const consumeActivePhoneOtpCodes = async ({ phoneNumber, purpose }) => {
  await query(
    `
      UPDATE phone_otp_codes
      SET consumed_at = NOW()
      WHERE phone_number = $1
        AND purpose = $2
        AND consumed_at IS NULL
    `,
    [phoneNumber, purpose],
  );
};

const findLatestActivePhoneOtpCode = async ({ phoneNumber, purpose }) => {
  const result = await query(
    `
      SELECT
        id,
        phone_number AS "phoneNumber",
        purpose,
        code_hash AS "codeHash",
        attempts,
        expires_at AS "expiresAt",
        consumed_at AS "consumedAt",
        created_at AS "createdAt"
      FROM phone_otp_codes
      WHERE phone_number = $1
        AND purpose = $2
        AND consumed_at IS NULL
        AND expires_at > NOW()
      ORDER BY created_at DESC
      LIMIT 1
    `,
    [phoneNumber, purpose],
  );

  return result.rows[0] || null;
};

const consumePhoneOtpCode = async (id) => {
  await query(
    `
      UPDATE phone_otp_codes
      SET consumed_at = NOW()
      WHERE id = $1
        AND consumed_at IS NULL
    `,
    [id],
  );
};

const registerFailedPhoneOtpAttempt = async ({ id, maxAttempts }) => {
  const result = await query(
    `
      UPDATE phone_otp_codes
      SET
        attempts = attempts + 1,
        consumed_at = CASE WHEN attempts + 1 >= $2 THEN NOW() ELSE consumed_at END
      WHERE id = $1
      RETURNING attempts
    `,
    [id, maxAttempts],
  );

  return result.rows[0]?.attempts || 0;
};

module.exports = {
  createPhoneOtpCode,
  consumeActivePhoneOtpCodes,
  findLatestActivePhoneOtpCode,
  consumePhoneOtpCode,
  registerFailedPhoneOtpAttempt,
};
