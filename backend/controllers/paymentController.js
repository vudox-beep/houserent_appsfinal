const db = require('../db');

exports.getPaymentHistory = async (req, res) => {
  const tenant_id = req.user.id;
  try {
    const [payments] = await db.query(`
      SELECT rp.*, p.title as property_title, p.location
      FROM rent_payments rp
      JOIN rentals r ON rp.rental_id = r.id
      JOIN properties p ON r.property_id = p.id
      WHERE rp.tenant_id = ?
      ORDER BY rp.created_at DESC
    `, [tenant_id]);

    res.json(payments);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error fetching payment history' });
  }
};
