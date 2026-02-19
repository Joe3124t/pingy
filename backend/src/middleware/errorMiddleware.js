const { ZodError } = require('zod');
const multer = require('multer');
const { HttpError } = require('../utils/httpError');

const notFoundMiddleware = (req, res) => {
  res.status(404).json({
    message: 'Route not found',
  });
};

const errorMiddleware = (error, req, res, next) => {
  if (res.headersSent) {
    return next(error);
  }

  if (error instanceof ZodError) {
    return res.status(400).json({
      message: 'Validation failed',
      details: error.issues,
    });
  }

  if (error instanceof multer.MulterError) {
    const statusCode = error.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
    return res.status(statusCode).json({
      message: error.code === 'LIMIT_FILE_SIZE' ? 'File is too large' : error.message,
    });
  }

  if (error instanceof HttpError) {
    return res.status(error.statusCode).json({
      message: error.message,
      details: error.details,
    });
  }

  console.error(error);

  return res.status(500).json({
    message: 'Unexpected server issue. Please try again shortly.',
    code: 'UNEXPECTED_SERVER_ERROR',
  });
};

module.exports = {
  notFoundMiddleware,
  errorMiddleware,
};
