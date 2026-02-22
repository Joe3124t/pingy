const { query } = require('../config/db');

const statusSchemaState = {
  ready: false,
};

const contactHashesTableState = {
  ready: false,
};

const ensureStatusSchema = async () => {
  if (statusSchemaState.ready) {
    return;
  }

  await query(`
    CREATE TABLE IF NOT EXISTS status_stories (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      content_type VARCHAR(12) NOT NULL CHECK (content_type IN ('text', 'image', 'video')),
      text_content TEXT,
      media_url TEXT,
      background_hex VARCHAR(16),
      privacy VARCHAR(16) NOT NULL DEFAULT 'contacts' CHECK (privacy IN ('contacts', 'custom')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
      deleted_at TIMESTAMPTZ,
      CHECK (text_content IS NOT NULL OR media_url IS NOT NULL)
    )
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS status_story_viewers (
      story_id UUID NOT NULL REFERENCES status_stories(id) ON DELETE CASCADE,
      viewer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (story_id, viewer_user_id)
    )
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_status_stories_owner_created
      ON status_stories (owner_user_id, created_at DESC)
      WHERE deleted_at IS NULL
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_status_stories_expires
      ON status_stories (expires_at)
      WHERE deleted_at IS NULL
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_status_story_viewers_story
      ON status_story_viewers (story_id, viewed_at DESC)
  `);

  statusSchemaState.ready = true;
};

const ensureUserContactHashesTable = async () => {
  if (contactHashesTableState.ready) {
    return;
  }

  await query(`
    CREATE TABLE IF NOT EXISTS user_contact_hashes (
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      contact_hash VARCHAR(64) NOT NULL,
      contact_label VARCHAR(120) NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, contact_hash)
    )
  `);

  await query(`
    CREATE INDEX IF NOT EXISTS idx_user_contact_hashes_lookup
      ON user_contact_hashes (contact_hash)
  `);

  contactHashesTableState.ready = true;
};

const STORY_SELECT = `
  ss.id,
  ss.owner_user_id AS "ownerUserId",
  owner.username AS "ownerName",
  owner.avatar_url AS "ownerAvatarUrl",
  ss.content_type AS "contentType",
  ss.text_content AS "text",
  ss.media_url AS "mediaUrl",
  ss.background_hex AS "backgroundHex",
  ss.privacy,
  ss.created_at AS "createdAt",
  ss.expires_at AS "expiresAt"
`;

const normalizeViewers = (value) => {
  if (!value) {
    return [];
  }

  if (Array.isArray(value)) {
    return value;
  }

  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }

  return [];
};

const normalizeStoryRow = (row) => {
  if (!row) {
    return null;
  }

  return {
    ...row,
    viewers: normalizeViewers(row.viewers).map((viewer) => ({
      id: viewer?.id || null,
      name: viewer?.name || 'Viewer',
      viewedAt: viewer?.viewedAt || null,
    })),
  };
};

const createStatusStory = async ({
  ownerUserId,
  contentType,
  text = null,
  mediaUrl = null,
  backgroundHex = null,
  privacy = 'contacts',
}) => {
  await ensureStatusSchema();

  const result = await query(
    `
      INSERT INTO status_stories (
        owner_user_id,
        content_type,
        text_content,
        media_url,
        background_hex,
        privacy,
        expires_at
      )
      VALUES (
        $1,
        $2,
        NULLIF($3, ''),
        $4,
        NULLIF($5, ''),
        $6,
        NOW() + INTERVAL '24 hours'
      )
      RETURNING id
    `,
    [ownerUserId, contentType, text, mediaUrl, backgroundHex, privacy],
  );

  const createdId = result.rows[0]?.id;
  if (!createdId) {
    return null;
  }

  return findStatusStoryById(createdId);
};

const findStatusStoryById = async (storyId) => {
  await ensureStatusSchema();

  const result = await query(
    `
      SELECT
        ${STORY_SELECT},
        COALESCE(
          json_agg(
            json_build_object(
              'id', viewer.id,
              'name', viewer.username,
              'viewedAt', ssv.viewed_at
            )
            ORDER BY ssv.viewed_at DESC
          ) FILTER (WHERE ssv.viewer_user_id IS NOT NULL),
          '[]'::json
        ) AS viewers
      FROM status_stories ss
      INNER JOIN users owner ON owner.id = ss.owner_user_id
      LEFT JOIN status_story_viewers ssv ON ssv.story_id = ss.id
      LEFT JOIN users viewer ON viewer.id = ssv.viewer_user_id
      WHERE ss.id = $1
        AND ss.deleted_at IS NULL
      GROUP BY ss.id, owner.username, owner.avatar_url
      LIMIT 1
    `,
    [storyId],
  );

  return normalizeStoryRow(result.rows[0] || null);
};

