const { query, withTransaction } = require('../config/db');

const normalizeReactions = (rows) =>
  rows.map((row) => ({
    emoji: row.emoji,
    count: Number(row.count || 0),
    reactedByMe: Boolean(row.reactedByMe),
  }));

const findReactableMessageForUser = async ({ messageId, userId }) => {
  const result = await query(
    `
      SELECT
        m.id AS "messageId",
        m.conversation_id AS "conversationId",
        m.created_at AS "createdAt"
      FROM messages m
      INNER JOIN conversation_participants cp
        ON cp.conversation_id = m.conversation_id
       AND cp.user_id = $2
      WHERE m.id = $1
        AND m.deleted_for_everyone_at IS NULL
        AND (cp.deleted_at IS NULL OR m.created_at > cp.deleted_at)
      LIMIT 1
    `,
    [messageId, userId],
  );

  return result.rows[0] || null;
};

const summarizeReactions = async ({ messageId, userId, client = null }) => {
  const executor = client || { query };
  const result = await executor.query(
    `
      SELECT
        grouped.emoji,
        grouped.count,
        grouped.reacted_by_me AS "reactedByMe"
      FROM (
        SELECT
          mr.emoji,
          COUNT(*)::int AS count,
          BOOL_OR(mr.user_id = $2) AS reacted_by_me
        FROM message_reactions mr
        WHERE mr.message_id = $1
        GROUP BY mr.emoji
      ) grouped
      ORDER BY grouped.count DESC, grouped.emoji ASC
    `,
    [messageId, userId],
  );

  return normalizeReactions(result.rows);
};

const toggleMessageReaction = async ({ messageId, userId, emoji }) => {
  return withTransaction(async (client) => {
    const messageResult = await client.query(
      `
        SELECT
          m.id AS "messageId",
          m.conversation_id AS "conversationId",
          m.created_at AS "createdAt",
          peer.user_id AS "peerUserId"
        FROM messages m
        INNER JOIN conversation_participants cp
          ON cp.conversation_id = m.conversation_id
         AND cp.user_id = $2
        LEFT JOIN conversation_participants peer
          ON peer.conversation_id = m.conversation_id
         AND peer.user_id <> cp.user_id
        WHERE m.id = $1
          AND m.deleted_for_everyone_at IS NULL
          AND (cp.deleted_at IS NULL OR m.created_at > cp.deleted_at)
        LIMIT 1
      `,
      [messageId, userId],
    );

    const message = messageResult.rows[0];

    if (!message) {
      return null;
    }

    const blockCheck = await client.query(
      `
        SELECT 1
        FROM user_blocks b
        WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
           OR (b.blocker_id = $2 AND b.blocked_id = $1)
        LIMIT 1
      `,
      [userId, message.peerUserId],
    );

    if (blockCheck.rows[0]) {
      const error = new Error('You cannot interact with this user');
      error.code = 'BLOCKED_INTERACTION';
      throw error;
    }

    const existingResult = await client.query(
      `
        SELECT emoji
        FROM message_reactions
        WHERE message_id = $1
          AND user_id = $2
        LIMIT 1
      `,
      [messageId, userId],
    );

    const existing = existingResult.rows[0] || null;
    let action = 'added';

    if (existing?.emoji === emoji) {
      await client.query(
        `
          DELETE FROM message_reactions
          WHERE message_id = $1
            AND user_id = $2
        `,
        [messageId, userId],
      );
      action = 'removed';
    } else {
      await client.query(
        `
          INSERT INTO message_reactions (message_id, user_id, emoji)
          VALUES ($1, $2, $3)
          ON CONFLICT (message_id, user_id)
          DO UPDATE SET emoji = EXCLUDED.emoji, updated_at = NOW()
        `,
        [messageId, userId, emoji],
      );
      action = existing ? 'updated' : 'added';
    }

    const reactions = await summarizeReactions({
      messageId,
      userId,
      client,
    });

    return {
      messageId,
      conversationId: message.conversationId,
      reactions,
      action,
      emoji,
    };
  });
};

module.exports = {
  findReactableMessageForUser,
  summarizeReactions,
  toggleMessageReaction,
};
