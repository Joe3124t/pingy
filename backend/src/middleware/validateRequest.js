const { HttpError } = require('../utils/httpError');
const { sanitizeNestedStrings } = require('../utils/sanitize');

const validateRequest = (schema, location = 'body') => (req, res, next) => {
  const payload = sanitizeNestedStrings(req[location] || {});
  const parsed = schema.safeParse(payload);

  if (!parsed.success) {
    return next(new HttpError(400, 'Validation failed', parsed.error.issues));
  }

  req[location] = parsed.data;
  return next();
};

module.exports = {
  validateRequest,
};
