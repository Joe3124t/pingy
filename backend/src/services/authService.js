const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { v4: uuidv4 } = require('uuid');
const { env } = require('../config/env');
const {
  createUser,
  findUserByPhone,
  findUserByPhoneWithPassword,
  findUserById,
  findUserAuthById,
  updateUserPasswordHash,
  updateUserDeviceBinding,
} = require('../models/userModel');
const {
  createRefreshToken,
  findActiveRefreshTokenByHash,
  revokeRefreshTokenByHash,
  revokeRefreshTokensForUser,
} = require('../models/refreshTokenModel');
const {
  createPhoneOtpCode,
  consumeActivePhoneOtpCodes,
  findLatestActivePhoneOtpCode,
  consumePhoneOtpCode,
  registerFailedPhoneOtpAttempt,
} = require('../models/phoneOtpModel');
const { deleteUserPublicKey } = require('../models/userKeyModel');
const {
  signAccessToken,
  generateRefreshToken,
  hashRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const { normalizePhoneNumber } = require('../utils/phone');
const { HttpError } = require('../utils/httpError');

const SALT_ROUNDS = 12;
const OTP_CODE_LENGTH = 6;
const OTP_GENERIC_MESSAGE = 'If this phone number can receive OTP, a code was sent.';
const OTP_PURPOSES = new Set(['register', 'reset']);

const getOtpSecret = () =>
  env.OTP_VERIFICATION_SECRET || env.PASSWORD_RESET_SECRET || env.REFRESH_TOKEN_SECRET;

const normalizeOtpPurpose = (purpose) => {
  const normalized = String(purpose || 'register').trim().toLowerCase();

  if (!OTP_PURPOSES.has(normalized)) {
    throw new HttpError(400, 'Invalid OTP purpose');
  }

  return normalized;
};

const secureHashEquals = (left, right) => {
  const a = Buffer.from(String(left || ''));
  const b = Buffer.from(String(right || ''));

  if (a.length !== b.length) {
    return false;
  }

  return crypto.timingSafeEqual(a, b);
};

const generateOtpCode = () =>
  Array.from({ length: OTP_CODE_LENGTH }, () => crypto.randomInt(0, 10)).join('');

const hashOtpCode = ({ phoneNumber, purpose, code }) =>
  crypto
    .createHmac('sha256', getOtpSecret())
    .update(`${phoneNumber}:${purpose}:${String(code).trim()}`)
    .digest('hex');

const parseOtpVerificationToken = (verificationToken) => {
  try {
    const payload = jwt.verify(verificationToken, getOtpSecret());
    return {
      phoneNumber: String(payload.phoneNumber || ''),
      purpose: String(payload.purpose || ''),
    };
  } catch (error) {
    throw new HttpError(401, 'OTP verification is invalid or expired');
  }
};

const createOtpVerificationToken = ({ phoneNumber, purpose }) =>
  jwt.sign(
    {
      phoneNumber,
      purpose,
    },
    getOtpSecret(),
    {
      expiresIn: env.OTP_VERIFY_TOKEN_TTL,
    },
  );

const buildDisplayNameFromPhone = (phoneNumber) => {
  const suffix = String(phoneNumber || '').slice(-4);
  return `Pingy ${suffix}`.trim();
};

const buildOtpMessage = ({ code, purpose }) => {
  if (purpose === 'reset') {
    return `Pingy reset code: ${code}. Do not share this code with anyone.`;
  }

  return `Pingy verification code: ${code}. Do not share this code with anyone.`;
};

const sendOtpViaRelay = async ({ phoneNumber, code, purpose }) => {
  if (!env.OTP_SMS_RELAY_URL) {
    return false;
  }

  const payload = {
    phoneNumber,
    message: buildOtpMessage({ code, purpose }),
    purpose,
    code,
  };

  const headers = {
    'Content-Type': 'application/json',
  };

  if (env.OTP_SMS_RELAY_TOKEN) {
    headers.Authorization = `Bearer ${env.OTP_SMS_RELAY_TOKEN}`;
  }

  const response = await fetch(env.OTP_SMS_RELAY_URL, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const responseText = await response.text().catch(() => '');
    throw new HttpError(502, `OTP relay rejected request (${response.status})${responseText ? `: ${responseText}` : ''}`);
  }

  return true;
};

const sendOtpViaTwilio = async ({ phoneNumber, code, purpose }) => {
  const hasTwilio =
    Boolean(env.TWILIO_ACCOUNT_SID) &&
    Boolean(env.TWILIO_AUTH_TOKEN) &&
    Boolean(env.TWILIO_FROM_NUMBER);

  if (!hasTwilio) {
    return false;
  }

  const endpoint = `https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`;
  const basicAuth = Buffer.from(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`).toString('base64');

  const body = new URLSearchParams({
    To: phoneNumber,
    From: env.TWILIO_FROM_NUMBER,
    Body: buildOtpMessage({ code, purpose }),
  });

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basicAuth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const responseText = await response.text().catch(() => '');
    throw new HttpError(502, `OTP SMS provider rejected request (${response.status})${responseText ? `: ${responseText}` : ''}`);
  }

  return true;
};

const sendOtpOutOfBand = async ({ phoneNumber, code, purpose }) => {
  if (await sendOtpViaRelay({ phoneNumber, code, purpose })) {
    return {
      delivery: 'relay',
    };
  }

  if (await sendOtpViaTwilio({ phoneNumber, code, purpose })) {
    return {
      delivery: 'twilio',
    };
  }

  if (env.OTP_DEV_ALLOW_PLAINTEXT) {
    console.log(`[OTP-DEV] phone=${phoneNumber} purpose=${purpose} code=${code}`);
    return {
      delivery: 'dev-plaintext',
    };
  }

  throw new HttpError(
    503,
    'OTP SMS service is not configured. Configure Twilio or OTP relay endpoint on server.',
  );
};

const issueAuthTokens = async ({ userId, deviceId, rotateKeys }) => {
  const normalizedDeviceId = String(deviceId || '').trim();

  if (!normalizedDeviceId) {
    throw new HttpError(400, 'deviceId is required');
  }

  const userAuth = await findUserAuthById(userId);

  if (!userAuth) {
    throw new HttpError(401, 'User no longer exists');
  }

  const deviceChanged =
    !userAuth.currentDeviceId || String(userAuth.currentDeviceId) !== normalizedDeviceId;

  if (deviceChanged || rotateKeys) {
    await revokeRefreshTokensForUser(userId);
    await updateUserDeviceBinding({
      userId,
      deviceId: normalizedDeviceId,
    });
    await deleteUserPublicKey(userId);
  } else {
    await updateUserDeviceBinding({
      userId,
      deviceId: normalizedDeviceId,
    });
  }

  const user = await findUserById(userId);

  if (!user) {
    throw new HttpError(401, 'User no longer exists');
  }

  const accessToken = signAccessToken({
    id: user.id,
    username: user.username,
    phoneNumber: user.phoneNumber,
    deviceId: normalizedDeviceId,
  });
  const refreshToken = generateRefreshToken();
  const refreshTokenHash = hashRefreshToken(refreshToken);

  await createRefreshToken({
    id: uuidv4(),
    userId: user.id,
    deviceId: normalizedDeviceId,
    tokenHash: refreshTokenHash,
    expiresAt: getRefreshTokenExpiryDate(),
  });

  return {
    user: {
      ...user,
      deviceId: normalizedDeviceId,
    },
    accessToken,
    refreshToken,
  };
};

const requestPhoneOtp = async ({ phoneNumber, purpose = 'register' }) => {
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  const normalizedPurpose = normalizeOtpPurpose(purpose);

  const latestCode = await findLatestActivePhoneOtpCode({
    phoneNumber: normalizedPhone,
    purpose: normalizedPurpose,
  });
  const cooldownMs = env.OTP_REQUEST_COOLDOWN_SECONDS * 1000;

  if (latestCode && Date.now() - new Date(latestCode.createdAt).getTime() < cooldownMs) {
    return {
      message: OTP_GENERIC_MESSAGE,
    };
  }

  await consumeActivePhoneOtpCodes({
    phoneNumber: normalizedPhone,
    purpose: normalizedPurpose,
  });

  const code = generateOtpCode();
  const codeHash = hashOtpCode({
    phoneNumber: normalizedPhone,
    purpose: normalizedPurpose,
    code,
  });
  const expiresAt = new Date(Date.now() + env.OTP_CODE_TTL_MINUTES * 60 * 1000);

  await createPhoneOtpCode({
    id: uuidv4(),
    phoneNumber: normalizedPhone,
    purpose: normalizedPurpose,
    codeHash,
    expiresAt,
  });

  await sendOtpOutOfBand({
    phoneNumber: normalizedPhone,
    code,
    purpose: normalizedPurpose,
  });

  return {
    message: OTP_GENERIC_MESSAGE,
  };
};

const verifyPhoneOtp = async ({ phoneNumber, code, purpose = 'register' }) => {
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  const normalizedPurpose = normalizeOtpPurpose(purpose);

  const otpRecord = await findLatestActivePhoneOtpCode({
    phoneNumber: normalizedPhone,
    purpose: normalizedPurpose,
  });

  if (!otpRecord) {
    throw new HttpError(400, 'Invalid OTP code');
  }

  const providedHash = hashOtpCode({
    phoneNumber: normalizedPhone,
    purpose: normalizedPurpose,
    code,
  });

  if (!secureHashEquals(providedHash, otpRecord.codeHash)) {
    const attempts = await registerFailedPhoneOtpAttempt({
      id: otpRecord.id,
      maxAttempts: env.OTP_MAX_ATTEMPTS,
    });

    if (attempts >= env.OTP_MAX_ATTEMPTS) {
      throw new HttpError(429, 'Too many invalid attempts. Request a new code');
    }

    throw new HttpError(400, 'Invalid OTP code');
  }

  await consumePhoneOtpCode(otpRecord.id);

  const existingUser = await findUserByPhone(normalizedPhone);
  const verificationToken = createOtpVerificationToken({
    phoneNumber: normalizedPhone,
    purpose: normalizedPurpose,
  });

  return {
    verificationToken,
    isRegistered: Boolean(existingUser),
  };
};

const registerUser = async ({ verificationToken, password, displayName, bio, deviceId }) => {
  const otpPayload = parseOtpVerificationToken(verificationToken);

  if (otpPayload.purpose !== 'register') {
    throw new HttpError(400, 'OTP verification purpose is invalid');
  }

  const normalizedPhone = normalizePhoneNumber(otpPayload.phoneNumber);
  const existing = await findUserByPhoneWithPassword(normalizedPhone);

  if (existing) {
    throw new HttpError(409, 'An account already exists for this phone number');
  }

  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
  const username = String(displayName || '').trim() || buildDisplayNameFromPhone(normalizedPhone);

  const user = await createUser({
    id: uuidv4(),
    username,
    phoneNumber: normalizedPhone,
    passwordHash,
    deviceId,
    bio: String(bio || '').trim(),
  });

  return issueAuthTokens({
    userId: user.id,
    deviceId,
    rotateKeys: true,
  });
};

const loginUser = async ({ phoneNumber, password, deviceId }) => {
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  const userWithPassword = await findUserByPhoneWithPassword(normalizedPhone);

  if (!userWithPassword) {
    throw new HttpError(401, 'Invalid credentials');
  }

  const passwordMatches = await bcrypt.compare(password, userWithPassword.passwordHash);

  if (!passwordMatches) {
    throw new HttpError(401, 'Invalid credentials');
  }

  return issueAuthTokens({
    userId: userWithPassword.id,
    deviceId,
    rotateKeys: true,
  });
};

const refreshUserTokens = async (refreshToken) => {
  const tokenHash = hashRefreshToken(refreshToken);
  const storedToken = await findActiveRefreshTokenByHash(tokenHash);

  if (!storedToken) {
    throw new HttpError(401, 'Refresh token is invalid or expired');
  }

  const user = await findUserAuthById(storedToken.userId);

  if (!user) {
    throw new HttpError(401, 'User no longer exists');
  }

  if (
    user.currentDeviceId &&
    String(user.currentDeviceId) !== String(storedToken.deviceId || '')
  ) {
    await revokeRefreshTokenByHash({ tokenHash });
    throw new HttpError(401, 'Refresh token is invalid for this device');
  }

  const newRefreshToken = generateRefreshToken();
  const newRefreshTokenHash = hashRefreshToken(newRefreshToken);

  await revokeRefreshTokenByHash({
    tokenHash,
    replacedByHash: newRefreshTokenHash,
  });

  await createRefreshToken({
    id: uuidv4(),
    userId: storedToken.userId,
    deviceId: storedToken.deviceId,
    tokenHash: newRefreshTokenHash,
    expiresAt: getRefreshTokenExpiryDate(),
  });

  const publicUser = await findUserById(storedToken.userId);

  if (!publicUser) {
    throw new HttpError(401, 'User no longer exists');
  }

  return {
    user: {
      ...publicUser,
      deviceId: storedToken.deviceId,
    },
    accessToken: signAccessToken({
      id: publicUser.id,
      username: publicUser.username,
      phoneNumber: publicUser.phoneNumber,
      deviceId: storedToken.deviceId,
    }),
    refreshToken: newRefreshToken,
  };
};

const logoutUser = async (refreshToken) => {
  const tokenHash = hashRefreshToken(refreshToken);
  const token = await findActiveRefreshTokenByHash(tokenHash);

  if (token?.userId) {
    await deleteUserPublicKey(token.userId);
  }

  await revokeRefreshTokenByHash({ tokenHash });
};

const requestPasswordResetCode = async ({ phoneNumber }) => {
  return requestPhoneOtp({
    phoneNumber,
    purpose: 'reset',
  });
};

const resetPasswordWithCode = async ({ phoneNumber, code, newPassword, deviceId }) => {
  const normalizedPhone = normalizePhoneNumber(phoneNumber);

  const otpRecord = await findLatestActivePhoneOtpCode({
    phoneNumber: normalizedPhone,
    purpose: 'reset',
  });

  if (!otpRecord) {
    throw new HttpError(400, 'Invalid reset code');
  }

  const providedHash = hashOtpCode({
    phoneNumber: normalizedPhone,
    purpose: 'reset',
    code,
  });
  const matches = secureHashEquals(providedHash, otpRecord.codeHash);

  if (!matches) {
    const attempts = await registerFailedPhoneOtpAttempt({
      id: otpRecord.id,
      maxAttempts: env.OTP_MAX_ATTEMPTS,
    });

    if (attempts >= env.OTP_MAX_ATTEMPTS) {
      throw new HttpError(429, 'Too many invalid attempts. Request a new code');
    }

    throw new HttpError(400, 'Invalid reset code');
  }

  const userWithPassword = await findUserByPhoneWithPassword(normalizedPhone);

  if (!userWithPassword) {
    throw new HttpError(404, 'Account not found');
  }

  const passwordHash = await bcrypt.hash(newPassword, SALT_ROUNDS);
  await updateUserPasswordHash({
    userId: userWithPassword.id,
    passwordHash,
  });
  await consumePhoneOtpCode(otpRecord.id);
  await revokeRefreshTokensForUser(userWithPassword.id);
  await deleteUserPublicKey(userWithPassword.id);

  if (deviceId) {
    await updateUserDeviceBinding({
      userId: userWithPassword.id,
      deviceId: String(deviceId).trim(),
    });
  }
};

module.exports = {
  requestPhoneOtp,
  verifyPhoneOtp,
  registerUser,
  loginUser,
  refreshUserTokens,
  logoutUser,
  requestPasswordResetCode,
  resetPasswordWithCode,
};
