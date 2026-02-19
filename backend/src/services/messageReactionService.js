const { HttpError } = require('../utils/httpError');
const { toggleMessageReaction } = require('../models/messageReactionModel');

const toggleReactionForMessage = async ({ userId, messageId, emoji }) => {
  try {
    const update = await toggleMessageReaction({
      userId,
      messageId,
      emoji,
    });

    if (!update) {
      throw new HttpError(404, 'Message not found');
    }

    return update;
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }

    if (error?.code === 'BLOCKED_INTERACTION') {
      throw new HttpError(403, 'You cannot interact with this user');
    }

    throw error;
  }
};

module.exports = {
  toggleReactionForMessage,
};
