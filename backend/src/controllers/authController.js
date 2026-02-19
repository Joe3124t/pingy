const { asyncHandler } = require('../utils/asyncHandler');
const {
  requestPhoneOtp,
  verifyPhoneOtp,
  registerUser,
  loginUser,
  refreshUserTokens,
  logoutUser,
  requestPasswordResetCode,
  resetPasswordWithCode,
} = require('../services/authService');
const { signMediaUrlsInUser } = require('../services/mediaAccessService');

const requestOtp = asyncHandler(async (req, res) => {
  const { phoneNumber, purpose = 'register' } = req.body;
  const result = await requestPhoneOtp({ phoneNumber, purpose });

  res.status(200).json(result);
});

const verifyOtp = asyncHandler(async (req, res) => {
  const { phoneNumber, code, purpose = 'register' } = req.body;
  const result = await verifyPhoneOtp({ phoneNumber, code, purpose });

  res.status(200).json(result);
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

module.exports = {
  requestOtp,
  verifyOtp,
  register,
  login,
  refresh,
  logout,
  me,
  requestPasswordReset,
  confirmPasswordReset,
};
