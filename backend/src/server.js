const http = require('node:http');
const app = require('./app');
const { env } = require('./config/env');
const { initializeDatabase, shutdownDatabase } = require('./config/db');
const { createSocketServer } = require('./sockets');

let server = null;
let io = null;
let isShuttingDown = false;

const startServer = async () => {
  await initializeDatabase();

  server = http.createServer(app);
  io = createSocketServer(server);
  app.locals.io = io;

  server.listen(env.PORT, () => {
    console.log(`Pingy backend listening on http://localhost:${env.PORT}`);
  });
};

const shutdown = async (signal) => {
  if (isShuttingDown) {
    return;
  }

  isShuttingDown = true;
  console.log(`${signal} received. Shutting down...`);

  if (io) {
    io.close();
  }

  if (server) {
    await new Promise((resolve) => {
      server.close(() => resolve());
    });
  }

  await shutdownDatabase();
  process.exit(0);
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

startServer().catch(async (error) => {
  console.error('Failed to start Pingy backend', error);
  await shutdownDatabase();
  process.exit(1);
});
