const express = require('express');
const router = express.Router();
const { getProperties, getPropertyById, createProperty, updateProperty, deleteProperty } = require('../controllers/propertyController');
const { protect, authorize } = require('../middlewares/auth');
const multer = require('multer');

const storage = multer.diskStorage({
  destination(req, file, cb) {
    cb(null, 'uploads/');
  },
  filename(req, file, cb) {
    cb(null, `${Date.now()}-${file.originalname}`);
  }
});
const upload = multer({ storage });

router.get('/', getProperties);
router.get('/:id', getPropertyById);
router.post('/', protect, authorize('dealer', 'admin'), upload.array('images', 5), createProperty);
router.put('/:id', protect, authorize('dealer', 'admin'), updateProperty);
router.delete('/:id', protect, authorize('dealer', 'admin'), deleteProperty);

module.exports = router;
