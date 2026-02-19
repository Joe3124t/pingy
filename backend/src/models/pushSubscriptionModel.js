const { query } = require('../config/db');

const PUSH_SUBSCRIPTION_COLUMNS = `
  id,
  user_id AS "userId",
  endpoint,
  p256dh,
  auth,
  user_agent AS "userAgent",
  created_at AS "createdAt",
  updated_at AS "updatedAt"
`;

const upsertUserPushSubscription = async ({
  userId,
  endpoint,
  p256dh,
  auth,
  userAgent = null,
}) => {
  const result = await query(
    `
      INSERT INTO user_push_subscriptions (
        user_id,
        endpoint,
        p256dh,
        auth,
        user_agent
      )
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (user_id, endpoint)
      DO UPDATE SET
        p256dh = EXCLUDED.p256dh,
        auth = EXCLUDED.auth,
        user_agent = EXCLUDED.user_agent,
        updated_at = NOW()
      RETURNING ${PUSH_SUBSCRIPTION_COLUMNS}
    `,
    [userId, endpoint, p256dh, auth, userAgent],
  );

  return result.rows[0] || null;
};

const listPushSubscriptionsForUser = async (userId) => {
  const result = await query(
    `
      SELECT ${PUSH_SUBSCRIPTION_COLUMNS}
      FROM user_push_subscriptions
      WHERE user_id = $1
      ORDER BY updated_at DESC
    `,
    [userId],
  );

  return result.rows;
};

const deleteUserPushSubscriptionByEndpoint = async ({ userId, endpoint }) => {
  const result = await query(
    `
      DELETE FROM user_push_subscriptions
      WHERE user_id = $1
        AND endpoint = $2
      RETURNING id
    `,
    [userId, endpoint],
  );

  return Boolean(result.rows[0]);
};

const deleteAnyPushSubscriptionByEndpoint = async (endpoint) => {
  const result = await query(
    `
      DELETE FROM user_push_subscriptions
      WHERE endpoint = $1
      RETURNING id
    `,
    [endpoint],
  );

  return Boolean(result.rows[0]);
};

module.exports = {
  upsertUserPushSubscription,
  listPushSubscriptionsForUser,
  deleteUserPushSubscriptionByEndpoint,
  deleteAnyPushSubscriptionByEndpoint,
};
