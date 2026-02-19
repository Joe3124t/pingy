const { z } = require('zod');

const uuidSchema = z.string().uuid();

const createDirectConversationSchema = z.object({
  recipientId: uuidSchema,
});

const conversationSearchSchema = z.object({
  query: z.string().min(1).max(50),
  limit: z.coerce.number().int().min(1).max(50).default(15),
});

const conversationParamsSchema = z.object({
  conversationId: uuidSchema,
});

const deleteConversationQuerySchema = z.object({
  scope: z.enum(['self', 'both']).optional(),
});

const wallpaperUrlSchema = z
  .string()
  .trim()
  .min(1)
  .max(500)
  .refine(
    (value) => value.startsWith('/uploads/') || /^https?:\/\//i.test(value),
    'Wallpaper URL must be an http(s) URL or /uploads path',
  );

const nullableWallpaperUrlSchema = z.preprocess((value) => {
  if (value === undefined || value === null) {
    return value;
  }

  const normalized = String(value).trim();
  return normalized.length === 0 ? null : normalized;
}, wallpaperUrlSchema.nullable().optional());

const conversationWallpaperSchema = z.object({
  wallpaperUrl: nullableWallpaperUrlSchema,
  blurIntensity: z.coerce.number().int().min(0).max(20).default(0).optional(),
});

module.exports = {
  uuidSchema,
  createDirectConversationSchema,
  conversationSearchSchema,
  conversationParamsSchema,
  deleteConversationQuerySchema,
  conversationWallpaperSchema,
};
