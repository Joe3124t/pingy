const { asyncHandler } = require('../utils/asyncHandler');
const { HttpError } = require('../utils/httpError');
const { sanitizeText } = require('../utils/sanitize');
const { uploadBuffer } = require('../services/storageService');
const { signMediaUrl } = require('../services/mediaAccessService');
const {
  createStatusStory,
  findStatusStoryById,
  listVisibleStatusStories,
  markStatusStoryViewed,
  softDeleteStatusStory,
} = require('../models/statusStoryModel');
const { inferStatusContentType } = require('../middleware/statusUploadMiddleware');

const normalizeBackgroundHex = (value) => {
  if (!value) {
    return null;
  }

  const trimmed = String(value).trim();
  if (!trimmed) {
    return null;
  }

  return trimmed.startsWith('#') ? trimmed : `#${trimmed}`;
};

const toStoryPayload = (story, viewerUserId) => ({
  id: story.id,
  ownerUserID: story.ownerUserId,
  ownerName: story.ownerName,
  ownerAvatarURL: signMediaUrl(story.ownerAvatarUrl),
  contentType: story.contentType,
  text: story.text,
  mediaURL: signMediaUrl(story.mediaUrl),
  backgroundHex: story.backgroundHex,
  privacy: story.privacy,
  createdAt: story.createdAt,
  expiresAt: story.expiresAt,
  viewers:
    story.ownerUserId === viewerUserId
      ? (story.viewers || []).filter((entry) => entry.id && entry.viewedAt)
      : [],
});

const listStatusStories = asyncHandler(async (req, res) => {
  const stories = await listVisibleStatusStories({ viewerUserId: req.user.id });

  res.status(200).json({
    stories: stories.map((story) => toStoryPayload(story, req.user.id)),
  });
});

const createTextStatus = asyncHandler(async (req, res) => {
  const text = sanitizeText(req.body?.text || '', 1000);

  if (!text) {
    throw new HttpError(400, 'Text status is required');
  }

  const created = await createStatusStory({
    ownerUserId: req.user.id,
    contentType: 'text',
    text,
    mediaUrl: null,
    backgroundHex: normalizeBackgroundHex(req.body?.backgroundHex),
    privacy: req.body?.privacy || 'contacts',
  });

  if (!created) {
    throw new HttpError(500, 'Could not create status');
  }

  res.status(201).json({
    story: toStoryPayload(created, req.user.id),
  });
});

const createMediaStatus = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new HttpError(400, 'Status media file is required');
  }

  const inferredType = inferStatusContentType(req.file.mimetype);
  const requestedType = req.body?.contentType;
  const contentType = requestedType || inferredType;

  if (requestedType && requestedType !== inferredType) {
    throw new HttpError(400, 'Status content type does not match uploaded file');
  }

  const uploaded = await uploadBuffer({
    buffer: req.file.buffer,
    originalName: req.file.originalname || `status-${Date.now()}`,
    mimeType: req.file.mimetype,
    folder: `status/${contentType}`,
  });

  const created = await createStatusStory({
    ownerUserId: req.user.id,
    contentType,
    text: null,
    mediaUrl: uploaded.url,
    backgroundHex: null,
    privacy: req.body?.privacy || 'contacts',
  });

  if (!created) {
    throw new HttpError(500, 'Could not create status');
  }

  res.status(201).json({
    story: toStoryPayload(created, req.user.id),
  });
});

const markStatusViewed = asyncHandler(async (req, res) => {
  const story = await findStatusStoryById(req.params.storyId);

  if (!story || !story.id) {
    throw new HttpError(404, 'Status not found');
  }

  if (story.ownerUserId !== req.user.id) {
    const viewed = await markStatusStoryViewed({
      storyId: req.params.storyId,
      viewerUserId: req.user.id,
    });

    if (!viewed) {
      throw new HttpError(404, 'Status not available');
    }
  }

  const refreshed = await findStatusStoryById(req.params.storyId);

  res.status(200).json({
    story: refreshed ? toStoryPayload(refreshed, req.user.id) : null,
  });
});

const deleteStatus = asyncHandler(async (req, res) => {
  const removed = await softDeleteStatusStory({
    storyId: req.params.storyId,
    ownerUserId: req.user.id,
  });

  if (!removed) {
    throw new HttpError(404, 'Status not found');
  }

  res.status(204).send();
});

module.exports = {
  listStatusStories,
  createTextStatus,
  createMediaStatus,
  markStatusViewed,
  deleteStatus,
};
