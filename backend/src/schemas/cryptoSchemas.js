const { z } = require('zod');
const { publicKeyJwkSchema } = require('../crypto/e2ee');

const upsertPublicKeySchema = z.object({
  publicKeyJwk: publicKeyJwkSchema,
  algorithm: z.string().min(3).max(40).default('ECDH-Curve25519').optional(),
});

const publicKeyUserParamsSchema = z.object({
  userId: z.string().uuid(),
});

module.exports = {
  upsertPublicKeySchema,
  publicKeyUserParamsSchema,
};
