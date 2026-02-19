const path = require('node:path');
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const { env, allowedOrigins } = require('./config/env');
const authRoutes = require('./routes/authRoutes');
const conversationRoutes = require('./routes/conversationRoutes');
const messageRoutes = require('./routes/messageRoutes');
const userRoutes = require('./routes/userRoutes');
const cryptoRoutes = require('./routes/cryptoRoutes');
const mediaRoutes = require('./routes/mediaRoutes');
const { authMiddleware } = require('./middleware/authMiddleware');
const { apiRateLimiter, authRateLimiter } = require('./middleware/rateLimiter');
const { signedMediaAccessMiddleware } = require('./middleware/mediaAccessMiddleware');
const { notFoundMiddleware, errorMiddleware } = require('./middleware/errorMiddleware');

const app = express();

app.disable('x-powered-by');
app.set('trust proxy', 1);

app.use(
  helmet({
    crossOriginResourcePolicy: false,
  }),
);

app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
        callback(null, true);
        return;
      }

      callback(new Error('CORS origin not allowed'));
    },
    credentials: true,
  }),
);

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));
app.use(cookieParser());
app.use('/uploads', signedMediaAccessMiddleware, express.static(path.resolve(process.cwd(), 'uploads')));

app.get('/api/health', (req, res) => {
  res.status(200).json({
    service: 'pingy-api',
    status: 'ok',
    environment: env.NODE_ENV,
    timestamp: new Date().toISOString(),
  });
});

app.use('/api/auth', authRateLimiter, authRoutes);
app.use('/api/media', mediaRoutes);
app.use('/api/conversations', apiRateLimiter, authMiddleware, conversationRoutes);
app.use('/api/messages', apiRateLimiter, authMiddleware, messageRoutes);
app.use('/api/users', apiRateLimiter, authMiddleware, userRoutes);
app.use('/api/crypto', apiRateLimiter, authMiddleware, cryptoRoutes);

app.use(notFoundMiddleware);
app.use(errorMiddleware);

module.exports = app;
