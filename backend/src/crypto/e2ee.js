const { z } = require('zod');

const base64UrlPattern = /^[A-Za-z0-9_-]+$/;
const base64Pattern = /^[A-Za-z0-9+/=]+$/;

const publicKeyJwkSchema = z.object({
  kty: z.literal('EC'),
  crv: z.literal('P-256'),
  x: z.string().min(20).max(200).regex(base64UrlPattern),
  y: z.string().min(20).max(200).regex(base64UrlPattern),
  ext: z.boolean().optional(),
  key_ops: z.array(z.string()).optional(),
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
