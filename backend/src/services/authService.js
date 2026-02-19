const crypto = require('node:crypto');
const bcrypt = require('bcrypt');
const { v4: uuidv4 } = require('uuid');
const { env } = require('../config/env');
const {
  createUser,
  findUserByEmailWithPassword,
  findUserById,
  updateUserPasswordHash,
} = require('../models/userModel');
const {
  createRefreshToken,
  findActiveRefreshTokenByHash,
  revokeRefreshTokenByHash,
  revokeRefreshTokensForUser,
} = require('../models/refreshTokenModel');
const {
  createPasswordResetCode,
  consumeActivePasswordResetCodesForUser,
  findLatestActivePasswordResetCodeForUser,
  consumePasswordResetCode,
  registerFailedPasswordResetAttempt,
} = require('../models/passwordResetCodeModel');
const {
  signAccessToken,
  generateRefreshToken,
  hashRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const { hasEmailConfig, sendPasswordResetCodeEmail } = require('./emailService');
const { HttpError } = require('../utils/httpError');

const SALT_ROUNDS = 12;
const PASSWORD_RESET_CODE_LENGTH = 6;
const PASSWORD_RESET_MESSAGE =
  'If an account with that email exists, a reset code was sent.';

const getPasswordResetSecret = () => env.PASSWORD_RESET_SECRET || env.REFRESH_TOKEN_SECRET;

const generatePasswordResetCode = () =>
  Array.from({ length: PASSWORD_RESET_CODE_LENGTH }, () => crypto.randomInt(0, 10)).join('');

const hashPasswordResetCode = ({ userId, code }) =>
  crypto
    .createHmac('sha256', getPasswordResetSecret())
    .update(`${userId}:${String(code).trim()}`)
    .digest('hex');

const secureHashEquals = (left, right) => {
  const a = Buffer.from(String(left || ''));
  const b = Buffer.from(String(right || ''));

  if (a.length !== b.length) {
    return false;
  }

  return crypto.timingSafeEqual(a, b);
};

const issueAuthTokens = async (userId) => {
  const user = await findUserById(userId);

  if (!user) {
    throw new HttpError(401, 'User no longer exists');
  }

  const accessToken = signAccessToken(user);
  const refreshToken = generateRefreshToken();
  const refreshTokenHash = hashRefreshToken(refreshToken);

  await createRefreshToken({
    id: uuidv4(),
    userId: user.id,
    tokenHash: refreshTokenHash,
    expiresAt: getRefreshTokenExpiryDate(),
  });

  return {
    user,
    accessToken,
    refreshToken,
  };
};

const registerUser = async ({ username, email, password }) => {
  const existing = await findUserByEmailWithPassword(email);

  if (existing) {
    throw new HttpError(409, 'Email is already in use');
  }

  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

  const user = await createUser({
    id: uuidv4(),
    username,
    email,
    passwordHash,
  });

  const accessToken = signAccessToken(user);
  const refreshToken = generateRefreshToken();

  await createRefreshToken({
    id: uuidv4(),
    userId: user.id,
    tokenHash: hashRefreshToken(refreshToken),
    expiresAt: getRefreshTokenExpiryDate(),
  });

  return {
    user,
    accessToken,
    refreshToken,
  };
};

const loginUser = async ({ email, password }) => {
  const userWithPassword = await findUserByEmailWithPassword(email);

  if (!userWithPassword) {
    throw new HttpError(401, 'Invalid credentials');
  }

  const passwordMatches = await bcrypt.compare(password, userWithPassword.passwordHash);

  if (!passwordMatches) {
    throw new HttpError(401, 'Invalid credentials');
  }

  return issueAuthTokens(userWithPassword.id);
};

const refreshUserTokens = async (refreshToken) => {
  const tokenHash = hashRefreshToken(refreshToken);
  const storedToken = await findActiveRefreshTokenByHash(tokenHash);

  if (!storedToken) {
    throw new HttpError(401, 'Refresh token is invalid or expired');
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
    tokenHash: newRefreshTokenHash,
    expiresAt: getRefreshTokenExpiryDate(),
  });

  const user = await findUserById(storedToken.userId);

  if (!user) {
    throw new HttpError(401, 'User no longer exists');
  }

  return {
    user,
    accessToken: signAccessToken(user),
    refreshToken: newRefreshToken,
  };
};

