const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const { env } = require('../config/env');
const { HttpError } = require('../utils/httpError');

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const BASE32_LOOKUP = BASE32_ALPHABET.split('').reduce((acc, char, index) => {
  acc[char] = index;
  return acc;
}, {});

const TOTP_PERIOD_SECONDS = 30;
const TOTP_DIGITS = 6;
const RECOVERY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const getEncryptionKey = () =>
  crypto
    .createHash('sha256')
    .update(String(env.TOTP_ENCRYPTION_SECRET || env.REFRESH_TOKEN_SECRET))
    .digest();

const getRecoveryHashSecret = () => String(env.TOTP_ENCRYPTION_SECRET || env.REFRESH_TOKEN_SECRET);

const getChallengeSecret = () =>
  String(env.TOTP_CHALLENGE_SECRET || env.OTP_VERIFICATION_SECRET || env.REFRESH_TOKEN_SECRET);

const encodeBase32 = (buffer) => {
  if (!buffer || buffer.length === 0) {
    return '';
  }

  let bits = '';
  for (const byte of buffer.values()) {
    bits += byte.toString(2).padStart(8, '0');
  }

  let encoded = '';
  for (let offset = 0; offset < bits.length; offset += 5) {
    const chunk = bits.slice(offset, offset + 5).padEnd(5, '0');
    encoded += BASE32_ALPHABET[Number.parseInt(chunk, 2)];
  }

  return encoded;
};

const decodeBase32 = (value) => {
  const normalized = String(value || '')
    .toUpperCase()
    .replace(/=+$/g, '')
    .replace(/\s+/g, '');

  if (!normalized) {
    throw new HttpError(400, 'Invalid TOTP secret');
  }

  let bits = '';
  for (const char of normalized) {
    const index = BASE32_LOOKUP[char];
    if (index === undefined) {
      throw new HttpError(400, 'Invalid TOTP secret');
    }
    bits += index.toString(2).padStart(5, '0');
  }

  const bytes = [];
  for (let offset = 0; offset + 8 <= bits.length; offset += 8) {
    const chunk = bits.slice(offset, offset + 8);
    bytes.push(Number.parseInt(chunk, 2));
  }

  return Buffer.from(bytes);
};

const generateBase32Secret = (byteLength = 20) => {
  const randomBytes = crypto.randomBytes(byteLength);
  return encodeBase32(randomBytes);
};

const createHotp = ({ secretBuffer, counter, digits = TOTP_DIGITS }) => {
  const counterBuffer = Buffer.alloc(8);
  counterBuffer.writeBigUInt64BE(BigInt(counter));
  const hmac = crypto.createHmac('sha1', secretBuffer).update(counterBuffer).digest();

  const offset = hmac[hmac.length - 1] & 0x0f;
  const codeInt =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  const otp = codeInt % 10 ** digits;
  return String(otp).padStart(digits, '0');
};

const generateTotpCode = ({
  secret,
  timestampMs = Date.now(),
  periodSeconds = TOTP_PERIOD_SECONDS,
  digits = TOTP_DIGITS,
}) => {
  const secretBuffer = decodeBase32(secret);
  const counter = Math.floor(timestampMs / 1000 / periodSeconds);
  return createHotp({
    secretBuffer,
    counter,
    digits,
  });
};

const verifyTotpCode = ({
  secret,
  code,
  timestampMs = Date.now(),
  window = 1,
  periodSeconds = TOTP_PERIOD_SECONDS,
  digits = TOTP_DIGITS,
}) => {
  const normalizedCode = String(code || '').trim();

  if (!/^\d{6}$/.test(normalizedCode)) {
    return false;
  }

  const secretBuffer = decodeBase32(secret);
  const currentCounter = Math.floor(timestampMs / 1000 / periodSeconds);

  for (let drift = -window; drift <= window; drift += 1) {
    const candidate = createHotp({
      secretBuffer,
      counter: currentCounter + drift,
      digits,
    });

    if (candidate === normalizedCode) {
      return true;
    }
  }

  return false;
};

const createOtpAuthUrl = ({
  secret,
  accountName,
  issuer = env.TOTP_ISSUER || 'Pingy',
  periodSeconds = TOTP_PERIOD_SECONDS,
  digits = TOTP_DIGITS,
}) => {
  const label = `${issuer}:${accountName}`;
  return `otpauth://totp/${encodeURIComponent(label)}?secret=${encodeURIComponent(secret)}&issuer=${encodeURIComponent(
    issuer,
  )}&algorithm=SHA1&digits=${digits}&period=${periodSeconds}`;
};

const encryptTotpSecret = (secret) => {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(String(secret), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `v1:${iv.toString('base64url')}:${tag.toString('base64url')}:${encrypted.toString('base64url')}`;
};

const decryptTotpSecret = (encryptedSecret) => {
  const [version, ivB64, tagB64, cipherB64] = String(encryptedSecret || '').split(':');

  if (version !== 'v1' || !ivB64 || !tagB64 || !cipherB64) {
    throw new HttpError(500, 'Stored TOTP secret is invalid');
  }

  const iv = Buffer.from(ivB64, 'base64url');
  const tag = Buffer.from(tagB64, 'base64url');
  const ciphertext = Buffer.from(cipherB64, 'base64url');

  const decipher = crypto.createDecipheriv('aes-256-gcm', getEncryptionKey(), iv);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

  return plain.toString('utf8');
};

const generateRecoveryCodes = (count = env.TOTP_RECOVERY_CODES_COUNT || 8) =>
  Array.from({ length: count }, () => {
    const bytes = crypto.randomBytes(8);
    let result = '';
    for (const byte of bytes.values()) {
      result += RECOVERY_ALPHABET[byte % RECOVERY_ALPHABET.length];
      if (result.length >= 10) {
        break;
      }
    }
    return `${result.slice(0, 5)}-${result.slice(5, 10)}`;
  });

const hashRecoveryCode = (recoveryCode) =>
  crypto
    .createHmac('sha256', getRecoveryHashSecret())
    .update(String(recoveryCode || '').trim().toUpperCase())
    .digest('hex');

const createTotpChallengeToken = ({ userId, deviceId }) =>
  jwt.sign(
    {
      sub: userId,
      deviceId,
      purpose: 'totp-login',
    },
    getChallengeSecret(),
    {
      expiresIn: env.TOTP_CHALLENGE_TTL || '10m',
    },
  );

const parseTotpChallengeToken = (token) => {
  try {
    const payload = jwt.verify(token, getChallengeSecret());

    if (payload?.purpose !== 'totp-login' || !payload?.sub || !payload?.deviceId) {
      throw new Error('Invalid challenge token payload');
    }

    return {
      userId: String(payload.sub),
      deviceId: String(payload.deviceId),
    };
  } catch {
    throw new HttpError(401, 'TOTP challenge is invalid or expired');
  }
};

module.exports = {
  TOTP_PERIOD_SECONDS,
  TOTP_DIGITS,
  generateBase32Secret,
  generateTotpCode,
  verifyTotpCode,
  createOtpAuthUrl,
  encryptTotpSecret,
  decryptTotpSecret,
  generateRecoveryCodes,
  hashRecoveryCode,
  createTotpChallengeToken,
  parseTotpChallengeToken,
};
