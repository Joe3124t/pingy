const { query } = require('../config/db');

const USER_PUBLIC_COLUMNS = `
  id,
  username,
  email,
  avatar_url AS "avatarUrl",
  bio,
  is_online AS "isOnline",
  show_online_status AS "showOnlineStatus",
  read_receipts_enabled AS "readReceiptsEnabled",
  theme_mode AS "themeMode",
  default_wallpaper_url AS "defaultWallpaperUrl",
  last_seen AS "lastSeen",
  created_at AS "createdAt"
`;

const createUser = async ({ id, username, email, passwordHash, avatarUrl = null, bio = '' }) => {
  const result = await query(
    `
      INSERT INTO users (id, username, email, password_hash, avatar_url, bio)
      VALUES ($1, $2, LOWER($3), $4, $5, $6)
      RETURNING ${USER_PUBLIC_COLUMNS}
    `,
    [id, username, email, passwordHash, avatarUrl, bio],
  );

  return result.rows[0];
};

const findUserById = async (userId) => {
  const result = await query(
    `
      SELECT ${USER_PUBLIC_COLUMNS}
      FROM users
      WHERE id = $1
      LIMIT 1
    `,
    [userId],
  );

  return result.rows[0] || null;
};

const findUserByEmailWithPassword = async (email) => {
  const result = await query(
    `
      SELECT
        ${USER_PUBLIC_COLUMNS},
        password_hash AS "passwordHash"
      FROM users
      WHERE email = LOWER($1)
      LIMIT 1
    `,
    [email],
  );

  return result.rows[0] || null;
};

const searchUsers = async ({ currentUserId, search, limit = 15 }) => {
  const wildcard = `%${search}%`;

  const result = await query(
    `
      SELECT ${USER_PUBLIC_COLUMNS}
      FROM users
      WHERE id <> $1
        AND NOT EXISTS (
          SELECT 1
          FROM user_blocks b
          WHERE (b.blocker_id = $1 AND b.blocked_id = users.id)
             OR (b.blocker_id = users.id AND b.blocked_id = $1)
        )
        AND (
          username ILIKE $2
          OR email ILIKE $2
        )
      ORDER BY is_online DESC, username ASC
      LIMIT $3
    `,
    [currentUserId, wildcard, limit],
  );

  return result.rows;
};

const setUserOnlineStatus = async ({ userId, isOnline }) => {
  const result = await query(
    `
      UPDATE users
      SET
        is_online = $2,
        last_seen = CASE WHEN $2 = FALSE THEN NOW() ELSE last_seen END,
        updated_at = NOW()
      WHERE id = $1
      RETURNING ${USER_PUBLIC_COLUMNS}
    `,
    [userId, isOnline],
  );

  return result.rows[0] || null;
};

const updateUserProfile = async ({ userId, username, bio }) => {
  const result = await query(
    `
      UPDATE users
      SET
        username = COALESCE($2, username),
        bio = COALESCE($3, bio),
        updated_at = NOW()
      WHERE id = $1
      RETURNING ${USER_PUBLIC_COLUMNS}
    `,
    [userId, username, bio],
  );

  return result.rows[0] || null;
};

const setUserAvatar = async ({ userId, avatarUrl }) => {
  const result = await query(
    `
      UPDATE users
      SET
        avatar_url = $2,
        updated_at = NOW()
      WHERE id = $1
      RETURNING ${USER_PUBLIC_COLUMNS}
    `,
    [userId, avatarUrl],
  );

  return result.rows[0] || null;
};

const updateUserPrivacySettings = async ({ userId, showOnlineStatus, readReceiptsEnabled }) => {
  const result = await query(
    `
      UPDATE users
      SET
        show_online_status = COALESCE($2, show_online_status),
        read_receipts_enabled = COALESCE($3, read_receipts_enabled),
        updated_at = NOW()
      WHERE id = $1
      RETURNING ${USER_PUBLIC_COLUMNS}
    `,
    [userId, showOnlineStatus, readReceiptsEnabled],
  );

  return result.rows[0] || null;
};

const updateUserChatSettings = async ({
  userId,
  themeMode,
  defaultWallpaperUrl,
  hasDefaultWallpaperUrl = false,
}) => {
  const result = await query(
    `
      UPDATE users
      SET
        theme_mode = COALESCE($2, theme_mode),
        default_wallpaper_url = CASE
          WHEN $4::boolean THEN $3
          ELSE default_wallpaper_url
        END,
        updated_at = NOW()
      WHERE id = $1
      RETURNING ${USER_PUBLIC_COLUMNS}
    `,
    [userId, themeMode, defaultWallpaperUrl, hasDefaultWallpaperUrl],
  );

  return result.rows[0] || null;
};

const updateUserPasswordHash = async ({ userId, passwordHash }) => {
  const result = await query(
    `
      UPDATE users
      SET
        password_hash = $2,
        updated_at = NOW()
      WHERE id = $1
      RETURNING ${USER_PUBLIC_COLUMNS}
    `,
    [userId, passwordHash],
  );

  return result.rows[0] || null;
};

const deleteUserById = async (userId) => {
  const result = await query(
    `
      DELETE FROM users
      WHERE id = $1
      RETURNING id
    `,
    [userId],
  );

  return Boolean(result.rows[0]);
};

const isUsernameAvailable = async ({ username, excludeUserId = null }) => {
  const result = await query(
    `
      SELECT 1
      FROM users
      WHERE LOWER(username) = LOWER($1)
        AND ($2::uuid IS NULL OR id <> $2::uuid)
      LIMIT 1
    `,
    [username, excludeUserId],
  );

  return !result.rows[0];
};

const filterVisiblePresenceUserIds = async ({ viewerUserId, candidateUserIds = [] }) => {
  if (!Array.isArray(candidateUserIds) || candidateUserIds.length === 0) {
    return [];
  }

  const result = await query(
    `
      SELECT u.id
      FROM users u
      WHERE u.id = ANY($2::uuid[])
        AND (u.id = $1 OR u.show_online_status = TRUE)
        AND (
          u.id = $1
          OR NOT EXISTS (
            SELECT 1
            FROM user_blocks b
            WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
               OR (b.blocker_id = u.id AND b.blocked_id = $1)
          )
        )
    `,
    [viewerUserId, candidateUserIds],
  );

  return result.rows.map((row) => row.id);
};

module.exports = {
  USER_PUBLIC_COLUMNS,
  createUser,
  findUserById,
  findUserByEmailWithPassword,
  searchUsers,
  setUserOnlineStatus,
  updateUserProfile,
  setUserAvatar,
  updateUserPrivacySettings,
  updateUserChatSettings,
  updateUserPasswordHash,
  deleteUserById,
  isUsernameAvailable,
  filterVisiblePresenceUserIds,
};
