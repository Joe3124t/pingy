const express = require('express');
const {
  listConversations,
  createDirectConversation,
  deleteConversation,
  updateConversationWallpaper,
  resetConversationWallpaper,
  uploadConversationWallpaper,
} = require('../controllers/conversationController');
const { validateRequest } = require('../middleware/validateRequest');
const {
  createDirectConversationSchema,
  conversationParamsSchema,
  deleteConversationQuerySchema,
  conversationWallpaperSchema,
} = require('../schemas/conversationSchemas');
const { wallpaperUpload } = require('../middleware/wallpaperUploadMiddleware');

const router = express.Router();

router.get('/', listConversations);
router.post('/direct', validateRequest(createDirectConversationSchema), createDirectConversation);
router.delete(
  '/:conversationId',
  validateRequest(conversationParamsSchema, 'params'),
  validateRequest(deleteConversationQuerySchema, 'query'),
  deleteConversation,
);
router.put(
  '/:conversationId/wallpaper',
  validateRequest(conversationParamsSchema, 'params'),
  validateRequest(conversationWallpaperSchema),
  updateConversationWallpaper,
);
router.post(
  '/:conversationId/wallpaper/upload',
  validateRequest(conversationParamsSchema, 'params'),
  wallpaperUpload.single('wallpaper'),
  uploadConversationWallpaper,
);
router.delete(
  '/:conversationId/wallpaper',
  validateRequest(conversationParamsSchema, 'params'),
  resetConversationWallpaper,
);

module.exports = router;
