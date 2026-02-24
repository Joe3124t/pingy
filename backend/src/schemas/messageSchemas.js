const { z } = require('zod');
const plainTextBodySchema = z.string().trim().min(1).max(4000);

const sendTextMessageSchema = z.object({
  body: plainTextBodySchema,
  clientId: z.string().min(5).max(80).optional(),
  replyToMessageId: z.string().trim().min(1).max(120).optional(),
});

const messageIdParamsSchema = z.object({
  messageId: z.string().uuid(),
});

const listMessagesSchema = z.object({
  // Allow larger windows for mobile resync calls while keeping a sane upper bound.
  limit: z.coerce.number().int().min(1).max(500).default(40),
  before: z.string().datetime({ offset: true }).optional(),
  after: z.string().datetime({ offset: true }).optional(),
});

const markSeenSchema = z.object({
  messageIds: z.array(z.string().uuid()).max(200).optional(),
});

const uploadMessageSchema = z.object({
  type: z.enum(['image', 'video', 'file', 'voice']).optional(),
  body: z.string().max(500).optional(),
  voiceDurationMs: z.coerce.number().int().min(0).max(3600000).optional(),
  clientId: z.string().min(5).max(80).optional(),
  replyToMessageId: z.string().trim().min(1).max(120).optional(),
});

const reactionEmojiValues = [
  '\u{1F44D}',
  '\u{2764}\u{FE0F}',
  '\u{1F602}',
  '\u{1F62E}',
  '\u{1F622}',
  '\u{1F525}',
  '\u{1F44F}',
  '\u{1F64F}',
];

const toggleReactionSchema = z.object({
  emoji: z.enum(reactionEmojiValues),
});

module.exports = {
  sendTextMessageSchema,
  messageIdParamsSchema,
  listMessagesSchema,
  markSeenSchema,
  uploadMessageSchema,
  reactionEmojiValues,
  toggleReactionSchema,
};
