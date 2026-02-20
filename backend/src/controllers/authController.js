const { asyncHandler } = require('../utils/asyncHandler');
const {
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
} = require('../services/authService');
const { signMediaUrlsInUser } = require('../services/mediaAccessService');

const requestOtp = asyncHandler(async (req, res) => {
  res.status(410).json({
    message: 'SMS OTP is disabled. Use Authenticator setup instead.',
  });
});

const verifyOtp = asyncHandler(async (req, res) => {
  res.status(410).json({
    message: 'SMS OTP is disabled. Use Authenticator setup instead.',
  });
});

const signupStart = asyncHandler(async (req, res) => {
  const { phoneNumber } = req.body;
  const result = await startAuthenticatorSignup({ phoneNumber });
  res.status(200).json(result);
});

const signupVerify = asyncHandler(async (req, res) => {
  const { challengeToken, code } = req.body;
  const result = await verifyAuthenticatorSignup({
    challengeToken,
    code,
  });
  res.status(200).json(result);
});

const signupComplete = asyncHandler(async (req, res) => {
  const { registrationToken, displayName, bio, password, deviceId } = req.body;
  const auth = await completeAuthenticatorSignup({
    registrationToken,
    displayName,
    bio,
    password,
    deviceId,
  });

  res.status(201).json({
    user: signMediaUrlsInUser(auth.user),
    tokens: {
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    },
    recoveryCodes: auth.recoveryCodes,
  });
});

const register = asyncHandler(async (req, res) => {
  const payload = req.body;
  const auth = await registerUser(payload);

  res.status(201).json({
    user: {
      ...signMediaUrlsInUser(auth.user),
      deviceId: req.body?.deviceId || null,
    },
    tokens: {
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    },
  });
});

const login = asyncHandler(async (req, res) => {
  const payload = req.body;
  const auth = await loginUser(payload);

  if (auth.requiresTotp) {
    res.status(200).json({
      requiresTotp: true,
      challengeToken: auth.challengeToken,
      userHint: auth.userHint,
      message: 'Enter your authenticator code to continue',
    });
    return;
  }

  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(auth.user),
      deviceId: req.body?.deviceId || null,
    },
    tokens: {
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    },
  });
});

const verifyTotpLoginController = asyncHandler(async (req, res) => {
  const { challengeToken, code, recoveryCode } = req.body;
  const result = await verifyTotpLogin({
    challengeToken,
    code,
    recoveryCode,
  });

  res.status(200).json({
    user: signMediaUrlsInUser(result.auth.user),
    tokens: {
      accessToken: result.auth.accessToken,
      refreshToken: result.auth.refreshToken,
    },
  });
});

const refresh = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  const auth = await refreshUserTokens(refreshToken);

  res.status(200).json({
    user: signMediaUrlsInUser(auth.user),
    tokens: {
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    },
  });
});

const logout = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  await logoutUser(refreshToken);

  res.status(204).send();
});

const me = asyncHandler(async (req, res) => {
  res.status(200).json({
    user: {
      ...signMediaUrlsInUser(req.user),
      deviceId: req.auth?.deviceId || null,
    },
  });
});

const requestPasswordReset = asyncHandler(async (req, res) => {
  const { phoneNumber } = req.body;
  const result = await requestPasswordResetCode({ phoneNumber });

  res.status(200).json(result);
});

const confirmPasswordReset = asyncHandler(async (req, res) => {
  const { phoneNumber, code, newPassword, deviceId } = req.body;

  await resetPasswordWithCode({
    phoneNumber,
    code,
    newPassword,
    deviceId,
  });

  res.status(200).json({
    message: 'Password reset successful. You can now log in',
  });
});

const getTotpStatusController = asyncHandler(async (req, res) => {
  const status = await getTotpStatusForUser({
    userId: req.auth.userId,
  });

  res.status(200).json(status);
});

const startTotpSetupController = asyncHandler(async (req, res) => {
  const setup = await startTotpSetup({
    userId: req.auth.userId,
  });

  res.status(200).json(setup);
});

const verifyTotpSetupController = asyncHandler(async (req, res) => {
  const { code } = req.body;
  const result = await verifyTotpSetup({
    userId: req.auth.userId,
    code,
  });

  res.status(200).json(result);
});

const disableTotpController = asyncHandler(async (req, res) => {
  const { code, recoveryCode } = req.body;
  const result = await disableTotpForUser({
    userId: req.auth.userId,
    code,
    recoveryCode,
  });

  res.status(200).json(result);
});

module.exports = {
  requestOtp,
  verifyOtp,
  signupStart,
  signupVerify,
  signupComplete,
  register,
  login,
  verifyTotpLoginController,
  refresh,
  logout,
  me,
  requestPasswordReset,
  confirmPasswordReset,
  getTotpStatusController,
  startTotpSetupController,
  verifyTotpSetupController,
  disableTotpController,
};
