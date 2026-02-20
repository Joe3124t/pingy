const { z } = require('zod');

const usernameSchema = z
  .string()
  .trim()
  .min(3)
  .max(30)
  .regex(/^[a-zA-Z0-9_]+$/, 'Only letters, numbers, and underscores');

const wallpaperUrlSchema = z
  .string()
  .trim()
  .min(1)
  .max(500)
  .refine(
    (value) => value.startsWith('/uploads/') || /^https?:\/\//i.test(value),
    'Wallpaper URL must be an http(s) URL or /uploads path',
  );

const optionalWallpaperUrlSchema = z.preprocess((value) => {
  if (value === undefined || value === null) {
    return value;
  }

  const normalized = String(value).trim();
  return normalized.length === 0 ? null : normalized;
}, wallpaperUrlSchema.nullable().optional());

const updateProfileSchema = z.object({
  username: usernameSchema.optional(),
  bio: z.string().trim().max(160).optional(),
});

const updatePrivacySchema = z.object({
  showOnlineStatus: z.boolean().optional(),
  readReceiptsEnabled: z.boolean().optional(),
});

const updateChatSchema = z.object({
  themeMode: z.enum(['light', 'dark', 'auto']).optional(),
  defaultWallpaperUrl: optionalWallpaperUrlSchema,
});

const userIdParamsSchema = z.object({
  userId: z.string().uuid(),
});

const apnsEndpointPattern = /^apns:\/\/[A-Fa-f0-9]{64}$/;

const pushEndpointSchema = z.string().trim().max(2000).refine((value) => {
  if (apnsEndpointPattern.test(value)) {
    return true;
  }

  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' || parsed.protocol === 'http:';
  } catch {
    return false;
  }
}, 'Push endpoint must be a valid http(s) URL or apns://<device-token>');

const pushSubscriptionSchema = z.object({
  endpoint: pushEndpointSchema,
  keys: z.object({
    p256dh: z.string().trim().min(1).max(300),
    auth: z.string().trim().min(1).max(300),
  }),
  expirationTime: z.number().nullable().optional(),
});

const savePushSubscriptionSchema = z.object({
  subscription: pushSubscriptionSchema,
});

const deletePushSubscriptionSchema = z.object({
  endpoint: pushEndpointSchema,
});

const contactHashItemSchema = z.object({
  hash: z
    .string()
    .trim()
    .regex(/^[a-fA-F0-9]{64}$/, 'hash must be a valid SHA-256 hex string')
    .transform((value) => value.toLowerCase()),
  label: z.string().trim().min(1).max(120),
});

const syncContactsSchema = z.object({
  contacts: z.array(contactHashItemSchema).min(1).max(5000),
});

module.exports = {
  updateProfileSchema,
  updatePrivacySchema,
  updateChatSchema,
  userIdParamsSchema,
  savePushSubscriptionSchema,
  deletePushSubscriptionSchema,
  syncContactsSchema,
};
