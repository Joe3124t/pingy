const { z } = require('zod');

const statusPrivacySchema = z.enum(['contacts', 'custom']);
const statusContentTypeSchema = z.enum(['image', 'video']);

const createTextStatusSchema = z.object({
  text: z.string().trim().min(1).max(1000),
  backgroundHex: z
    .string()
    .trim()
    .regex(/^#?[0-9a-fA-F]{6}$/)
    .optional(),
  privacy: statusPrivacySchema.optional(),
});

const createMediaStatusSchema = z.object({
  contentType: statusContentTypeSchema.optional(),
  privacy: statusPrivacySchema.optional(),
});

const statusStoryParamsSchema = z.object({
  storyId: z.string().uuid(),
});

module.exports = {
  createTextStatusSchema,
  createMediaStatusSchema,
  statusStoryParamsSchema,
};
