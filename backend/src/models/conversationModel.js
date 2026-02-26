const { v4: uuidv4 } = require('uuid');
const { query, withTransaction } = require('../config/db');
const {
  upsertConversationSettings,
  deleteConversationSettings,
} = require('./conversationSettingsModel');

const buildDirectConversationKey = (firstUserId, secondUserId) =>
  [firstUserId, secondUserId].sort().join(':');

const createOrGetDirectConversation = async ({ userId, recipientId }) => {
  return withTransaction(async (client) => {
    const key = buildDirectConversationKey(userId, recipientId);
    const conversationId = uuidv4();

    const conversationResult = await client.query(
      `
        INSERT INTO conversations (id, type, unique_key, created_at, updated_at)
        VALUES ($1, 'direct', $2, NOW(), NOW())
        ON CONFLICT (unique_key)
        DO UPDATE SET updated_at = NOW()
        RETURNING id, type, created_at AS "createdAt", updated_at AS "updatedAt"
      `,
      [conversationId, key],
    );

    const conversation = conversationResult.rows[0];

    await client.query(
      `
        INSERT INTO conversation_participants (conversation_id, user_id)
        VALUES ($1, $2), ($1, $3)
        ON CONFLICT (conversation_id, user_id)
        DO UPDATE SET deleted_at = NULL
      `,
      [conversation.id, userId, recipientId],
    );

    return conversation;
  });
};

const isUserInConversation = async ({ conversationId, userId }) => {
  const result = await query(
    `
      SELECT 1
      FROM conversation_participants
      WHERE conversation_id = $1
        AND user_id = $2
      LIMIT 1
    `,
    [conversationId, userId],
  );

  return Boolean(result.rows[0]);
};

const findConversationParticipants = async (conversationId) => {
  const result = await query(
    `
      SELECT user_id AS "userId"
      FROM conversation_participants
      WHERE conversation_id = $1
    `,
    [conversationId],
  );

  return result.rows.map((row) => row.userId);
};

const listConversationsForUser = async (userId) => {
  const result = await query(
    `
      SELECT
        c.id AS "conversationId",
        c.type,
        c.created_at AS "createdAt",
        c.updated_at AS "updatedAt",
        c.last_message_at AS "lastMessageAt",
        counterpart.id AS "participantId",
        counterpart.username AS "participantUsername",
        counterpart.phone_number AS "participantPhoneNumber",
        counterpart.avatar_url AS "participantAvatarUrl",
        CASE
          WHEN block_state.blocked_by_me OR block_state.blocked_by_participant OR counterpart.show_online_status = FALSE THEN FALSE
          ELSE counterpart.is_online
        END AS "participantIsOnline",
        CASE
          WHEN block_state.blocked_by_me OR block_state.blocked_by_participant OR counterpart.show_online_status = FALSE THEN NULL
          ELSE counterpart.last_seen
        END AS "participantLastSeen",
        (block_state.blocked_by_me OR block_state.blocked_by_participant) AS "isBlocked",
        block_state.blocked_by_me AS "blockedByMe",
        block_state.blocked_by_participant AS "blockedByParticipant",
        upk.public_key_jwk AS "participantPublicKeyJwk",
        lm.id AS "lastMessageId",
        lm.type AS "lastMessageType",
        lm.body AS "lastMessageBody",
        lm.is_encrypted AS "lastMessageIsEncrypted",
        lm.media_name AS "lastMessageMediaName",
        lm.created_at AS "lastMessageCreatedAt",
        lm.sender_id AS "lastMessageSenderId",
        COALESCE(unread.unread_count, 0)::int AS "unreadCount",
        COALESCE(cws.wallpaper_url, ucs.wallpaper_url) AS "wallpaperUrl",
        COALESCE(cws.blur_intensity, ucs.blur_intensity, 0)::int AS "blurIntensity"
      FROM conversation_participants cp
      INNER JOIN conversations c ON c.id = cp.conversation_id
      INNER JOIN conversation_participants cp2
        ON cp2.conversation_id = c.id
        AND cp2.user_id <> cp.user_id
      INNER JOIN users counterpart ON counterpart.id = cp2.user_id
      LEFT JOIN user_public_keys upk ON upk.user_id = counterpart.id
      LEFT JOIN conversation_wallpaper_settings cws
        ON cws.conversation_id = c.id
      LEFT JOIN user_conversation_settings ucs
        ON ucs.user_id = cp.user_id
       AND ucs.conversation_id = c.id
      LEFT JOIN LATERAL (
        SELECT
          EXISTS(
            SELECT 1
            FROM user_blocks ub
            WHERE ub.blocker_id = cp.user_id
              AND ub.blocked_id = counterpart.id
          ) AS blocked_by_me,
          EXISTS(
            SELECT 1
            FROM user_blocks ub
            WHERE ub.blocker_id = counterpart.id
              AND ub.blocked_id = cp.user_id
          ) AS blocked_by_participant
      ) block_state ON TRUE
      LEFT JOIN LATERAL (
        SELECT
          m.id,
          m.type,
          m.body,
          m.is_encrypted,
          m.media_name,
          m.created_at,
          m.sender_id
        FROM messages m
        WHERE m.conversation_id = c.id
          AND m.deleted_for_everyone_at IS NULL
          AND (cp.deleted_at IS NULL OR m.created_at > cp.deleted_at)
        ORDER BY m.created_at DESC
        LIMIT 1
      ) lm ON TRUE
      LEFT JOIN LATERAL (
        SELECT COUNT(*) AS unread_count
        FROM messages m2
        WHERE m2.conversation_id = c.id
          AND m2.deleted_for_everyone_at IS NULL
          AND (cp.deleted_at IS NULL OR m2.created_at > cp.deleted_at)
          AND m2.recipient_id = $1
          AND m2.seen_at IS NULL
      ) unread ON TRUE
      WHERE cp.user_id = $1
      ORDER BY COALESCE(lm.created_at, c.updated_at) DESC
    `,
    [userId],
  );

  return result.rows.map((conversation) => ({
    ...conversation,
    isBlocked: Boolean(conversation.isBlocked),
    blockedByMe: Boolean(conversation.blockedByMe),
    blockedByParticipant: Boolean(conversation.blockedByParticipant),
  }));
};

