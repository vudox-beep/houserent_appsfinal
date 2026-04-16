const express = require('express');
const router = express.Router();
const { getPaymentHistory } = require('../controllers/paymentController');
const { protect, authorize } = require('../middlewares/auth');

router.get('/history', protect, authorize('user', 'tenant'), getPaymentHistory);

module.exports = router;
