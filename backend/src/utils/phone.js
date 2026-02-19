const { HttpError } = require('./httpError');

const E164_PATTERN = /^\+[1-9]\d{7,14}$/;

const normalizePhoneNumber = (rawValue) => {
  const raw = String(rawValue || '').trim();
  if (!raw) {
    throw new HttpError(400, 'Phone number is required');
  }

  const compact = raw.replace(/[\s().-]+/g, '');
  const prefixed = compact.startsWith('00') ? `+${compact.slice(2)}` : compact;
  const normalized = prefixed.startsWith('+') ? prefixed : `+${prefixed}`;

  if (!E164_PATTERN.test(normalized)) {
    throw new HttpError(400, 'Phone number must be a valid international format');
  }

  return normalized;
};

const isValidPhoneNumber = (value) => E164_PATTERN.test(String(value || ''));

module.exports = {
  E164_PATTERN,
  normalizePhoneNumber,
  isValidPhoneNumber,
};
