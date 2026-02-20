const http2 = require('node:http2');
const jwt = require('jsonwebtoken');
const webPush = require('web-push');
const { env } = require('../config/env');
const {
  listPushSubscriptionsForUser,
  deleteAnyPushSubscriptionByEndpoint,
} = require('../models/pushSubscriptionModel');

const APNS_AUTH_TOKEN_REFRESH_MS = 50 * 60 * 1000;
const APNS_INVALID_REASONS = new Set([
  'BadDeviceToken',
  'DeviceTokenNotForTopic',
  'Unregistered',
]);

const apnsAuthTokenCache = {
  token: null,
  expiresAt: 0,
};

const isWebPushConfigured = () =>
  Boolean(env.WEB_PUSH_PUBLIC_KEY && env.WEB_PUSH_PRIVATE_KEY && env.WEB_PUSH_SUBJECT);

const isAPNsConfigured = () =>
  Boolean(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_BUNDLE_ID && env.APNS_PRIVATE_KEY);

const isPushDeliveryConfigured = () => isWebPushConfigured() || isAPNsConfigured();

if (isWebPushConfigured()) {
  webPush.setVapidDetails(
    env.WEB_PUSH_SUBJECT,
    env.WEB_PUSH_PUBLIC_KEY,
    env.WEB_PUSH_PRIVATE_KEY,
  );
}

const normalizeAPNSPrivateKey = () =>
  String(env.APNS_PRIVATE_KEY || '')
    .trim()
    .replace(/\\n/g, '\n');

const getAPNsAuthority = () =>
  env.APNS_USE_SANDBOX ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';

const getAPNsAuthToken = () => {
  const now = Date.now();

  if (apnsAuthTokenCache.token && now < apnsAuthTokenCache.expiresAt) {
    return apnsAuthTokenCache.token;
  }

  const signed = jwt.sign({}, normalizeAPNSPrivateKey(), {
    algorithm: 'ES256',
    issuer: env.APNS_TEAM_ID,
    header: {
      alg: 'ES256',
      kid: env.APNS_KEY_ID,
    },
    expiresIn: '50m',
  });

  apnsAuthTokenCache.token = signed;
  apnsAuthTokenCache.expiresAt = now + APNS_AUTH_TOKEN_REFRESH_MS;
  return signed;
};

const parseAPNSTokenFromEndpoint = (endpoint) => {
  if (!endpoint || typeof endpoint !== 'string') {
    return null;
  }

  if (!endpoint.startsWith('apns://')) {
    return null;
  }

  const token = endpoint.slice('apns://'.length).trim();
  return token || null;
};

const isAPNSEndpoint = (endpoint) => Boolean(parseAPNSTokenFromEndpoint(endpoint));

const getWebPushPublicKey = () => env.WEB_PUSH_PUBLIC_KEY || null;

const getMessagePreview = (message) => {
  if (message?.type === 'voice') {
    return 'Voice message';
  }

  if (message?.type === 'image') {
    return 'Image';
  }

  if (message?.type === 'video') {
    return 'Video';
  }

  if (message?.type === 'file') {
    return message?.mediaName ? `File: ${message.mediaName}` : 'File';
  }

  return 'New message';
};

const buildWebPushPayload = (message, badgeCount) => {
  const conversationId = String(message?.conversationId || '');
  const tagSuffix = conversationId || 'message';

  return JSON.stringify({
    type: 'message:new',
    title: message?.senderUsername || 'Pingy',
    body: getMessagePreview(message),
    conversationId: conversationId || null,
    messageId: message?.id || null,
    senderId: message?.senderId || null,
    senderUsername: message?.senderUsername || null,
    url: conversationId ? `/?conversationId=${encodeURIComponent(conversationId)}` : '/',
    tag: `pingy-conversation-${tagSuffix}`,
    badge: Number.isFinite(Number(badgeCount)) ? Number(badgeCount) : 0,
  });
};

const buildAPNsPayload = (message, badgeCount) => {
  const conversationId = String(message?.conversationId || '');
  const parsedBadge = Number.isFinite(Number(badgeCount)) ? Math.max(0, Number(badgeCount)) : 0;

  return {
    aps: {
      alert: {
        title: message?.senderUsername || 'Pingy',
        body: getMessagePreview(message),
      },
      sound: 'default',
      badge: parsedBadge,
      'thread-id': conversationId || 'pingy',
    },
    type: 'message:new',
    conversationId: conversationId || null,
    messageId: message?.id || null,
    senderId: message?.senderId || null,
    senderUsername: message?.senderUsername || null,
  };
};

