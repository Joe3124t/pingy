const express = require('express');
const { searchUsersController } = require('../controllers/conversationController');
const {
  getMySettings,
  updateProfileSettings,
  uploadAvatar,
  uploadDefaultWallpaper,
  updatePrivacySettings,
  updateChatSettings,
  blockUserController,
  unblockUserController,
  listBlockedUsersController,
  syncContactsController,
  deleteMyAccount,
  getPushPublicKeyController,
  saveMyPushSubscriptionController,
  deleteMyPushSubscriptionController,
} = require('../controllers/userController');
const { validateRequest } = require('../middleware/validateRequest');
const { conversationSearchSchema } = require('../schemas/conversationSchemas');
const {
  updateProfileSchema,
  updatePrivacySchema,
  updateChatSchema,
  userIdParamsSchema,
  savePushSubscriptionSchema,
  deletePushSubscriptionSchema,
  syncContactsSchema,
} = require('../schemas/userSchemas');
const { avatarUpload } = require('../middleware/avatarUploadMiddleware');
const { wallpaperUpload } = require('../middleware/wallpaperUploadMiddleware');

const router = express.Router();

router.get('/', validateRequest(conversationSearchSchema, 'query'), searchUsersController);
router.get('/me/settings', getMySettings);
router.post('/contact-sync', validateRequest(syncContactsSchema), syncContactsController);
router.patch('/me/profile', validateRequest(updateProfileSchema), updateProfileSettings);
router.post('/me/avatar', avatarUpload.single('avatar'), uploadAvatar);
router.post('/me/chat/wallpaper', wallpaperUpload.single('wallpaper'), uploadDefaultWallpaper);
router.patch('/me/privacy', validateRequest(updatePrivacySchema), updatePrivacySettings);
router.patch('/me/chat', validateRequest(updateChatSchema), updateChatSettings);
router.get('/me/push/public-key', getPushPublicKeyController);
router.post('/me/push-subscriptions', validateRequest(savePushSubscriptionSchema), saveMyPushSubscriptionController);
router.delete('/me/push-subscriptions', validateRequest(deletePushSubscriptionSchema), deleteMyPushSubscriptionController);
router.delete('/me', deleteMyAccount);
router.get('/blocked', listBlockedUsersController);
router.post('/:userId/block', validateRequest(userIdParamsSchema, 'params'), blockUserController);
router.delete('/:userId/block', validateRequest(userIdParamsSchema, 'params'), unblockUserController);

module.exports = router;
