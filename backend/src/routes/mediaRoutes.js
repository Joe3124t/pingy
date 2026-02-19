const express = require('express');
const { accessSignedMedia } = require('../controllers/mediaController');

const router = express.Router();

router.get('/access', accessSignedMedia);

module.exports = router;