const toWebPushSubscription = (subscription) => ({
  endpoint: subscription.endpoint,
  keys: {
    p256dh: subscription.p256dh,
    auth: subscription.auth,
  },
});

const shouldDeleteAPNSSubscription = ({ statusCode, reason }) => {
  if (statusCode === 410 || statusCode === 404) {
    return true;
  }

  if (statusCode === 400 && APNS_INVALID_REASONS.has(String(reason || ''))) {
    return true;
  }

  return false;
};

const sendAPNSNotification = async ({ deviceToken, payload, conversationId }) =>
  new Promise((resolve) => {
    try {
      const authToken = getAPNsAuthToken();
      const authority = getAPNsAuthority();
      const client = http2.connect(authority);
      let resolved = false;

      const finish = (value) => {
        if (resolved) {
          return;
        }
        resolved = true;
        try {
          client.close();
        } catch {
          // no-op
        }
        resolve(value);
      };

      client.on('error', (error) => {
        finish({
          ok: false,
          statusCode: 0,
          reason: error?.message || 'APNs connection failed',
        });
      });

      const request = client.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${authToken}`,
        'apns-topic': env.APNS_BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-collapse-id': conversationId || 'pingy-message',
        'content-type': 'application/json',
      });

      let responseStatus = 0;
      let responseBody = '';

      request.setEncoding('utf8');
      request.on('response', (headers) => {
        responseStatus = Number(headers[':status'] || 0);
      });

      request.on('data', (chunk) => {
        responseBody += chunk;
      });

      request.on('error', (error) => {
        finish({
          ok: false,
          statusCode: 0,
          reason: error?.message || 'APNs request failed',
        });
      });

      request.on('end', () => {
        if (responseStatus >= 200 && responseStatus < 300) {
          finish({ ok: true, statusCode: responseStatus });
          return;
        }

        let reason = null;
        if (responseBody) {
          try {
            reason = JSON.parse(responseBody)?.reason || null;
          } catch {
            reason = responseBody;
          }
        }

        finish({
          ok: false,
          statusCode: responseStatus,
          reason: reason || 'APNs rejected notification',
        });
      });

      request.end(JSON.stringify(payload));
    } catch (error) {
      resolve({
        ok: false,
        statusCode: 0,
        reason: error?.message || 'APNs setup failed',
      });
    }
  });

const sendMessagePushToUser = async ({ recipientUserId, message, badgeCount = 0 }) => {
  if (!recipientUserId || !message || !isPushDeliveryConfigured()) {
    return {
      sent: 0,
      attempted: 0,
      skipped: true,
    };
  }

  const subscriptions = await listPushSubscriptionsForUser(recipientUserId);

  if (!subscriptions.length) {
    return {
      sent: 0,
      attempted: 0,
      skipped: true,
    };
  }

  const webPayload = buildWebPushPayload(message, badgeCount);
  const apnsPayload = buildAPNsPayload(message, badgeCount);

  const sendResults = await Promise.allSettled(
    subscriptions.map(async (subscription) => {
      const apnsDeviceToken = parseAPNSTokenFromEndpoint(subscription.endpoint);

      if (apnsDeviceToken) {
        if (!isAPNsConfigured()) {
          return { ok: false, skipped: true };
        }

        const result = await sendAPNSNotification({
          deviceToken: apnsDeviceToken,
          payload: apnsPayload,
          conversationId: message?.conversationId,
        });

        if (!result.ok && shouldDeleteAPNSSubscription(result)) {
          await deleteAnyPushSubscriptionByEndpoint(subscription.endpoint);
        }

        return { ok: result.ok };
      }

      if (!isWebPushConfigured()) {
        return { ok: false, skipped: true };
      }

      try {
        await webPush.sendNotification(toWebPushSubscription(subscription), webPayload, {
          TTL: 180,
          urgency: 'high',
        });
        return { ok: true };
      } catch (error) {
        const statusCode = Number(error?.statusCode || 0);

        if (statusCode === 404 || statusCode === 410) {
          await deleteAnyPushSubscriptionByEndpoint(subscription.endpoint);
        }

        return { ok: false };
      }
    }),
  );

  const sent = sendResults.filter(
    (result) => result.status === 'fulfilled' && result.value?.ok,
  ).length;

  return {
    sent,
    attempted: subscriptions.length,
    skipped: false,
  };
};

module.exports = {
  isWebPushConfigured,
  isAPNsConfigured,
  isPushDeliveryConfigured,
  isAPNSEndpoint,
  getWebPushPublicKey,
  sendMessagePushToUser,
};
