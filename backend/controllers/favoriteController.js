const db = require('../db');

exports.getFavorites = async (req, res) => {
  try {
    const [favorites] = await db.query(`
      SELECT sp.id as saved_id, p.*, u.name as dealer_name, u.phone as dealer_phone 
      FROM saved_properties sp
      JOIN properties p ON sp.property_id = p.id
      JOIN users u ON p.dealer_id = u.id
      WHERE sp.user_id = ?
    `, [req.user.id]);

    for (let prop of favorites) {
      const [images] = await db.query('SELECT image_path FROM property_images WHERE property_id = ?', [prop.id]);
      prop.images = images.map(img => img.image_path);
    }

    res.json(favorites);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error fetching favorites' });
  }
};

exports.addFavorite = async (req, res) => {
  const { property_id } = req.body;
  try {
    // Check if already saved
    const [existing] = await db.query('SELECT * FROM saved_properties WHERE user_id = ? AND property_id = ?', [req.user.id, property_id]);
    if (existing.length > 0) return res.status(400).json({ message: 'Property already saved' });

    await db.query('INSERT INTO saved_properties (user_id, property_id) VALUES (?, ?)', [req.user.id, property_id]);
    res.status(201).json({ message: 'Property saved successfully' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error saving property' });
  }
};

exports.removeFavorite = async (req, res) => {
  const { property_id } = req.params;
  try {
    await db.query('DELETE FROM saved_properties WHERE user_id = ? AND property_id = ?', [req.user.id, property_id]);
    res.json({ message: 'Property removed from saved list' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error removing favorite' });
  }
};
