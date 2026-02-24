const { v4: uuidv4 } = require('uuid');
const { query } = require('../config/db');

const MESSAGE_SELECT = `
  m.id,
  m.conversation_id AS "conversationId",
  m.sender_id AS "senderId",
  sender.username AS "senderUsername",
  sender.avatar_url AS "senderAvatarUrl",
  m.recipient_id AS "recipientId",
  m.reply_to_message_id AS "replyToMessageId",
  rm.sender_id AS "replyToSenderId",
  reply_sender.username AS "replyToSenderUsername",
  rm.type AS "replyToType",
  rm.body AS "replyToBody",
  rm.is_encrypted AS "replyToIsEncrypted",
  rm.media_name AS "replyToMediaName",
  rm.created_at AS "replyToCreatedAt",
  m.type,
  m.body,
  m.is_encrypted AS "isEncrypted",
  m.media_url AS "mediaUrl",
  m.media_name AS "mediaName",
  m.media_mime AS "mediaMime",
  m.media_size::int AS "mediaSize",
  m.voice_duration_ms::int AS "voiceDurationMs",
  m.client_id AS "clientId",
  m.created_at AS "createdAt",
  m.delivered_at AS "deliveredAt",
  m.seen_at AS "seenAt"
`;

const normalizeMessageRow = (row) => {
  if (!row) {
    return null;
  }

  const mediaSizeRaw = row.mediaSize;
  const voiceDurationRaw = row.voiceDurationMs;
  const mediaSize = mediaSizeRaw === null || mediaSizeRaw === undefined ? null : Number(mediaSizeRaw);
  const voiceDurationMs =
    voiceDurationRaw === null || voiceDurationRaw === undefined ? null : Number(voiceDurationRaw);

  let reactions = row.reactions;

  if (!Array.isArray(reactions)) {
    if (typeof reactions === 'string') {
      try {
        reactions = JSON.parse(reactions);
      } catch {
        reactions = [];
      }
    } else {
      reactions = [];
    }
  }

  return {
    ...row,
    mediaSize: Number.isFinite(mediaSize) ? mediaSize : null,
    voiceDurationMs: Number.isFinite(voiceDurationMs) ? voiceDurationMs : null,
    replyTo: row.replyToMessageId
      ? {
          id: row.replyToMessageId,
          senderId: row.replyToSenderId,
          senderUsername: row.replyToSenderUsername,
          type: row.replyToType,
          body: row.replyToBody,
          isEncrypted: Boolean(row.replyToIsEncrypted),
          mediaName: row.replyToMediaName,
          createdAt: row.replyToCreatedAt,
        }
      : null,
    reactions: reactions.map((entry) => ({
      emoji: entry?.emoji,
      count: Number(entry?.count || 0),
      reactedByMe: Boolean(entry?.reactedByMe),
    })),
  };
};

const findMessageById = async (messageId) => {
  const result = await query(
    `
      SELECT ${MESSAGE_SELECT}
      FROM messages m
      INNER JOIN users sender ON sender.id = m.sender_id
      LEFT JOIN messages rm
        ON rm.id = m.reply_to_message_id
       AND rm.deleted_for_everyone_at IS NULL
      LEFT JOIN users reply_sender ON reply_sender.id = rm.sender_id
      WHERE m.id = $1
        AND m.deleted_for_everyone_at IS NULL
      LIMIT 1
    `,
    [messageId],
  );

  return normalizeMessageRow(result.rows[0] || null);
};

const findMessageByClientId = async ({ conversationId, senderId, clientId }) => {
  if (!clientId) {
    return null;
  }

  const result = await query(
    `
      SELECT ${MESSAGE_SELECT}
      FROM messages m
      INNER JOIN users sender ON sender.id = m.sender_id
      LEFT JOIN messages rm
        ON rm.id = m.reply_to_message_id
       AND rm.deleted_for_everyone_at IS NULL
      LEFT JOIN users reply_sender ON reply_sender.id = rm.sender_id
      WHERE m.conversation_id = $1
        AND m.sender_id = $2
        AND m.client_id = $3
        AND m.deleted_for_everyone_at IS NULL
      LIMIT 1
    `,
    [conversationId, senderId, clientId],
  );

  return normalizeMessageRow(result.rows[0] || null);
};

const createMessage = async ({
  conversationId,
  senderId,
  recipientId,
  replyToMessageId = null,
  type,
  body = null,
  isEncrypted = false,
  mediaUrl = null,
  mediaName = null,
  mediaMime = null,
  mediaSize = null,
  voiceDurationMs = null,
  clientId = null,
}) => {
  const messageId = uuidv4();

  await query(
    `
      INSERT INTO messages (
        id,
        conversation_id,
        sender_id,
        recipient_id,
        reply_to_message_id,
        type,
        body,
        is_encrypted,
        media_url,
        media_name,
        media_mime,
        media_size,
        voice_duration_ms,
        client_id,
        created_at
      )
      VALUES (
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        NULLIF($7, ''),
        $8,
        $9,
        $10,
        $11,
        $12,
        $13,
        $14,
        NOW()
      )
    `,
    [
      messageId,
      conversationId,
      senderId,
      recipientId,
      replyToMessageId,
      type,
      body,
      isEncrypted,
      mediaUrl,
      mediaName,
      mediaMime,
      mediaSize,
      voiceDurationMs,
      clientId,
    ],
  );

  const message = await findMessageById(messageId);

  if (!message) {
    return null;
  }

  return {
    ...message,
    reactions: Array.isArray(message?.reactions) ? message.reactions : [],
  };
};

