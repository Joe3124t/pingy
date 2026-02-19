/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');
const { initializeDatabase, query, shutdownDatabase } = require('../src/config/db');

const REQUIRED_CONFIRMATION = 'RESET_V2';

const run = async () => {
  const confirmation = String(process.env.PINGY_RESET_CONFIRM || '').trim();

  if (confirmation !== REQUIRED_CONFIRMATION) {
    throw new Error(
      `Refusing to reset database. Set PINGY_RESET_CONFIRM=${REQUIRED_CONFIRMATION} and run again.`,
    );
  }

  await initializeDatabase();

  await query(
    `
      TRUNCATE TABLE
        user_push_subscriptions,
        message_reactions,
        messages,
        conversation_participants,
        conversations,
        user_blocks,
        user_public_keys,
        conversation_wallpaper_settings,
        user_conversation_settings,
        phone_otp_codes,
        password_reset_codes,
        refresh_tokens,
        users
      RESTART IDENTITY CASCADE;
    `,
  );

  const schemaPath = path.resolve(process.cwd(), 'db', 'schema.sql');
  const schemaSql = fs.readFileSync(schemaPath, 'utf8');
  await query(schemaSql);

  console.log('Pingy v2 hard reset completed: users, keys, chats, sessions, OTP codes cleared.');
};

run()
  .catch((error) => {
    console.error('reset-v2 failed:', error.message || error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await shutdownDatabase();
  });
