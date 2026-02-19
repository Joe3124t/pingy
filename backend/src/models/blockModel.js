const { query } = require('../config/db');

const blockUser = async ({ blockerId, blockedId }) => {
  await query(
    `
      INSERT INTO user_blocks (blocker_id, blocked_id)
      VALUES ($1, $2)
      ON CONFLICT (blocker_id, blocked_id)
      DO NOTHING
    `,
    [blockerId, blockedId],
  );
};

const unblockUser = async ({ blockerId, blockedId }) => {
  const result = await query(
    `
      DELETE FROM user_blocks
      WHERE blocker_id = $1
        AND blocked_id = $2
    `,
    [blockerId, blockedId],
  );

  return result.rowCount > 0;
};

const isEitherUserBlocked = async ({ firstUserId, secondUserId }) => {
  const result = await query(
    `
      SELECT 1
      FROM user_blocks
      WHERE (blocker_id = $1 AND blocked_id = $2)
         OR (blocker_id = $2 AND blocked_id = $1)
      LIMIT 1
    `,
    [firstUserId, secondUserId],
  );

  return Boolean(result.rows[0]);
};

const listBlockedUsers = async (blockerId) => {
  const result = await query(
    `
      SELECT
        u.id,
        u.username,
        u.email,
        u.avatar_url AS "avatarUrl",
        ub.created_at AS "blockedAt"
      FROM user_blocks ub
      INNER JOIN users u ON u.id = ub.blocked_id
      WHERE ub.blocker_id = $1
      ORDER BY ub.created_at DESC
    `,
    [blockerId],
  );

  return result.rows;
};

const listUsersHiddenFromPresence = async (viewerId) => {
  const result = await query(
    `
      SELECT
        CASE
          WHEN blocker_id = $1 THEN blocked_id
          ELSE blocker_id
        END AS "userId"
      FROM user_blocks
      WHERE blocker_id = $1 OR blocked_id = $1
    `,
    [viewerId],
  );

  return result.rows.map((row) => row.userId);
};

module.exports = {
  blockUser,
  unblockUser,
  isEitherUserBlocked,
  listBlockedUsers,
  listUsersHiddenFromPresence,
};
