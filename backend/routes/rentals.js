const express = require('express');
const router = express.Router();
const { getMyRentals } = require('../controllers/rentalController');
const { protect, authorize } = require('../middlewares/auth');

router.get('/my-rentals', protect, authorize('user', 'tenant'), getMyRentals);

module.exports = router;
