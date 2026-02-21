const express = require('express');
const {
  listStatusStories,
  createTextStatus,
  createMediaStatus,
  markStatusViewed,
  deleteStatus,
} = require('../controllers/statusController');
const { validateRequest } = require('../middleware/validateRequest');
const { statusUpload } = require('../middleware/statusUploadMiddleware');
const {
  createTextStatusSchema,
  createMediaStatusSchema,
  statusStoryParamsSchema,
} = require('../schemas/statusSchemas');

const router = express.Router();

router.get('/', listStatusStories);
router.post('/text', validateRequest(createTextStatusSchema), createTextStatus);
router.post(
  '/media',
  statusUpload.single('file'),
  validateRequest(createMediaStatusSchema),
  createMediaStatus,
);
router.post('/:storyId/view', validateRequest(statusStoryParamsSchema, 'params'), markStatusViewed);
router.delete('/:storyId', validateRequest(statusStoryParamsSchema, 'params'), deleteStatus);

module.exports = router;
