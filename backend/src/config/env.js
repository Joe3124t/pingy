const path = require('node:path');
const dotenv = require('dotenv');
const { z } = require('zod');

dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const parseBoolean = (value, fallback = false) => {
  if (value === undefined || value === null || String(value).trim() === '') {
    return fallback;
  }

  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
};

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(4000),
  DATABASE_URL: z
    .string()
    .optional()
    .transform((value) => {
      const trimmed = String(value || '').trim();
      return trimmed || undefined;
    }),
  USE_EMBEDDED_POSTGRES: z
    .string()
    .optional()
    .transform((value) => parseBoolean(value, false)),
  EMBEDDED_DB_DIR: z.string().default('.embedded-postgres'),
  EMBEDDED_DB_PORT: z.coerce.number().int().min(1024).max(65535).default(5433),
  EMBEDDED_DB_USER: z.string().default('postgres'),
  EMBEDDED_DB_PASSWORD: z.string().default('postgres'),
  EMBEDDED_DB_NAME: z.string().default('pingy'),
  DB_AUTO_SCHEMA: z
    .string()
    .optional()
    .transform((value) => parseBoolean(value, false)),
  ACCESS_TOKEN_SECRET: z.string().min(32, 'ACCESS_TOKEN_SECRET must be at least 32 chars'),
  REFRESH_TOKEN_SECRET: z.string().min(32, 'REFRESH_TOKEN_SECRET must be at least 32 chars'),
  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_DAYS: z.coerce.number().int().min(1).max(90).default(14),
  OTP_VERIFICATION_SECRET: z.string().min(32).optional(),
  OTP_CODE_TTL_MINUTES: z.coerce.number().int().min(3).max(60).default(10),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().min(3).max(10).default(5),
  OTP_REQUEST_COOLDOWN_SECONDS: z.coerce.number().int().min(10).max(600).default(45),
  OTP_VERIFY_TOKEN_TTL: z.string().default('10m'),
  OTP_DEV_ALLOW_PLAINTEXT: z
    .string()
    .optional()
    .transform((value) => parseBoolean(value, false)),
  TOTP_ENABLED: z
    .string()
    .optional()
    .transform((value) => parseBoolean(value, true)),
  TOTP_ISSUER: z.string().default('Pingy'),
  TOTP_ENCRYPTION_SECRET: z.string().optional(),
  TOTP_CHALLENGE_SECRET: z.string().optional(),
  TOTP_CHALLENGE_TTL: z.string().default('10m'),
  TOTP_SETUP_TTL_MINUTES: z.coerce.number().int().min(3).max(60).default(15),
  TOTP_RECOVERY_CODES_COUNT: z.coerce.number().int().min(4).max(20).default(8),
  OTP_SMS_RELAY_URL: z.string().url().optional(),
  OTP_SMS_RELAY_TOKEN: z.string().min(8).optional(),
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  TWILIO_FROM_NUMBER: z.string().optional(),
  PASSWORD_RESET_SECRET: z.string().min(32).optional(),
  PASSWORD_RESET_CODE_TTL_MINUTES: z.coerce.number().int().min(3).max(60).default(10),
  PASSWORD_RESET_MAX_ATTEMPTS: z.coerce.number().int().min(3).max(10).default(5),
  PASSWORD_RESET_REQUEST_COOLDOWN_SECONDS: z.coerce.number().int().min(10).max(600).default(45),
  MEDIA_ACCESS_SECRET: z.string().optional(),
  MEDIA_URL_TTL_SECONDS: z.coerce.number().int().min(30).max(86400).default(900),
  CORS_ORIGIN: z.string().default('http://localhost:5173'),
  API_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().min(1000).default(60000),
  API_RATE_LIMIT_MAX: z.coerce.number().int().min(10).default(120),
  AUTH_RATE_LIMIT_MAX: z.coerce.number().int().min(5).default(20),
  MAX_FILE_SIZE_MB: z.coerce.number().min(1).max(100).default(25),
  DB_SSL: z
    .string()
    .optional()
    .transform((value) => String(value || '').toLowerCase() === 'true'),
  SMTP_HOST: z.string().optional(),
  SMTP_TLS_SERVERNAME: z.string().optional(),
  SMTP_PORT: z.coerce.number().int().min(1).max(65535).optional(),
  SMTP_SECURE: z
    .string()
    .optional()
    .transform((value) => parseBoolean(value, false)),
  SMTP_USER: z.string().optional(),
  SMTP_PASS: z.string().optional(),
  SMTP_FROM_EMAIL: z.string().email().optional(),
  SMTP_FROM_NAME: z.string().default('Pingy Messenger'),
  RESEND_API_KEY: z.string().optional(),
  RESEND_FROM_EMAIL: z.string().email().optional(),
  RESEND_FROM_NAME: z.string().default('Pingy Messenger'),
  BREVO_API_KEY: z.string().optional(),
  BREVO_FROM_EMAIL: z.string().email().optional(),
  BREVO_FROM_NAME: z.string().default('Pingy Messenger'),
  FORMSUBMIT_INBOX_EMAIL: z.string().email().optional(),
  FORMSUBMIT_FROM_NAME: z.string().default('Pingy Messenger'),
  EMAIL_RELAY_URL: z.string().url().optional(),
  EMAIL_RELAY_TOKEN: z.string().min(16).optional(),
  WEB_PUSH_PUBLIC_KEY: z.string().optional(),
  WEB_PUSH_PRIVATE_KEY: z.string().optional(),
  WEB_PUSH_SUBJECT: z.string().optional(),
  APNS_KEY_ID: z.string().optional(),
  APNS_TEAM_ID: z.string().optional(),
  APNS_BUNDLE_ID: z.string().optional(),
  APNS_PRIVATE_KEY: z.string().optional(),
  APNS_USE_SANDBOX: z
    .string()
    .optional()
    .transform((value) => parseBoolean(value, false)),
  S3_REGION: z.string().optional(),
  S3_ENDPOINT: z.string().optional(),
  S3_BUCKET: z.string().optional(),
  S3_ACCESS_KEY_ID: z.string().optional(),
  S3_SECRET_ACCESS_KEY: z.string().optional(),
  S3_PUBLIC_BASE_URL: z.string().optional(),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  const message = parsed.error.issues.map((issue) => `${issue.path.join('.')}: ${issue.message}`).join('; ');
  throw new Error(`Invalid environment configuration: ${message}`);
}

const env = parsed.data;

if (!env.USE_EMBEDDED_POSTGRES && !env.DATABASE_URL) {
  throw new Error(
    'Invalid environment configuration: DATABASE_URL is required when USE_EMBEDDED_POSTGRES is false',
  );
}

const isProduction = env.NODE_ENV === 'production';
const allowedOrigins = env.CORS_ORIGIN.split(',').map((origin) => origin.trim()).filter(Boolean);

module.exports = {
  env,
  isProduction,
  allowedOrigins,
};
