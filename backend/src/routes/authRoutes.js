const express = require('express');
const {
  requestOtp,
  verifyOtp,
  register,
  login,
  refresh,
  logout,
  me,
  requestPasswordReset,
  confirmPasswordReset,
} = require('../controllers/authController');
const { authMiddleware } = require('../middleware/authMiddleware');
const { validateRequest } = require('../middleware/validateRequest');
const {
  requestOtpSchema,
  verifyOtpSchema,
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  forgotPasswordRequestSchema,
  forgotPasswordConfirmSchema,
} = require('../schemas/authSchemas');

const router = express.Router();

router.post('/phone/request-otp', validateRequest(requestOtpSchema), requestOtp);
router.post('/phone/verify-otp', validateRequest(verifyOtpSchema), verifyOtp);
router.post('/register', validateRequest(registerSchema), register);
router.post('/login', validateRequest(loginSchema), login);
router.post('/refresh', validateRequest(refreshSchema), refresh);
router.post('/logout', validateRequest(logoutSchema), logout);
router.post('/forgot-password/request', validateRequest(forgotPasswordRequestSchema), requestPasswordReset);
router.post('/forgot-password/confirm', validateRequest(forgotPasswordConfirmSchema), confirmPasswordReset);
router.get('/me', authMiddleware, me);

module.exports = router;
