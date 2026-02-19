const rateLimit = require('express-rate-limit');
const { env } = require('../config/env');

const jsonRateLimitHandler = (req, res) => {
  res.status(429).json({
    message: 'Too many requests, please try again shortly.',
  });
};

const apiRateLimiter = rateLimit({
  windowMs: env.API_RATE_LIMIT_WINDOW_MS,
  max: env.API_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  handler: jsonRateLimitHandler,
});

const authRateLimiter = rateLimit({
  windowMs: env.API_RATE_LIMIT_WINDOW_MS,
  max: env.AUTH_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  handler: jsonRateLimitHandler,
});

module.exports = {
  apiRateLimiter,
  authRateLimiter,
};