const listConversationIdsForUser = async (userId) => {
  const result = await query(
    `
      SELECT conversation_id AS "conversationId"
      FROM conversation_participants
      WHERE user_id = $1
    `,
    [userId],
  );

  return result.rows.map((row) => row.conversationId);
};

const findConversationForUser = async ({ conversationId, userId }) => {
  const conversations = await listConversationsForUser(userId);
  return conversations.find((conversation) => conversation.conversationId === conversationId) || null;
};

const touchConversationActivity = async (conversationId, lastMessageAt) => {
  await query(
    `
      UPDATE conversations
      SET
        updated_at = NOW(),
        last_message_at = COALESCE($2, NOW())
      WHERE id = $1
    `,
    [conversationId, lastMessageAt],
  );

  await query(
    `
      UPDATE conversation_participants
      SET deleted_at = NULL
      WHERE conversation_id = $1
    `,
    [conversationId],
  );
};

const updateParticipantReadCursor = async ({ conversationId, userId, messageId }) => {
  await query(
    `
      UPDATE conversation_participants
      SET last_read_message_id = $3
      WHERE conversation_id = $1
        AND user_id = $2
    `,
    [conversationId, userId, messageId],
  );
};

const softDeleteConversation = async ({ conversationId, userId }) => {
  await query(
    `
      UPDATE conversation_participants
      SET
        deleted_at = NOW(),
        last_read_message_id = NULL
      WHERE conversation_id = $1
        AND user_id = $2
    `,
    [conversationId, userId],
  );
};

const softDeleteConversationForEveryone = async ({ conversationId }) => {
  await withTransaction(async (client) => {
    await client.query(
      `
        UPDATE messages
        SET deleted_for_everyone_at = NOW()
        WHERE conversation_id = $1
          AND deleted_for_everyone_at IS NULL
      `,
      [conversationId],
    );

    await client.query(
      `
        UPDATE conversation_participants
        SET
          deleted_at = NOW(),
          last_read_message_id = NULL
        WHERE conversation_id = $1
      `,
      [conversationId],
    );

    await client.query(
      `
        UPDATE conversations
        SET
          updated_at = NOW(),
          last_message_at = NULL
        WHERE id = $1
      `,
      [conversationId],
    );
  });
};

const setConversationWallpaperSettings = async ({
  conversationId,
  wallpaperUrl,
  blurIntensity,
}) => {
  return upsertConversationSettings({
    conversationId,
    wallpaperUrl,
    blurIntensity,
  });
};

const resetConversationWallpaperSettings = async ({ conversationId }) => {
  await deleteConversationSettings({ conversationId });
};

module.exports = {
  buildDirectConversationKey,
  createOrGetDirectConversation,
  isUserInConversation,
  findConversationParticipants,
  listConversationsForUser,
  touchConversationActivity,
  updateParticipantReadCursor,
  softDeleteConversation,
  softDeleteConversationForEveryone,
  setConversationWallpaperSettings,
  resetConversationWallpaperSettings,
  listConversationIdsForUser,
  findConversationForUser,
};
