const webPush = require('web-push');
const { env } = require('../config/env');
const {
  listPushSubscriptionsForUser,
  deleteAnyPushSubscriptionByEndpoint,
} = require('../models/pushSubscriptionModel');

const isWebPushConfigured = () =>
  Boolean(env.WEB_PUSH_PUBLIC_KEY && env.WEB_PUSH_PRIVATE_KEY && env.WEB_PUSH_SUBJECT);

if (isWebPushConfigured()) {
  webPush.setVapidDetails(
    env.WEB_PUSH_SUBJECT,
    env.WEB_PUSH_PUBLIC_KEY,
    env.WEB_PUSH_PRIVATE_KEY,
  );
}

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

const buildPushPayload = (message) => {
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
  });
};

const toWebPushSubscription = (subscription) => ({
  endpoint: subscription.endpoint,
  keys: {
    p256dh: subscription.p256dh,
    auth: subscription.auth,
  },
});

const sendMessagePushToUser = async ({ recipientUserId, message }) => {
  if (!isWebPushConfigured() || !recipientUserId || !message) {
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

  const payload = buildPushPayload(message);
  const sendResults = await Promise.allSettled(
    subscriptions.map(async (subscription) => {
      try {
        await webPush.sendNotification(toWebPushSubscription(subscription), payload, {
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
  getWebPushPublicKey,
  sendMessagePushToUser,
};
