const express = require('express');
const {
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
} = require('../controllers/authController');
const { authMiddleware } = require('../middleware/authMiddleware');
const { validateRequest } = require('../middleware/validateRequest');
const {
  requestOtpSchema,
  verifyOtpSchema,
  registerSchema,
  loginSchema,
  signupStartSchema,
  signupVerifySchema,
  signupCompleteSchema,
  refreshSchema,
  logoutSchema,
  forgotPasswordRequestSchema,
  forgotPasswordConfirmSchema,
  verifyTotpLoginSchema,
  verifyTotpSetupSchema,
  disableTotpSchema,
} = require('../schemas/authSchemas');

const router = express.Router();

router.post('/phone/request-otp', validateRequest(requestOtpSchema), requestOtp);
router.post('/phone/verify-otp', validateRequest(verifyOtpSchema), verifyOtp);
// Backward-compatible aliases for older native builds and mixed deployments.
router.post('/request-otp', validateRequest(requestOtpSchema), requestOtp);
router.post('/verify-otp', validateRequest(verifyOtpSchema), verifyOtp);
router.post('/phone/request', validateRequest(requestOtpSchema), requestOtp);
router.post('/phone/verify', validateRequest(verifyOtpSchema), verifyOtp);
router.post('/signup/start', validateRequest(signupStartSchema), signupStart);
router.post('/signup/verify', validateRequest(signupVerifySchema), signupVerify);
router.post('/signup/complete', validateRequest(signupCompleteSchema), signupComplete);
router.post('/register', validateRequest(registerSchema), register);
router.post('/login', validateRequest(loginSchema), login);
router.post('/totp/login/verify', validateRequest(verifyTotpLoginSchema), verifyTotpLoginController);
router.post('/login/totp/verify', validateRequest(verifyTotpLoginSchema), verifyTotpLoginController);
router.post('/refresh', validateRequest(refreshSchema), refresh);
router.post('/logout', validateRequest(logoutSchema), logout);
router.post('/forgot-password/request', validateRequest(forgotPasswordRequestSchema), requestPasswordReset);
router.post('/forgot-password/confirm', validateRequest(forgotPasswordConfirmSchema), confirmPasswordReset);
router.get('/me', authMiddleware, me);
router.get('/totp/status', authMiddleware, getTotpStatusController);
router.post('/totp/setup/start', authMiddleware, startTotpSetupController);
router.post('/totp/setup/verify', authMiddleware, validateRequest(verifyTotpSetupSchema), verifyTotpSetupController);
router.post('/totp/disable', authMiddleware, validateRequest(disableTotpSchema), disableTotpController);

module.exports = router;
