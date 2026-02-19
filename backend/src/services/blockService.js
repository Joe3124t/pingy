const {
  blockUser,
  unblockUser,
  isEitherUserBlocked,
  listBlockedUsers,
} = require('../models/blockModel');
const { findUserById } = require('../models/userModel');
const { HttpError } = require('../utils/httpError');

const assertUsersCanInteract = async ({ firstUserId, secondUserId }) => {
  const blocked = await isEitherUserBlocked({ firstUserId, secondUserId });

  if (blocked) {
    throw new HttpError(403, 'You cannot interact with this user');
  }
};

const blockTargetUser = async ({ blockerId, blockedId }) => {
  if (blockerId === blockedId) {
    throw new HttpError(400, 'You cannot block yourself');
  }

  const target = await findUserById(blockedId);

  if (!target) {
    throw new HttpError(404, 'User not found');
  }

  await blockUser({ blockerId, blockedId });
};

const unblockTargetUser = async ({ blockerId, blockedId }) => {
  const removed = await unblockUser({ blockerId, blockedId });

  if (!removed) {
    throw new HttpError(403, 'Only the blocker can unblock this user');
  }
};

const getBlockedUsersForUser = async (userId) => {
  return listBlockedUsers(userId);
};

module.exports = {
  assertUsersCanInteract,
  blockTargetUser,
  unblockTargetUser,
  getBlockedUsersForUser,
};
