const { z } = require('zod');

const passwordSchema = z
  .string()
  .min(8)
  .max(128)
  .regex(/[a-z]/, 'Password must include a lowercase letter')
  .regex(/[A-Z]/, 'Password must include an uppercase letter')
  .regex(/[0-9]/, 'Password must include a number');

const registerSchema = z.object({
  username: z.string().min(3).max(30).regex(/^[a-zA-Z0-9_]+$/, 'Only letters, numbers, and underscores'),
  email: z.string().email().max(255),
  password: passwordSchema,
});

const loginSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(30),
});

const logoutSchema = z.object({
  refreshToken: z.string().min(30),
});

const forgotPasswordRequestSchema = z.object({
  email: z.string().email().max(255),
});

const forgotPasswordConfirmSchema = z.object({
  email: z.string().email().max(255),
  code: z.string().trim().regex(/^\d{6}$/, 'Code must be 6 digits'),
  newPassword: passwordSchema,
});

module.exports = {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  forgotPasswordRequestSchema,
  forgotPasswordConfirmSchema,
};
