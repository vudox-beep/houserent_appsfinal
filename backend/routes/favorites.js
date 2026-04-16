const express = require('express');
const router = express.Router();
const { getFavorites, addFavorite, removeFavorite } = require('../controllers/favoriteController');
const { protect } = require('../middlewares/auth');

router.get('/', protect, getFavorites);
router.post('/', protect, addFavorite);
router.delete('/:property_id', protect, removeFavorite);

module.exports = router;
