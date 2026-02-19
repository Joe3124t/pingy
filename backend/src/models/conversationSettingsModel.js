const { query } = require('../config/db');

const upsertConversationSettings = async ({
  conversationId,
  wallpaperUrl = null,
  blurIntensity = 0,
}) => {
  const result = await query(
    `
      INSERT INTO conversation_wallpaper_settings (
        conversation_id,
        wallpaper_url,
        blur_intensity,
        created_at,
        updated_at
      )
      VALUES ($1, $2, $3, NOW(), NOW())
      ON CONFLICT (conversation_id)
      DO UPDATE SET
        wallpaper_url = EXCLUDED.wallpaper_url,
        blur_intensity = EXCLUDED.blur_intensity,
        updated_at = NOW()
      RETURNING
        conversation_id AS "conversationId",
        wallpaper_url AS "wallpaperUrl",
        blur_intensity AS "blurIntensity",
        updated_at AS "updatedAt"
    `,
    [conversationId, wallpaperUrl, blurIntensity],
  );

  return result.rows[0] || null;
};

const deleteConversationSettings = async ({ conversationId }) => {
  await query(
    `
      DELETE FROM conversation_wallpaper_settings
      WHERE conversation_id = $1
    `,
    [conversationId],
  );
};

module.exports = {
  upsertConversationSettings,
  deleteConversationSettings,
};
