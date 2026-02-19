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

const pushSubscriptionSchema = z.object({
  endpoint: z.string().trim().url().max(2000),
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
  endpoint: z.string().trim().url().max(2000),
});

module.exports = {
  updateProfileSchema,
  updatePrivacySchema,
  updateChatSchema,
  userIdParamsSchema,
  savePushSubscriptionSchema,
  deletePushSubscriptionSchema,
};
