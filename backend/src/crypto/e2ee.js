const { z } = require('zod');

const base64UrlPattern = /^[A-Za-z0-9_-]+$/;
const base64Pattern = /^[A-Za-z0-9+/=]+$/;

const publicKeyJwkSchema = z.object({
  kty: z.enum(['EC', 'OKP']),
  crv: z.enum(['P-256', 'X25519']),
  x: z.string().min(20).max(200).regex(base64UrlPattern),
  y: z.string().min(20).max(200).regex(base64UrlPattern).optional(),
  ext: z.boolean().optional(),
  key_ops: z.array(z.string()).optional(),
  identityPublicKey: z
    .object({
      kty: z.literal('OKP'),
      crv: z.literal('Ed25519'),
      x: z.string().min(20).max(200).regex(base64UrlPattern),
    })
    .optional(),
}).superRefine((value, context) => {
  if (value.kty === 'EC' && value.crv !== 'P-256') {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'EC keys must use P-256 curve',
      path: ['crv'],
    });
  }

  if (value.kty === 'EC' && !value.y) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'EC keys require y coordinate',
      path: ['y'],
    });
  }

  if (value.kty === 'OKP' && value.crv !== 'X25519') {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'OKP keys must use X25519 for key agreement',
      path: ['crv'],
    });
  }
});

const encryptedPayloadSchema = z.object({
  v: z.literal(1),
  alg: z.literal('AES-256-GCM'),
  iv: z.string().min(8).max(64).regex(base64Pattern),
  ciphertext: z.string().min(16).regex(base64Pattern),
});

const assertPublicKeyJwk = (value) => publicKeyJwkSchema.parse(value);
const assertEncryptedPayload = (value) => encryptedPayloadSchema.parse(value);

module.exports = {
  publicKeyJwkSchema,
  encryptedPayloadSchema,
  assertPublicKeyJwk,
  assertEncryptedPayload,
};
