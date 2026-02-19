const { z } = require('zod');

const passwordSchema = z
  .string()
  .min(8)
  .max(128)
  .regex(/[a-z]/, 'Password must include a lowercase letter')
  .regex(/[A-Z]/, 'Password must include an uppercase letter')
  .regex(/[0-9]/, 'Password must include a number');

const phoneNumberSchema = z
  .string()
  .trim()
  .regex(/^\+?[1-9]\d{7,14}$/, 'Phone number must be a valid international format');

const deviceIdSchema = z.string().trim().min(16).max(128);

const otpPurposeSchema = z.enum(['register', 'reset']);

const registerSchema = z.object({
  verificationToken: z.string().trim().min(30).max(2000),
  displayName: z.string().trim().min(2).max(40),
  bio: z.string().trim().max(160).optional(),
  password: passwordSchema,
  deviceId: deviceIdSchema,
});

const loginSchema = z.object({
  phoneNumber: phoneNumberSchema,
  password: z.string().min(1),
  deviceId: deviceIdSchema,
});

const requestOtpSchema = z.object({
  phoneNumber: phoneNumberSchema,
  purpose: otpPurposeSchema.default('register').optional(),
});

const verifyOtpSchema = z.object({
  phoneNumber: phoneNumberSchema,
  code: z.string().trim().regex(/^\d{6}$/, 'Code must be 6 digits'),
  purpose: otpPurposeSchema.default('register').optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(30),
});

const logoutSchema = z.object({
  refreshToken: z.string().min(30),
});

const forgotPasswordRequestSchema = z.object({
  phoneNumber: phoneNumberSchema,
});

const forgotPasswordConfirmSchema = z.object({
  phoneNumber: phoneNumberSchema,
  code: z.string().trim().regex(/^\d{6}$/, 'Code must be 6 digits'),
  newPassword: passwordSchema,
  deviceId: deviceIdSchema.optional(),
});

module.exports = {
  requestOtpSchema,
  verifyOtpSchema,
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  forgotPasswordRequestSchema,
  forgotPasswordConfirmSchema,
};