const listMessages = async ({
  userId,
  conversationId,
  limit = 40,
  before = null,
  after = null,
}) => {
  const result = await query(
    `
      SELECT *
      FROM (
        SELECT
          ${MESSAGE_SELECT},
          COALESCE(reaction_summary.reactions, '[]'::json) AS reactions
        FROM messages m
        INNER JOIN users sender ON sender.id = m.sender_id
        LEFT JOIN messages rm
          ON rm.id = m.reply_to_message_id
         AND rm.deleted_for_everyone_at IS NULL
        LEFT JOIN users reply_sender ON reply_sender.id = rm.sender_id
        INNER JOIN conversation_participants cp
          ON cp.conversation_id = m.conversation_id
         AND cp.user_id = $1
        LEFT JOIN LATERAL (
          SELECT
            COALESCE(
              json_agg(
                json_build_object(
                  'emoji',
                  grouped.emoji,
                  'count',
                  grouped.count,
                  'reactedByMe',
                  grouped.reacted_by_me
                )
                ORDER BY grouped.count DESC, grouped.emoji ASC
              ),
              '[]'::json
            ) AS reactions
          FROM (
            SELECT
              mr.emoji,
              COUNT(*)::int AS count,
              BOOL_OR(mr.user_id = $1) AS reacted_by_me
            FROM message_reactions mr
            WHERE mr.message_id = m.id
            GROUP BY mr.emoji
          ) grouped
        ) reaction_summary ON TRUE
        WHERE m.conversation_id = $2
          AND m.deleted_for_everyone_at IS NULL
          AND (cp.deleted_at IS NULL OR m.created_at > cp.deleted_at)
          AND ($3::timestamptz IS NULL OR m.created_at < $3)
          AND ($4::timestamptz IS NULL OR m.created_at >= $4)
        ORDER BY m.created_at DESC
        LIMIT $5
      ) recent
      ORDER BY recent."createdAt" ASC
    `,
    [userId, conversationId, before, after, limit],
  );

  return result.rows.map(normalizeMessageRow);
};

const markMessagesDelivered = async ({ recipientId, messageIds = null, conversationId = null }) => {
  const useMessageIds = Array.isArray(messageIds) && messageIds.length > 0;

  const result = await query(
    `
      UPDATE messages
      SET delivered_at = NOW()
      WHERE recipient_id = $1
        AND deleted_for_everyone_at IS NULL
        AND delivered_at IS NULL
        AND ($2::uuid[] IS NULL OR id = ANY($2::uuid[]))
        AND ($3::uuid IS NULL OR conversation_id = $3)
      RETURNING
        id,
        conversation_id AS "conversationId",
        sender_id AS "senderId",
        delivered_at AS "deliveredAt"
    `,
    [recipientId, useMessageIds ? messageIds : null, conversationId],
  );

  return result.rows;
};

const markMessagesSeen = async ({ recipientId, conversationId, messageIds = null }) => {
  const useMessageIds = Array.isArray(messageIds) && messageIds.length > 0;

  const result = await query(
    `
      UPDATE messages
      SET
        seen_at = NOW(),
        delivered_at = COALESCE(delivered_at, NOW())
      WHERE recipient_id = $1
        AND conversation_id = $2
        AND deleted_for_everyone_at IS NULL
        AND seen_at IS NULL
        AND ($3::uuid[] IS NULL OR id = ANY($3::uuid[]))
      RETURNING
        id,
        conversation_id AS "conversationId",
        sender_id AS "senderId",
        seen_at AS "seenAt",
        delivered_at AS "deliveredAt"
    `,
    [recipientId, conversationId, useMessageIds ? messageIds : null],
  );

  return result.rows;
};

const countUnreadMessagesForUser = async (recipientId) => {
  const result = await query(
    `
      SELECT COUNT(*)::int AS "unreadCount"
      FROM messages
      WHERE recipient_id = $1
        AND deleted_for_everyone_at IS NULL
        AND seen_at IS NULL
    `,
    [recipientId],
  );

  return Number(result.rows[0]?.unreadCount || 0);
};

module.exports = {
  findMessageById,
  findMessageByClientId,
  createMessage,
  listMessages,
  markMessagesDelivered,
  markMessagesSeen,
  countUnreadMessagesForUser,
};
