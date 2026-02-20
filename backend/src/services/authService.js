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
const {
  getUserTotpState,
  setUserTotpPendingSecret,
  activateUserTotpSecret,
  clearUserTotpPendingSecret,
  disableUserTotp,
  replaceUserRecoveryCodeHashes,
  consumeRecoveryCodeHash,
  countAvailableRecoveryCodes,
} = require('../models/userTotpModel');
const { deleteUserPublicKey } = require('../models/userKeyModel');
const {
  signAccessToken,
  generateRefreshToken,
  hashRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const {
  generateBase32Secret,
  verifyTotpCode,
  createOtpAuthUrl,
  encryptTotpSecret,
  decryptTotpSecret,
  generateRecoveryCodes,
  hashRecoveryCode,
  createTotpChallengeToken,
  parseTotpChallengeToken,
} = require('../crypto/totp');
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

const getTotpSignupTokenSecret = () =>
  String(env.TOTP_CHALLENGE_SECRET || env.OTP_VERIFICATION_SECRET || env.REFRESH_TOKEN_SECRET);

const createTotpSignupChallengeToken = ({ phoneNumber, encryptedSecret }) =>
  jwt.sign(
    {
      phoneNumber,
      encryptedSecret,
      purpose: 'totp-signup-challenge',
    },
    getTotpSignupTokenSecret(),
    {
      expiresIn: `${env.TOTP_SETUP_TTL_MINUTES || 15}m`,
    },
  );

const parseTotpSignupChallengeToken = (challengeToken) => {
  try {
    const payload = jwt.verify(challengeToken, getTotpSignupTokenSecret());

    if (
      payload?.purpose !== 'totp-signup-challenge' ||
      !payload?.phoneNumber ||
      !payload?.encryptedSecret
    ) {
      throw new Error('Invalid signup challenge payload');
    }

    return {
      phoneNumber: String(payload.phoneNumber),
      encryptedSecret: String(payload.encryptedSecret),
    };
  } catch {
    throw new HttpError(401, 'Authenticator setup token is invalid or expired');
  }
};

const createTotpSignupRegistrationToken = ({ phoneNumber, encryptedSecret }) =>
  jwt.sign(
    {
      phoneNumber,
      encryptedSecret,
      purpose: 'totp-signup-verified',
    },
    getTotpSignupTokenSecret(),
    {
      expiresIn: env.TOTP_CHALLENGE_TTL || '10m',
    },
  );

const parseTotpSignupRegistrationToken = (registrationToken) => {
  try {
    const payload = jwt.verify(registrationToken, getTotpSignupTokenSecret());

    if (
      payload?.purpose !== 'totp-signup-verified' ||
      !payload?.phoneNumber ||
      !payload?.encryptedSecret
    ) {
      throw new Error('Invalid signup registration payload');
    }

    return {
      phoneNumber: String(payload.phoneNumber),
      encryptedSecret: String(payload.encryptedSecret),
    };
  } catch {
    throw new HttpError(401, 'Authenticator registration token is invalid or expired');
  }
};

const buildDisplayNameFromPhone = (phoneNumber) => {
  const suffix = String(phoneNumber || '').slice(-4);
  return `Pingy ${suffix}`.trim();
};

const maskPhoneNumber = (phoneNumber) => {
  const normalized = String(phoneNumber || '').trim();

  if (!normalized) {
    return '';
  }

  if (normalized.length <= 4) {
    return normalized;
  }

  const prefixLength = Math.min(4, normalized.length - 2);
  const suffixLength = 2;
  const hiddenLength = Math.max(0, normalized.length - prefixLength - suffixLength);

  return `${normalized.slice(0, prefixLength)}${'*'.repeat(hiddenLength)}${normalized.slice(
    normalized.length - suffixLength,
  )}`;
};

const normalizeRecoveryCode = (value) =>
  String(value || '')
    .trim()
    .toUpperCase();

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

const startAuthenticatorSignup = async ({ phoneNumber }) => {
  if (!env.TOTP_ENABLED) {
    throw new HttpError(400, 'Authenticator signup is disabled on server');
  }

  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  const existing = await findUserByPhoneWithPassword(normalizedPhone);

  if (existing) {
    throw new HttpError(409, 'An account already exists for this phone number');
  }

  const secret = generateBase32Secret();
  const encryptedSecret = encryptTotpSecret(secret);

  return {
    message: 'Authenticator setup generated. Add it in your Authenticator app.',
    challengeToken: createTotpSignupChallengeToken({
      phoneNumber: normalizedPhone,
      encryptedSecret,
    }),
    secret,
    otpAuthUrl: createOtpAuthUrl({
      secret,
      accountName: normalizedPhone,
      issuer: env.TOTP_ISSUER,
    }),
    issuer: env.TOTP_ISSUER,
    accountName: normalizedPhone,
  };
};

const verifyAuthenticatorSignup = async ({ challengeToken, code }) => {
  const signupChallenge = parseTotpSignupChallengeToken(challengeToken);
  const secret = decryptTotpSecret(signupChallenge.encryptedSecret);
  const isValid = verifyTotpCode({
    secret,
    code,
  });

  if (!isValid) {
    throw new HttpError(400, 'Invalid authenticator code');
  }

  return {
    message: 'Authenticator verified successfully. Continue to set your password.',
    registrationToken: createTotpSignupRegistrationToken({
      phoneNumber: signupChallenge.phoneNumber,
      encryptedSecret: signupChallenge.encryptedSecret,
    }),
  };
};

const completeAuthenticatorSignup = async ({
  registrationToken,
  password,
  displayName,
  bio,
  deviceId,
}) => {
  const payload = parseTotpSignupRegistrationToken(registrationToken);
  const normalizedPhone = normalizePhoneNumber(payload.phoneNumber);
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

  await activateUserTotpSecret({
    userId: user.id,
    encryptedSecret: payload.encryptedSecret,
  });

  const recoveryCodes = generateRecoveryCodes(env.TOTP_RECOVERY_CODES_COUNT);
  const recoveryHashes = recoveryCodes.map((recoveryCode) =>
    hashRecoveryCode(normalizeRecoveryCode(recoveryCode)),
  );

  await replaceUserRecoveryCodeHashes({
    userId: user.id,
    hashes: recoveryHashes,
  });

  const auth = await issueAuthTokens({
    userId: user.id,
    deviceId,
    rotateKeys: true,
  });

  return {
    ...auth,
    recoveryCodes,
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

const verifyTotpOrRecovery = async ({
  userId,
  encryptedSecret,
  code,
  recoveryCode,
  allowRecovery = false,
}) => {
  const normalizedCode = String(code || '').trim();
  const normalizedRecovery = normalizeRecoveryCode(recoveryCode);

  if (normalizedCode) {
    if (!encryptedSecret) {
      throw new HttpError(400, 'Two-step verification is not configured for this account');
    }

    const secret = decryptTotpSecret(encryptedSecret);
    if (verifyTotpCode({ secret, code: normalizedCode })) {
      return {
        verified: true,
        method: 'totp',
      };
    }
  }

  if (allowRecovery && normalizedRecovery) {
    const consumed = await consumeRecoveryCodeHash({
      userId,
      codeHash: hashRecoveryCode(normalizedRecovery),
    });

    if (consumed) {
      return {
        verified: true,
        method: 'recovery',
      };
    }
  }

  return {
    verified: false,
    method: null,
  };
};

const loginUser = async ({ phoneNumber, password, deviceId }) => {
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  const normalizedDeviceId = String(deviceId || '').trim();

  if (!normalizedDeviceId) {
    throw new HttpError(400, 'deviceId is required');
  }

  const userWithPassword = await findUserByPhoneWithPassword(normalizedPhone);

  if (!userWithPassword) {
    throw new HttpError(401, 'Invalid credentials');
  }

  const passwordMatches = await bcrypt.compare(password, userWithPassword.passwordHash);

  if (!passwordMatches) {
    throw new HttpError(401, 'Invalid credentials');
  }

  if (env.TOTP_ENABLED && userWithPassword.totpEnabled && Boolean(userWithPassword.totpSecretEnc)) {
    return {
      requiresTotp: true,
      challengeToken: createTotpChallengeToken({
        userId: userWithPassword.id,
        deviceId: normalizedDeviceId,
      }),
      userHint: {
        id: userWithPassword.id,
        username: userWithPassword.username,
        phoneMasked: maskPhoneNumber(userWithPassword.phoneNumber),
      },
    };
  }

  if (env.TOTP_ENABLED) {
    throw new HttpError(
      403,
      'Authenticator is required for this account. Enable two-step verification before login.',
    );
  }

  const auth = await issueAuthTokens({
    userId: userWithPassword.id,
    deviceId: normalizedDeviceId,
    rotateKeys: true,
  });

  return {
    requiresTotp: false,
    ...auth,
  };
};

const verifyTotpLogin = async ({ challengeToken, code, recoveryCode }) => {
  if (!env.TOTP_ENABLED) {
    throw new HttpError(400, 'Two-step verification is disabled on server');
  }

  const { userId, deviceId } = parseTotpChallengeToken(challengeToken);
  const userWithPassword = await findUserAuthById(userId);

  if (!userWithPassword) {
    throw new HttpError(401, 'Account session is invalid. Login again');
  }

  if (!userWithPassword.totpEnabled || !userWithPassword.totpSecretEnc) {
    throw new HttpError(401, 'Two-step verification is not enabled for this account');
  }

  const verification = await verifyTotpOrRecovery({
    userId,
    encryptedSecret: userWithPassword.totpSecretEnc,
    code,
    recoveryCode,
    allowRecovery: true,
  });

  if (!verification.verified) {
    throw new HttpError(401, 'Invalid authenticator code');
  }

  const auth = await issueAuthTokens({
    userId,
    deviceId,
    rotateKeys: true,
  });

  return {
    requiresTotp: false,
    auth,
  };
};

const getTotpStatusForUser = async ({ userId }) => {
  if (!env.TOTP_ENABLED) {
    return {
      enabled: false,
      pending: false,
      pendingExpiresAt: null,
      recoveryCodesAvailable: 0,
      issuer: env.TOTP_ISSUER,
      isServerEnabled: false,
    };
  }

  const state = await getUserTotpState(userId);

  if (!state) {
    throw new HttpError(404, 'User not found');
  }

  const pendingExpiresAt = state.totpPendingExpiresAt ? new Date(state.totpPendingExpiresAt) : null;
  const hasExpiredPendingSecret =
    Boolean(state.totpPendingSecretEnc) &&
    Boolean(pendingExpiresAt) &&
    Number.isFinite(pendingExpiresAt.getTime()) &&
    pendingExpiresAt.getTime() <= Date.now();

  if (hasExpiredPendingSecret) {
    await clearUserTotpPendingSecret(userId);
  }

  const isPending = Boolean(
    state.totpPendingSecretEnc &&
      pendingExpiresAt &&
      Number.isFinite(pendingExpiresAt.getTime()) &&
      pendingExpiresAt.getTime() > Date.now(),
  );
  const recoveryCodesAvailable = state.totpEnabled
    ? await countAvailableRecoveryCodes(userId)
    : 0;

  return {
    enabled: Boolean(state.totpEnabled),
    pending: isPending,
    pendingExpiresAt: pendingExpiresAt ? pendingExpiresAt.toISOString() : null,
    recoveryCodesAvailable,
    issuer: env.TOTP_ISSUER,
    isServerEnabled: true,
  };
};

const startTotpSetup = async ({ userId }) => {
  if (!env.TOTP_ENABLED) {
    throw new HttpError(400, 'Two-step verification is disabled on server');
  }

  const user = await findUserById(userId);

  if (!user) {
    throw new HttpError(404, 'User not found');
  }

  const secret = generateBase32Secret();
  const encryptedSecret = encryptTotpSecret(secret);
  const expiresAt = new Date(Date.now() + env.TOTP_SETUP_TTL_MINUTES * 60 * 1000);
  const accountName = user.phoneNumber || user.username || user.id;

  await setUserTotpPendingSecret({
    userId,
    encryptedSecret,
    expiresAt,
  });

  return {
    secret,
    otpAuthUrl: createOtpAuthUrl({
      secret,
      accountName,
      issuer: env.TOTP_ISSUER,
    }),
    issuer: env.TOTP_ISSUER,
    accountName,
    expiresAt: expiresAt.toISOString(),
  };
};

const verifyTotpSetup = async ({ userId, code }) => {
  if (!env.TOTP_ENABLED) {
    throw new HttpError(400, 'Two-step verification is disabled on server');
  }

  const state = await getUserTotpState(userId);

  if (!state?.totpPendingSecretEnc) {
    throw new HttpError(400, 'Start two-step setup first');
  }

  const expiresAt = state.totpPendingExpiresAt ? new Date(state.totpPendingExpiresAt) : null;

  if (!expiresAt || expiresAt.getTime() <= Date.now()) {
    await clearUserTotpPendingSecret(userId);
    throw new HttpError(400, 'Two-step setup expired. Start setup again');
  }

  const secret = decryptTotpSecret(state.totpPendingSecretEnc);
  const isValid = verifyTotpCode({
    secret,
    code,
  });

  if (!isValid) {
    throw new HttpError(400, 'Invalid authenticator code');
  }

  await activateUserTotpSecret({
    userId,
    encryptedSecret: state.totpPendingSecretEnc,
  });

  const recoveryCodes = generateRecoveryCodes(env.TOTP_RECOVERY_CODES_COUNT);
  const recoveryHashes = recoveryCodes.map((recoveryCode) =>
    hashRecoveryCode(normalizeRecoveryCode(recoveryCode)),
  );

  await replaceUserRecoveryCodeHashes({
    userId,
    hashes: recoveryHashes,
  });

  return {
    message: 'Two-step verification enabled successfully',
    recoveryCodes,
  };
};

const disableTotpForUser = async ({ userId, code, recoveryCode }) => {
  if (!env.TOTP_ENABLED) {
    throw new HttpError(400, 'Two-step verification is disabled on server');
  }

  const state = await getUserTotpState(userId);

  if (!state?.totpEnabled || !state.totpSecretEnc) {
    return {
      message: 'Two-step verification is already disabled',
    };
  }

  const verification = await verifyTotpOrRecovery({
    userId,
    encryptedSecret: state.totpSecretEnc,
    code,
    recoveryCode,
    allowRecovery: true,
  });

  if (!verification.verified) {
    throw new HttpError(401, 'Invalid authenticator code');
  }

  await disableUserTotp(userId);

  return {
    message: 'Two-step verification disabled successfully',
  };
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
  startAuthenticatorSignup,
  verifyAuthenticatorSignup,
  completeAuthenticatorSignup,
  registerUser,
  loginUser,
  verifyTotpLogin,
  getTotpStatusForUser,
  startTotpSetup,
  verifyTotpSetup,
  disableTotpForUser,
  refreshUserTokens,
  logoutUser,
  requestPasswordResetCode,
  resetPasswordWithCode,
};
