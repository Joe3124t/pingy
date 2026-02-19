const CONTROL_CHAR_PATTERN = /[\u0000-\u001f\u007f]/g;

const sanitizeText = (value, maxLength = 2000) => {
  if (typeof value !== 'string') {
    return '';
  }

  return value
    .replace(/[<>]/g, '')
    .replace(CONTROL_CHAR_PATTERN, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
};

const sanitizeNestedStrings = (value) => {
  if (typeof value === 'string') {
    return sanitizeText(value, value.length);
  }

  if (Array.isArray(value)) {
    return value.map((item) => sanitizeNestedStrings(item));
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, nestedValue]) => [key, sanitizeNestedStrings(nestedValue)]),
    );
  }

  return value;
};

module.exports = {
  sanitizeText,
  sanitizeNestedStrings,
};
