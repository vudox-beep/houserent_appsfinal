const db = require('../db');

exports.getProperties = async (req, res) => {
  try {
    let query = `
      SELECT p.*, u.name as dealer_name, u.phone as dealer_phone, u.email as dealer_email
      FROM properties p
      JOIN users u ON p.dealer_id = u.id
      WHERE p.status = 'available'
    `;
    const params = [];

    // Filters
    if (req.query.location) {
      query += ` AND p.city LIKE ?`;
      params.push(`%${req.query.location}%`);
    }
    if (req.query.minPrice) {
      query += ` AND p.price >= ?`;
      params.push(req.query.minPrice);
    }
    if (req.query.maxPrice) {
      query += ` AND p.price <= ?`;
      params.push(req.query.maxPrice);
    }
    if (req.query.type) {
      query += ` AND p.property_type = ?`;
      params.push(req.query.type);
    }
    if (req.query.bedrooms) {
      query += ` AND p.bedrooms >= ?`;
      params.push(req.query.bedrooms);
    }
    if (req.query.dealer_id) {
      query += ` AND p.dealer_id = ?`;
      params.push(req.query.dealer_id);
    }

    query += ' ORDER BY p.created_at DESC';

    const [properties] = await db.query(query, params);

    // Fetch images for each property
    for (let prop of properties) {
      const [images] = await db.query('SELECT image_path FROM property_images WHERE property_id = ?', [prop.id]);
      prop.images = images.map(img => img.image_path);
    }

    res.json(properties);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getPropertyById = async (req, res) => {
  try {
    const [properties] = await db.query(`
      SELECT p.*, u.name as dealer_name, u.phone as dealer_phone, u.email as dealer_email
      FROM properties p
      JOIN users u ON p.dealer_id = u.id
      WHERE p.id = ?
    `, [req.params.id]);

    if (properties.length === 0) return res.status(404).json({ message: 'Property not found' });

    const property = properties[0];
    const [images] = await db.query('SELECT image_path FROM property_images WHERE property_id = ?', [property.id]);
    property.images = images.map(img => img.image_path);

    res.json(property);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.createProperty = async (req, res) => {
  const { title, description, price, bedrooms, bathrooms, property_type, location, city, country } = req.body;
  const dealer_id = req.user.id;

  try {
    const [result] = await db.query(
      `INSERT INTO properties (dealer_id, title, description, price, bedrooms, bathrooms, property_type, location, city, country)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [dealer_id, title, description, price, bedrooms, bathrooms, property_type, location, city, country]
    );

    const propertyId = result.insertId;

    if (req.files && req.files.length > 0) {
      const imagePromises = req.files.map(file => {
        return db.query(
          'INSERT INTO property_images (property_id, image_path, type) VALUES (?, ?, ?)',
          [propertyId, file.path, 'image']
        );
      });
      await Promise.all(imagePromises);
    }

    res.status(201).json({ message: 'Property created', propertyId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.updateProperty = async (req, res) => {
  // Simplistic update for demonstration
  const { title, description, price } = req.body;
  try {
    const [prop] = await db.query('SELECT * FROM properties WHERE id = ?', [req.params.id]);
    if (prop.length === 0) return res.status(404).json({ message: 'Not found' });

    if (prop[0].dealer_id !== req.user.id && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Unauthorized' });
    }

    await db.query(
      'UPDATE properties SET title=?, description=?, price=? WHERE id=?',
      [title, description, price, req.params.id]
    );
    res.json({ message: 'Property updated' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.deleteProperty = async (req, res) => {
  try {
    const [prop] = await db.query('SELECT * FROM properties WHERE id = ?', [req.params.id]);
    if (prop.length === 0) return res.status(404).json({ message: 'Not found' });

    if (prop[0].dealer_id !== req.user.id && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Unauthorized' });
    }

    await db.query('DELETE FROM properties WHERE id = ?', [req.params.id]);
    res.json({ message: 'Property removed' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
};
