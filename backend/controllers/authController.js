const db = require('../db');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const generateToken = (id, role) => {
  return jwt.sign({ id, role }, process.env.JWT_SECRET, { expiresIn: '30d' });
};

exports.register = async (req, res) => {
  const { name, email, password, role } = req.body;
  try {
    // Check if user exists
    const [existing] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    if (existing.length > 0) {
      return res.status(400).json({ message: 'User already exists' });
    }

    // Hash password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);
    // Ensure we use the correct format. bcryptjs uses $2a$ which is compatible.

    // Insert user
    // Make sure we use 'user' role instead of 'tenant' since 'user' is in your ENUM
    const userRole = (role === 'dealer') ? 'dealer' : 'user';
    const [result] = await db.query(
      'INSERT INTO users (name, email, password, role) VALUES (?, ?, ?, ?)',
      [name, email, hashedPassword, userRole]
    );

    const newUserId = result.insertId;

    // If dealer, add to dealers table
    if (userRole === 'dealer') {
      await db.query('INSERT INTO dealers (user_id) VALUES (?)', [newUserId]);
    }

    res.status(201).json({
      id: newUserId,
      name,
      email,
      role: userRole,
      token: generateToken(newUserId, userRole)
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.login = async (req, res) => {
  const { email, password } = req.body;
  try {
    const [users] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    if (users.length === 0) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }

    const user = users[0];
    
    // Convert $2y$ to $2a$ for bcryptjs compatibility if needed, though bcryptjs often handles $2y$
    let hash = user.password;
    if (hash && hash.startsWith('$2y$')) {
      hash = hash.replace('$2y$', '$2a$');
    }

    const isMatch = await bcrypt.compare(password, hash);
    if (!isMatch) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }

    res.json({
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      token: generateToken(user.id, user.role)
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getMe = async (req, res) => {
  try {
    const [users] = await db.query('SELECT id, name, email, phone, role FROM users WHERE id = ?', [req.user.id]);
    if (users.length === 0) return res.status(404).json({ message: 'User not found' });
    res.json(users[0]);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.updateProfile = async (req, res) => {
  const { name, phone } = req.body;
  try {
    await db.query('UPDATE users SET name = ?, phone = ? WHERE id = ?', [name, phone, req.user.id]);
    res.json({ message: 'Profile updated successfully' });
  } catch (err) {
    res.status(500).json({ message: 'Server error updating profile' });
  }
};
