const { asyncHandler } = require('../utils/asyncHandler');
const {
  registerUser,
  loginUser,
  refreshUserTokens,
  logoutUser,
  requestPasswordResetCode,
  resetPasswordWithCode,
} = require('../services/authService');
const { signMediaUrlsInUser } = require('../services/mediaAccessService');

const register = asyncHandler(async (req, res) => {
  const payload = req.body;
  const auth = await registerUser(payload);

  res.status(201).json({
    user: signMediaUrlsInUser(auth.user),
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
    user: signMediaUrlsInUser(auth.user),
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
    user: signMediaUrlsInUser(req.user),
  });
});

const requestPasswordReset = asyncHandler(async (req, res) => {
  const { email } = req.body;
  const result = await requestPasswordResetCode({ email });

  res.status(200).json(result);
});

const confirmPasswordReset = asyncHandler(async (req, res) => {
  const { email, code, newPassword } = req.body;

  await resetPasswordWithCode({
    email,
    code,
    newPassword,
  });

  res.status(200).json({
    message: 'Password reset successful. You can now log in',
  });
});

module.exports = {
  register,
  login,
  refresh,
  logout,
  me,
  requestPasswordReset,
  confirmPasswordReset,
};
