const { Client } = require('pg');

const SOURCE_DB = process.env.SOURCE_DB || 'pingy';
const TARGET_DB = process.env.TARGET_DB || 'pingy_utf8';
const PG_BASE = process.env.PG_BASE || 'postgres://postgres:postgres@127.0.0.1:5433';

const sourceConn = `${PG_BASE}/${SOURCE_DB}`;
const targetConn = `${PG_BASE}/${TARGET_DB}`;

const connect = async (connectionString) => {
  const client = new Client({ connectionString });
  await client.connect();
  return client;
};

const keyLower = (value) => String(value || '').trim().toLowerCase();

const loadDestUsers = async (dest) => {
  const result = await dest.query(`
    SELECT
      id,
      email,
      username
    FROM users
  `);

  const byId = new Map();
  const byEmail = new Map();
  const byUsername = new Map();

  result.rows.forEach((row) => {
    byId.set(row.id, row);
    byEmail.set(keyLower(row.email), row);
    byUsername.set(keyLower(row.username), row);
  });

  return { byId, byEmail, byUsername };
};

const loadDestConversations = async (dest) => {
  const result = await dest.query(`
    SELECT
      id,
      unique_key AS "uniqueKey"
    FROM conversations
  `);

  const byId = new Map();
  const byKey = new Map();

  result.rows.forEach((row) => {
    byId.set(row.id, row);
    byKey.set(row.uniqueKey, row);
  });

  return { byId, byKey };
};

