const express = require('express');
const {
  listMessages,
  sendTextMessage,
  sendUploadedMessage,
  markSeen,
  toggleReaction,
} = require('../controllers/messageController');
const { upload } = require('../middleware/uploadMiddleware');
const { validateRequest } = require('../middleware/validateRequest');
const {
  sendTextMessageSchema,
  messageIdParamsSchema,
  listMessagesSchema,
  markSeenSchema,
  toggleReactionSchema,
} = require('../schemas/messageSchemas');
const { conversationParamsSchema } = require('../schemas/conversationSchemas');

const router = express.Router();

router.get(
  '/:conversationId',
  validateRequest(conversationParamsSchema, 'params'),
  validateRequest(listMessagesSchema, 'query'),
  listMessages,
);
router.post(
  '/:conversationId',
  validateRequest(conversationParamsSchema, 'params'),
  validateRequest(sendTextMessageSchema),
  sendTextMessage,
);
router.post(
  '/:conversationId/upload',
  validateRequest(conversationParamsSchema, 'params'),
  upload.single('file'),
  sendUploadedMessage,
);
router.post(
  '/:conversationId/seen',
  validateRequest(conversationParamsSchema, 'params'),
  validateRequest(markSeenSchema),
  markSeen,
);
router.put(
  '/:messageId/reaction',
  validateRequest(messageIdParamsSchema, 'params'),
  validateRequest(toggleReactionSchema),
  toggleReaction,
);

module.exports = router;
