const express = require('express');
const {
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
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  forgotPasswordRequestSchema,
  forgotPasswordConfirmSchema,
} = require('../schemas/authSchemas');

const router = express.Router();

router.post('/register', validateRequest(registerSchema), register);
router.post('/login', validateRequest(loginSchema), login);
router.post('/refresh', validateRequest(refreshSchema), refresh);
router.post('/logout', validateRequest(logoutSchema), logout);
router.post('/forgot-password/request', validateRequest(forgotPasswordRequestSchema), requestPasswordReset);
router.post('/forgot-password/confirm', validateRequest(forgotPasswordConfirmSchema), confirmPasswordReset);
router.get('/me', authMiddleware, me);

module.exports = router;