const run = async () => {
  const source = await connect(sourceConn);
  const dest = await connect(targetConn);

  const stats = {
    usersInserted: 0,
    usersMappedByEmailOrUsername: 0,
    usersSkipped: 0,
    conversationsInserted: 0,
    conversationsMappedByKey: 0,
    participantsInserted: 0,
    participantsSkipped: 0,
    messagesInserted: 0,
    messagesSkipped: 0,
    refreshTokensInserted: 0,
    refreshTokensSkipped: 0,
  };

  const userIdMap = new Map();
  const conversationIdMap = new Map();

  try {
    await dest.query('BEGIN');

    const sourceUsers = await source.query(`
      SELECT
        id,
        username,
        email,
        password_hash AS "passwordHash",
        avatar_url AS "avatarUrl",
        is_online AS "isOnline",
        last_seen AS "lastSeen",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM users
      ORDER BY created_at ASC
    `);

    const destUsers = await loadDestUsers(dest);

    for (const user of sourceUsers.rows) {
      const existingById = destUsers.byId.get(user.id);

      if (existingById) {
        userIdMap.set(user.id, existingById.id);
        stats.usersSkipped += 1;
        continue;
      }

      const existingByEmail = destUsers.byEmail.get(keyLower(user.email));
      if (existingByEmail) {
        userIdMap.set(user.id, existingByEmail.id);
        stats.usersMappedByEmailOrUsername += 1;
        continue;
      }

      const existingByUsername = destUsers.byUsername.get(keyLower(user.username));
      if (existingByUsername) {
        userIdMap.set(user.id, existingByUsername.id);
        stats.usersMappedByEmailOrUsername += 1;
        continue;
      }

      await dest.query(
        `
          INSERT INTO users (
            id,
            username,
            email,
            password_hash,
            avatar_url,
            is_online,
            last_seen,
            created_at,
            updated_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          ON CONFLICT DO NOTHING
        `,
        [
          user.id,
          user.username,
          user.email,
          user.passwordHash,
          user.avatarUrl,
          user.isOnline,
          user.lastSeen,
          user.createdAt,
          user.updatedAt,
        ],
      );

      const inserted = await dest.query(
        `
          SELECT id, email, username
          FROM users
          WHERE id = $1
          LIMIT 1
        `,
        [user.id],
      );

      if (inserted.rows[0]) {
        const stored = inserted.rows[0];
        userIdMap.set(user.id, stored.id);
        destUsers.byId.set(stored.id, stored);
        destUsers.byEmail.set(keyLower(stored.email), stored);
        destUsers.byUsername.set(keyLower(stored.username), stored);
        stats.usersInserted += 1;
      } else {
        stats.usersSkipped += 1;
      }
    }

    const sourceConversations = await source.query(`
      SELECT
        id,
        type,
        unique_key AS "uniqueKey",
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        last_message_at AS "lastMessageAt"
      FROM conversations
      ORDER BY created_at ASC
    `);

    const destConversations = await loadDestConversations(dest);

    for (const conversation of sourceConversations.rows) {
      const existingById = destConversations.byId.get(conversation.id);
      if (existingById) {
        conversationIdMap.set(conversation.id, existingById.id);
        continue;
      }

      const existingByKey = destConversations.byKey.get(conversation.uniqueKey);
      if (existingByKey) {
        conversationIdMap.set(conversation.id, existingByKey.id);
        stats.conversationsMappedByKey += 1;
        continue;
      }

      await dest.query(
        `
          INSERT INTO conversations (
            id,
            type,
            unique_key,
            created_at,
            updated_at,
            last_message_at
          )
          VALUES ($1, $2, $3, $4, $5, $6)
          ON CONFLICT DO NOTHING
        `,
        [
          conversation.id,
          conversation.type,
          conversation.uniqueKey,
          conversation.createdAt,
          conversation.updatedAt,
          conversation.lastMessageAt,
        ],
      );

      const inserted = await dest.query(
        `
          SELECT
            id,
            unique_key AS "uniqueKey"
          FROM conversations
          WHERE id = $1
             OR unique_key = $2
          ORDER BY (id = $1) DESC
          LIMIT 1
        `,
        [conversation.id, conversation.uniqueKey],
      );

      if (inserted.rows[0]) {
        const stored = inserted.rows[0];
        conversationIdMap.set(conversation.id, stored.id);
        destConversations.byId.set(stored.id, stored);
        destConversations.byKey.set(stored.uniqueKey, stored);
        if (stored.id === conversation.id) {
          stats.conversationsInserted += 1;
        } else {
          stats.conversationsMappedByKey += 1;
        }
      }
    }

    const sourceParticipants = await source.query(`
      SELECT
        conversation_id AS "conversationId",
        user_id AS "userId",
        joined_at AS "joinedAt",
        last_read_message_id AS "lastReadMessageId"
      FROM conversation_participants
    `);

    for (const participant of sourceParticipants.rows) {
      const mappedConversationId = conversationIdMap.get(participant.conversationId);
      const mappedUserId = userIdMap.get(participant.userId);

      if (!mappedConversationId || !mappedUserId) {
        stats.participantsSkipped += 1;
        continue;
      }

      const result = await dest.query(
        `
          INSERT INTO conversation_participants (
            conversation_id,
            user_id,
            joined_at,
            last_read_message_id
          )
          VALUES ($1, $2, $3, $4)
          ON CONFLICT DO NOTHING
        `,
        [
          mappedConversationId,
          mappedUserId,
          participant.joinedAt,
          participant.lastReadMessageId,
        ],
      );

      if (result.rowCount > 0) {
        stats.participantsInserted += 1;
      } else {
        stats.participantsSkipped += 1;
      }
    }

    const sourceMessages = await source.query(`
      SELECT
        id,
        conversation_id AS "conversationId",
        sender_id AS "senderId",
        recipient_id AS "recipientId",
        type,
        body,
        media_url AS "mediaUrl",
        media_name AS "mediaName",
        media_mime AS "mediaMime",
        media_size AS "mediaSize",
        voice_duration_ms AS "voiceDurationMs",
        client_id AS "clientId",
        delivered_at AS "deliveredAt",
        seen_at AS "seenAt",
        created_at AS "createdAt"
      FROM messages
      ORDER BY created_at ASC
    `);

    for (const message of sourceMessages.rows) {
      const mappedConversationId = conversationIdMap.get(message.conversationId);
      const mappedSenderId = userIdMap.get(message.senderId);
      const mappedRecipientId = userIdMap.get(message.recipientId);

      if (!mappedConversationId || !mappedSenderId || !mappedRecipientId) {
        stats.messagesSkipped += 1;
        continue;
      }

      const result = await dest.query(
        `
          INSERT INTO messages (
            id,
            conversation_id,
            sender_id,
            recipient_id,
            type,
            body,
            media_url,
            media_name,
            media_mime,
            media_size,
            voice_duration_ms,
            client_id,
            delivered_at,
            seen_at,
            created_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
          ON CONFLICT DO NOTHING
        `,
        [
          message.id,
          mappedConversationId,
          mappedSenderId,
          mappedRecipientId,
          message.type,
          message.body,
          message.mediaUrl,
          message.mediaName,
          message.mediaMime,
          message.mediaSize,
          message.voiceDurationMs,
          message.clientId,
          message.deliveredAt,
          message.seenAt,
          message.createdAt,
        ],
      );

      if (result.rowCount > 0) {
        stats.messagesInserted += 1;
      } else {
        stats.messagesSkipped += 1;
      }
    }

    const sourceRefreshTokens = await source.query(`
      SELECT
        id,
        user_id AS "userId",
        token_hash AS "tokenHash",
        expires_at AS "expiresAt",
        revoked_at AS "revokedAt",
        replaced_by_hash AS "replacedByHash",
        created_at AS "createdAt"
      FROM refresh_tokens
      ORDER BY created_at ASC
    `);

    for (const token of sourceRefreshTokens.rows) {
      const mappedUserId = userIdMap.get(token.userId);

      if (!mappedUserId) {
        stats.refreshTokensSkipped += 1;
        continue;
      }

      const result = await dest.query(
        `
          INSERT INTO refresh_tokens (
            id,
            user_id,
            token_hash,
            expires_at,
            revoked_at,
            replaced_by_hash,
            created_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          ON CONFLICT DO NOTHING
        `,
        [
          token.id,
          mappedUserId,
          token.tokenHash,
          token.expiresAt,
          token.revokedAt,
          token.replacedByHash,
          token.createdAt,
        ],
      );

      if (result.rowCount > 0) {
        stats.refreshTokensInserted += 1;
      } else {
        stats.refreshTokensSkipped += 1;
      }
    }

    await dest.query('COMMIT');
    console.log('Migration completed successfully');
    console.log(JSON.stringify(stats, null, 2));
  } catch (error) {
    await dest.query('ROLLBACK');
    console.error('Migration failed');
    console.error(error);
    process.exitCode = 1;
  } finally {
    await source.end();
    await dest.end();
  }
};

run();
