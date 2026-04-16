const db = require('../db');

exports.getMyRentals = async (req, res) => {
  const tenant_id = req.user.id;
  try {
    const [rentals] = await db.query(`
      SELECT r.*, p.title, p.location, p.price, p.property_type,
             d.name as landlord_name, d.phone as landlord_phone
      FROM rentals r
      JOIN properties p ON r.property_id = p.id
      JOIN users d ON r.dealer_id = d.id
      WHERE r.tenant_id = ?
      ORDER BY r.created_at DESC
    `, [tenant_id]);

    // For each rental, calculate rent due date or get the latest payment status
    for (let rental of rentals) {
      const [payments] = await db.query(`
        SELECT * FROM rent_payments 
        WHERE rental_id = ? 
        ORDER BY created_at DESC LIMIT 1
      `, [rental.id]);
      
      rental.latest_payment = payments.length > 0 ? payments[0] : null;
      // You could add logic here to calculate next_due_date based on start_date and payments
    }

    res.json(rentals);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error fetching rentals' });
  }
};