const logoutUser = async (refreshToken) => {
  const tokenHash = hashRefreshToken(refreshToken);
  await revokeRefreshTokenByHash({ tokenHash });
};

const requestPasswordResetCode = async ({ email }) => {
  if (env.NODE_ENV === 'production' && !hasEmailConfig()) {
    throw new HttpError(503, 'Password reset email is not configured yet');
  }

  const userWithPassword = await findUserByEmailWithPassword(email);

  if (!userWithPassword) {
    return { message: PASSWORD_RESET_MESSAGE };
  }

  const latestCode = await findLatestActivePasswordResetCodeForUser(userWithPassword.id);
  const cooldownMs = env.PASSWORD_RESET_REQUEST_COOLDOWN_SECONDS * 1000;

  if (
    latestCode &&
    Date.now() - new Date(latestCode.createdAt).getTime() < cooldownMs
  ) {
    return { message: PASSWORD_RESET_MESSAGE };
  }

  await consumeActivePasswordResetCodesForUser(userWithPassword.id);

  const code = generatePasswordResetCode();
  const codeHash = hashPasswordResetCode({
    userId: userWithPassword.id,
    code,
  });
  const expiresAt = new Date(Date.now() + env.PASSWORD_RESET_CODE_TTL_MINUTES * 60 * 1000);

  await createPasswordResetCode({
    id: uuidv4(),
    userId: userWithPassword.id,
    codeHash,
    expiresAt,
  });

  try {
    await sendPasswordResetCodeEmail({
      toEmail: userWithPassword.email,
      username: userWithPassword.username,
      code,
      expiresInMinutes: env.PASSWORD_RESET_CODE_TTL_MINUTES,
    });
  } catch (error) {
    console.error('Password reset email failed', error);
    if (error instanceof HttpError) {
      throw error;
    }
    throw new HttpError(503, 'Password reset is temporarily unavailable. Try again in a minute.');
  }

  return { message: PASSWORD_RESET_MESSAGE };
};

const resetPasswordWithCode = async ({ email, code, newPassword }) => {
  const userWithPassword = await findUserByEmailWithPassword(email);

  if (!userWithPassword) {
    throw new HttpError(400, 'Invalid reset code or email');
  }

  const resetCodeRecord = await findLatestActivePasswordResetCodeForUser(userWithPassword.id);

  if (!resetCodeRecord) {
    throw new HttpError(400, 'Invalid reset code or email');
  }

  const providedHash = hashPasswordResetCode({
    userId: userWithPassword.id,
    code,
  });
  const matches = secureHashEquals(providedHash, resetCodeRecord.codeHash);

  if (!matches) {
    const attempts = await registerFailedPasswordResetAttempt({
      id: resetCodeRecord.id,
      maxAttempts: env.PASSWORD_RESET_MAX_ATTEMPTS,
    });

    if (attempts >= env.PASSWORD_RESET_MAX_ATTEMPTS) {
      throw new HttpError(429, 'Too many invalid attempts. Request a new code');
    }

    throw new HttpError(400, 'Invalid reset code or email');
  }

  const passwordHash = await bcrypt.hash(newPassword, SALT_ROUNDS);

  await updateUserPasswordHash({
    userId: userWithPassword.id,
    passwordHash,
  });
  await consumePasswordResetCode(resetCodeRecord.id);
  await revokeRefreshTokensForUser(userWithPassword.id);
};

module.exports = {
  registerUser,
  loginUser,
  refreshUserTokens,
  logoutUser,
  requestPasswordResetCode,
  resetPasswordWithCode,
};
