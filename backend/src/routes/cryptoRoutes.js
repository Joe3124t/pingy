const express = require('express');
const {
  upsertMyPublicKey,
  getUserPublicKey,
  getMyPublicKey,
} = require('../controllers/cryptoController');
const { validateRequest } = require('../middleware/validateRequest');
const {
  upsertPublicKeySchema,
  publicKeyUserParamsSchema,
} = require('../schemas/cryptoSchemas');

const router = express.Router();

router.get('/public-key/me', getMyPublicKey);
router.get('/public-key/:userId', validateRequest(publicKeyUserParamsSchema, 'params'), getUserPublicKey);
router.put('/public-key', validateRequest(upsertPublicKeySchema), upsertMyPublicKey);

module.exports = router;