const listVisibleStatusStories = async ({ viewerUserId }) => {
  await ensureStatusSchema();
  await ensureUserContactHashesTable();

  const result = await query(
    `
      WITH conversation_contacts AS (
        SELECT DISTINCT cp_other.user_id AS user_id
        FROM conversation_participants cp_self
        INNER JOIN conversation_participants cp_other
          ON cp_other.conversation_id = cp_self.conversation_id
         AND cp_other.user_id <> cp_self.user_id
        WHERE cp_self.user_id = $1
          AND cp_self.deleted_at IS NULL
          AND cp_other.deleted_at IS NULL
      ),
      synced_address_book_contacts AS (
        SELECT DISTINCT u.id AS user_id
        FROM user_contact_hashes uch
        INNER JOIN users u
          ON uch.contact_hash = encode(digest(COALESCE(u.phone_number, ''), 'sha256'), 'hex')
        WHERE uch.user_id = $1
          AND u.id <> $1
      ),
      contact_users AS (
        SELECT user_id FROM conversation_contacts
        UNION
        SELECT user_id FROM synced_address_book_contacts
      ),
      visible_stories AS (
        SELECT ss.*
        FROM status_stories ss
        WHERE ss.deleted_at IS NULL
          AND ss.expires_at > NOW()
          AND (
            ss.owner_user_id = $1
            OR (
              ss.owner_user_id IN (SELECT user_id FROM contact_users)
              AND ss.privacy IN ('contacts', 'custom')
            )
          )
          AND NOT EXISTS (
            SELECT 1
            FROM user_blocks ub
            WHERE (ub.blocker_id = $1 AND ub.blocked_id = ss.owner_user_id)
               OR (ub.blocker_id = ss.owner_user_id AND ub.blocked_id = $1)
          )
      )
      SELECT
        ${STORY_SELECT},
        COALESCE(
          json_agg(
            json_build_object(
              'id', viewer.id,
              'name', viewer.username,
              'viewedAt', ssv.viewed_at
            )
            ORDER BY ssv.viewed_at DESC
          ) FILTER (WHERE ssv.viewer_user_id IS NOT NULL),
          '[]'::json
        ) AS viewers
      FROM visible_stories ss
      INNER JOIN users owner ON owner.id = ss.owner_user_id
      LEFT JOIN status_story_viewers ssv ON ssv.story_id = ss.id
      LEFT JOIN users viewer ON viewer.id = ssv.viewer_user_id
      GROUP BY ss.id, owner.username, owner.avatar_url
      ORDER BY ss.created_at DESC
    `,
    [viewerUserId],
  );

  return result.rows.map(normalizeStoryRow);
};

const markStatusStoryViewed = async ({ storyId, viewerUserId }) => {
  await ensureStatusSchema();
  await ensureUserContactHashesTable();

  const result = await query(
    `
      WITH conversation_contacts AS (
        SELECT DISTINCT cp_other.user_id AS user_id
        FROM conversation_participants cp_self
        INNER JOIN conversation_participants cp_other
          ON cp_other.conversation_id = cp_self.conversation_id
         AND cp_other.user_id <> cp_self.user_id
        WHERE cp_self.user_id = $1
          AND cp_self.deleted_at IS NULL
          AND cp_other.deleted_at IS NULL
      ),
      synced_address_book_contacts AS (
        SELECT DISTINCT u.id AS user_id
        FROM user_contact_hashes uch
        INNER JOIN users u
          ON uch.contact_hash = encode(digest(COALESCE(u.phone_number, ''), 'sha256'), 'hex')
        WHERE uch.user_id = $1
          AND u.id <> $1
      ),
      contact_users AS (
        SELECT user_id FROM conversation_contacts
        UNION
        SELECT user_id FROM synced_address_book_contacts
      ),
      allowed_story AS (
        SELECT ss.id
        FROM status_stories ss
        WHERE ss.id = $2
          AND ss.deleted_at IS NULL
          AND ss.expires_at > NOW()
          AND ss.owner_user_id <> $1
          AND (
            ss.owner_user_id IN (SELECT user_id FROM contact_users)
            AND ss.privacy IN ('contacts', 'custom')
          )
          AND NOT EXISTS (
            SELECT 1
            FROM user_blocks ub
            WHERE (ub.blocker_id = $1 AND ub.blocked_id = ss.owner_user_id)
               OR (ub.blocker_id = ss.owner_user_id AND ub.blocked_id = $1)
          )
      )
      INSERT INTO status_story_viewers (
        story_id,
        viewer_user_id,
        viewed_at
      )
      SELECT
        allowed_story.id,
        $1,
        NOW()
      FROM allowed_story
      ON CONFLICT (story_id, viewer_user_id)
      DO UPDATE SET viewed_at = EXCLUDED.viewed_at
      RETURNING story_id AS "storyId"
    `,
    [viewerUserId, storyId],
  );

  return Boolean(result.rows[0]?.storyId);
};

const softDeleteStatusStory = async ({ storyId, ownerUserId }) => {
  await ensureStatusSchema();

  const result = await query(
    `
      UPDATE status_stories
      SET deleted_at = NOW()
      WHERE id = $1
        AND owner_user_id = $2
        AND deleted_at IS NULL
      RETURNING id
    `,
    [storyId, ownerUserId],
  );

  return Boolean(result.rows[0]?.id);
};

module.exports = {
  createStatusStory,
  findStatusStoryById,
  listVisibleStatusStories,
  markStatusStoryViewed,
  softDeleteStatusStory,
};
