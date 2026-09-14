'use strict';

require('dotenv').config();

const crypto = require('crypto');
const http = require('http');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { rateLimit } = require('express-rate-limit');
const mysql = require('mysql2/promise');
const { Server } = require('socket.io');
const { loadDatabaseConfig } = require('./database-config');

const app = express();
const server = http.createServer(app);
const allowedOrigin = process.env.APP_ORIGIN || '*';
const io = new Server(server, {
  cors: { origin: allowedOrigin, methods: ['GET', 'POST', 'PATCH'] },
});

const databaseConfig = loadDatabaseConfig();
const pool = mysql.createPool({
  ...databaseConfig,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  decimalNumbers: true,
  timezone: 'Z',
});

app.set('trust proxy', 1);
app.use(helmet());
app.use(cors({ origin: allowedOrigin }));
app.use(express.json({ limit: '64kb' }));
app.use(rateLimit({
  windowMs: 60 * 1000,
  limit: 180,
  standardHeaders: true,
  legacyHeaders: false,
}));

class ApiError extends Error {
  constructor(statusCode, code, message) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
  }
}

const ok = (res, message, data = {}, statusCode = 200) => {
  res.status(statusCode).json({ status: 'success', message, data });
};

const fail = (res, error) => {
  const statusCode = error instanceof ApiError ? error.statusCode : 500;
  const code = error instanceof ApiError ? error.code : 'server_error';
  if (!(error instanceof ApiError)) console.error(error);
  res.status(statusCode).json({
    status: 'error',
    code,
    message: error instanceof ApiError
      ? error.message
      : 'Something went wrong. Please try again.',
  });
};

const asyncRoute = handler => (req, res) => {
  Promise.resolve(handler(req, res)).catch(error => fail(res, error));
};

function safeEqual(actual, expected) {
  const a = Buffer.from(String(actual || ''));
  const b = Buffer.from(String(expected || ''));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function checkApiKey(value) {
  const expected = process.env.API_SHARED_SECRET;
  if (!expected || expected === 'replace-with-a-long-random-secret') return true;
  return safeEqual(value, expected);
}

async function loadUser(userId) {
  const id = Number(userId);
  if (!Number.isInteger(id) || id < 1) {
    throw new ApiError(401, 'login_required', 'Please log in before using moving bookings.');
  }

  const [rows] = await pool.query(
    `SELECT u.id, u.name, u.email, u.phone, u.role, u.is_banned,
            d.vehicle_type, d.vehicle_capacity, d.vehicle_plate,
            d.service_area, d.availability_status, d.booking_tokens
       FROM users u
       LEFT JOIN drivers d ON d.user_id = u.id
      WHERE u.id = ?
      LIMIT 1`,
    [id],
  );
  const user = rows[0];
  if (!user || Number(user.is_banned) === 1) {
    throw new ApiError(401, 'invalid_account', 'Your account is unavailable.');
  }
  return user;
}

async function authenticate(req, res, next) {
  try {
    if (!checkApiKey(req.get('x-api-key'))) {
      throw new ApiError(401, 'invalid_api_key', 'The mobile app could not be authenticated.');
    }
    req.user = await loadUser(req.get('x-user-id') || req.body?.user_id || req.query?.user_id);
    next();
  } catch (error) {
    fail(res, error);
  }
}

function requireRole(user, ...roles) {
  if (!roles.includes(user.role)) {
    throw new ApiError(403, 'wrong_account_type', 'This action is not available for your account type.');
  }
}

function requirePositiveAmount(value) {
  const amount = Math.round(Number(value) * 100) / 100;
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new ApiError(422, 'invalid_amount', 'Enter a valid price greater than zero.');
  }
  return amount;
}

function requireCoordinate(value, min, max, label) {
  const coordinate = Number(value);
  if (!Number.isFinite(coordinate) || coordinate < min || coordinate > max) {
    throw new ApiError(422, 'invalid_location', `${label} is invalid.`);
  }
  return coordinate;
}

function conversationRoom(bookingId, driverId) {
  return `booking:${Number(bookingId)}:driver:${Number(driverId)}`;
}

function tenantRoom(tenantId) {
  return `tenant:${Number(tenantId)}`;
}

function driverRoom(driverId) {
  return `driver:${Number(driverId)}`;
}

async function getBooking(bookingId, connection = pool, lock = false) {
  const [rows] = await connection.query(
    `SELECT b.*,
            tenant.name AS tenant_name,
            tenant.phone AS tenant_phone,
            driver.name AS driver_name,
            driver.phone AS driver_phone,
            d.vehicle_type,
            d.vehicle_capacity,
            d.vehicle_plate,
            d.current_latitude AS driver_latitude,
            d.current_longitude AS driver_longitude,
            d.location_updated_at,
            COALESCE((
              SELECT ROUND(AVG(r.rating), 1)
                FROM moving_driver_ratings r
               WHERE r.driver_id = b.driver_id
            ), 0) AS driver_rating,
            (
              SELECT COUNT(*)
                FROM moving_driver_ratings r
               WHERE r.driver_id = b.driver_id
            ) AS driver_rating_count
       FROM moving_bookings b
       JOIN users tenant ON tenant.id = b.tenant_id
       LEFT JOIN users driver ON driver.id = b.driver_id
       LEFT JOIN drivers d ON d.user_id = b.driver_id
      WHERE b.id = ?
      ${lock ? 'FOR UPDATE' : ''}`,
    [Number(bookingId)],
  );
  if (!rows[0]) throw new ApiError(404, 'booking_not_found', 'This moving request was not found.');
  return rows[0];
}

async function driverUnlocked(bookingId, driverId, connection = pool) {
  const [rows] = await connection.query(
    'SELECT id FROM driver_booking_unlocks WHERE booking_id = ? AND driver_id = ? LIMIT 1',
    [Number(bookingId), Number(driverId)],
  );
  return Boolean(rows[0]);
}

async function requireConversationAccess(user, bookingId, requestedDriverId, connection = pool) {
  const booking = await getBooking(bookingId, connection);
  let driverId;

  if (user.role === 'driver') {
    driverId = Number(user.id);
    const unlocked = await driverUnlocked(booking.id, driverId, connection);
    if (!unlocked && Number(booking.driver_id) !== driverId) {
      throw new ApiError(403, 'request_locked', 'Unlock this request before contacting the tenant.');
    }
  } else if (user.role === 'user' && Number(booking.tenant_id) === Number(user.id)) {
    driverId = Number(requestedDriverId || booking.driver_id);
    if (!driverId || !(await driverUnlocked(booking.id, driverId, connection))) {
      throw new ApiError(403, 'driver_not_available', 'This driver has not unlocked your request.');
    }
  } else {
    throw new ApiError(403, 'not_a_participant', 'You are not part of this moving request.');
  }

  return { booking, driverId };
}

function shapeBooking(row, user, unlocked = false) {
  const assignedToDriver = user.role === 'driver' && Number(row.driver_id) === Number(user.id);
  const tenantOwner = (user.role === 'user' || user.role === 'tenant')
    && Number(row.tenant_id) === Number(user.id);
  const canViewPrivate = tenantOwner || unlocked || assignedToDriver;
  // Drivers need map pins for open requests before unlocking.
  const showMapPins = canViewPrivate
    || (user.role === 'driver' && row.status === 'open');

  const booking = {
    id: Number(row.id),
    status: row.status,
    moving_date: row.moving_date,
    moving_time: row.moving_time,
    currency: row.currency,
    agreed_amount: row.agreed_amount,
    created_at: row.created_at,
    unlocked: Boolean(unlocked || assignedToDriver),
  };

  if (showMapPins) {
    booking.pickup = {
      address: canViewPrivate ? row.pickup_location : 'Pickup nearby',
      place_id: canViewPrivate ? row.pickup_place_id : null,
      latitude: Number(row.pickup_latitude),
      longitude: Number(row.pickup_longitude),
    };
    booking.dropoff = {
      address: canViewPrivate ? row.dropoff_location : 'Drop-off nearby',
      place_id: canViewPrivate ? row.dropoff_place_id : null,
      latitude: Number(row.dropoff_latitude),
      longitude: Number(row.dropoff_longitude),
    };
  }

  if (canViewPrivate) {
    booking.items = row.item_description;
    booking.contact_phone = row.contact_phone;
    booking.tenant = {
      id: Number(row.tenant_id),
      name: row.tenant_name,
      phone: row.tenant_phone,
    };
  } else if (user.role === 'driver' && row.status === 'open') {
    const firstName = String(row.tenant_name || 'Tenant').trim().split(/\s+/)[0] || 'Tenant';
    booking.tenant = {
      id: Number(row.tenant_id),
      name: firstName,
      phone: null,
    };
    booking.items = 'Unlock to see full item list';
  }

  if (row.driver_id) {
    booking.driver = {
      id: Number(row.driver_id),
      name: row.driver_name,
      phone: row.driver_phone,
      vehicle_type: row.vehicle_type,
      vehicle_capacity: row.vehicle_capacity,
      vehicle_plate: row.vehicle_plate,
      rating: Number(row.driver_rating || 0),
      rating_count: Number(row.driver_rating_count || 0),
      location: row.driver_latitude == null ? null : {
        latitude: Number(row.driver_latitude),
        longitude: Number(row.driver_longitude),
        updated_at: row.location_updated_at,
      },
    };
  }

  return booking;
}

async function createOffer(user, bookingId, payload) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const booking = await getBooking(bookingId, connection, true);
    if (booking.status !== 'open') {
      throw new ApiError(409, 'booking_not_open', 'Price negotiation has closed for this request.');
    }

    let driverId;
    if (user.role === 'driver') {
      driverId = Number(user.id);
      if (!(await driverUnlocked(booking.id, driverId, connection))) {
        throw new ApiError(403, 'request_locked', 'Unlock this request before making an offer.');
      }
    } else if (user.role === 'user' && Number(booking.tenant_id) === Number(user.id)) {
      driverId = Number(payload.driver_id);
      if (!driverId || !(await driverUnlocked(booking.id, driverId, connection))) {
        throw new ApiError(403, 'driver_not_available', 'Choose a driver who has unlocked your request.');
      }
    } else {
      throw new ApiError(403, 'not_a_participant', 'You cannot negotiate on this request.');
    }

    const amount = requirePositiveAmount(payload.amount);
    const note = String(payload.note || '').trim().slice(0, 500) || null;
    await connection.query(
      `UPDATE moving_booking_offers
          SET status = 'rejected'
        WHERE booking_id = ? AND driver_id = ? AND status = 'pending'`,
      [booking.id, driverId],
    );
    const [result] = await connection.query(
      `INSERT INTO moving_booking_offers
         (booking_id, driver_id, sender_id, amount, currency, note)
       VALUES (?, ?, ?, ?, 'ZMW', ?)`,
      [booking.id, driverId, user.id, amount, note],
    );
    const [rows] = await connection.query(
      `SELECT o.*, u.name AS sender_name, u.role AS sender_role
         FROM moving_booking_offers o
         JOIN users u ON u.id = o.sender_id
        WHERE o.id = ?`,
      [result.insertId],
    );
    await connection.commit();
    const offer = rows[0];
    io.to(conversationRoom(booking.id, driverId)).emit('offer:new', offer);
    io.to(tenantRoom(booking.tenant_id)).emit('offer:new', offer);
    io.to(driverRoom(driverId)).emit('offer:new', offer);
    return offer;
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

async function createMessage(user, bookingId, payload) {
  const { booking, driverId } = await requireConversationAccess(user, bookingId, payload.driver_id);
  const message = String(payload.message || '').trim();
  if (!message || message.length > 1000) {
    throw new ApiError(422, 'invalid_message', 'Write a message between 1 and 1000 characters.');
  }

  const [result] = await pool.query(
    `INSERT INTO moving_booking_messages (booking_id, driver_id, sender_id, message)
     VALUES (?, ?, ?, ?)`,
    [booking.id, driverId, user.id, message],
  );
  const data = {
    id: Number(result.insertId),
    booking_id: Number(booking.id),
    driver_id: driverId,
    sender_id: Number(user.id),
    sender_name: user.name,
    sender_role: user.role,
    message,
    created_at: new Date().toISOString(),
  };
  io.to(conversationRoom(booking.id, driverId)).emit('message:new', data);
  io.to(tenantRoom(booking.tenant_id)).emit('message:new', data);
  io.to(driverRoom(driverId)).emit('message:new', data);
  return data;
}

async function updateDriverLocation(user, payload) {
  requireRole(user, 'driver');
  const latitude = requireCoordinate(payload.latitude, -90, 90, 'Latitude');
  const longitude = requireCoordinate(payload.longitude, -180, 180, 'Longitude');
  await pool.query(
    `UPDATE drivers
        SET current_latitude = ?, current_longitude = ?, location_updated_at = NOW()
      WHERE user_id = ?`,
    [latitude, longitude, user.id],
  );
  const location = {
    driver_id: Number(user.id),
    latitude,
    longitude,
    updated_at: new Date().toISOString(),
  };
  const [bookings] = await pool.query(
    "SELECT id, tenant_id FROM moving_bookings WHERE driver_id = ? AND status = 'accepted'",
    [user.id],
  );
  bookings.forEach(booking => {
    io.to(conversationRoom(booking.id, user.id)).emit('driver:location', location);
    io.to(tenantRoom(booking.tenant_id)).emit('driver:location', {
      ...location,
      booking_id: Number(booking.id),
    });
  });
  return location;
}

app.get('/health', asyncRoute(async (req, res) => {
  await pool.query('SELECT 1');
  ok(res, 'Moving marketplace API is online.', { realtime: true });
}));

app.use('/api/v1', authenticate);

app.post('/api/v1/bookings', asyncRoute(async (req, res) => {
  requireRole(req.user, 'user');
  const pickup = req.body.pickup || {};
  const dropoff = req.body.dropoff || {};
  const movingDate = String(req.body.moving_date || '');
  const items = String(req.body.item_description || '').trim();
  const phone = String(req.body.contact_phone || req.user.phone || '').trim();
  if (!pickup.address || !dropoff.address || !movingDate || !items || !phone) {
    throw new ApiError(422, 'missing_booking_details', 'Add pickup, destination, moving date, items and a contact number.');
  }
  if (new Date(`${movingDate}T23:59:59`) < new Date()) {
    throw new ApiError(422, 'invalid_moving_date', 'Choose today or a future moving date.');
  }

  const pickupLatitude = requireCoordinate(pickup.latitude, -90, 90, 'Pickup latitude');
  const pickupLongitude = requireCoordinate(pickup.longitude, -180, 180, 'Pickup longitude');
  const dropoffLatitude = requireCoordinate(dropoff.latitude, -90, 90, 'Drop-off latitude');
  const dropoffLongitude = requireCoordinate(dropoff.longitude, -180, 180, 'Drop-off longitude');
  const [result] = await pool.query(
    `INSERT INTO moving_bookings
       (tenant_id, pickup_location, pickup_place_id, pickup_latitude, pickup_longitude,
        dropoff_location, dropoff_place_id, dropoff_latitude, dropoff_longitude,
        moving_date, moving_time, item_description, contact_phone)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      req.user.id,
      String(pickup.address).slice(0, 255),
      String(pickup.place_id || '').slice(0, 255) || null,
      pickupLatitude,
      pickupLongitude,
      String(dropoff.address).slice(0, 255),
      String(dropoff.place_id || '').slice(0, 255) || null,
      dropoffLatitude,
      dropoffLongitude,
      movingDate,
      String(req.body.moving_time || '').slice(0, 50) || null,
      items.slice(0, 5000),
      phone.slice(0, 30),
    ],
  );
  const booking = await getBooking(result.insertId);
  io.emit('booking:available', shapeBooking(booking, req.user, false));
  ok(res, 'Your moving request is live. Available drivers can now respond.', {
    booking: shapeBooking(booking, req.user, true),
  }, 201);
}));

app.get('/api/v1/bookings', asyncRoute(async (req, res) => {
  const page = Math.max(1, Number(req.query.page || 1));
  const limit = Math.min(50, Math.max(1, Number(req.query.limit || 20)));
  const offset = (page - 1) * limit;
  let rows;

  if (req.user.role === 'user') {
    [rows] = await pool.query(
      `SELECT b.*, tenant.name AS tenant_name, tenant.phone AS tenant_phone,
              driver.name AS driver_name, driver.phone AS driver_phone,
              d.vehicle_type, d.vehicle_capacity, d.vehicle_plate,
              d.current_latitude AS driver_latitude, d.current_longitude AS driver_longitude,
              d.location_updated_at,
              COALESCE(ROUND(AVG(r.rating), 1), 0) AS driver_rating,
              COUNT(r.id) AS driver_rating_count,
              1 AS unlock_id
         FROM moving_bookings b
         JOIN users tenant ON tenant.id = b.tenant_id
         LEFT JOIN users driver ON driver.id = b.driver_id
         LEFT JOIN drivers d ON d.user_id = b.driver_id
         LEFT JOIN moving_driver_ratings r ON r.driver_id = b.driver_id
        WHERE b.tenant_id = ?
        GROUP BY b.id
        ORDER BY b.created_at DESC
        LIMIT ? OFFSET ?`,
      [req.user.id, limit, offset],
    );
  } else {
    requireRole(req.user, 'driver');
    [rows] = await pool.query(
      `SELECT b.*, tenant.name AS tenant_name, tenant.phone AS tenant_phone,
              driver.name AS driver_name, driver.phone AS driver_phone,
              d.vehicle_type, d.vehicle_capacity, d.vehicle_plate,
              d.current_latitude AS driver_latitude, d.current_longitude AS driver_longitude,
              d.location_updated_at,
              COALESCE(ROUND(AVG(r.rating), 1), 0) AS driver_rating,
              COUNT(r.id) AS driver_rating_count,
              x.id AS unlock_id
         FROM moving_bookings b
         JOIN users tenant ON tenant.id = b.tenant_id
         LEFT JOIN users driver ON driver.id = b.driver_id
         LEFT JOIN drivers d ON d.user_id = b.driver_id
         LEFT JOIN moving_driver_ratings r ON r.driver_id = b.driver_id
         LEFT JOIN driver_booking_unlocks x ON x.booking_id = b.id AND x.driver_id = ?
        WHERE b.status = 'open' OR b.driver_id = ?
        GROUP BY b.id
        ORDER BY CASE b.status WHEN 'accepted' THEN 0 WHEN 'open' THEN 1 ELSE 2 END,
                 b.moving_date ASC
        LIMIT ? OFFSET ?`,
      [req.user.id, req.user.id, limit, offset],
    );
  }

  ok(res, 'Moving requests loaded.', {
    bookings: rows.map(row => shapeBooking(row, req.user, Boolean(row.unlock_id))),
    pagination: { page, limit, returned: rows.length },
  });
}));

app.get('/api/v1/bookings/:bookingId', asyncRoute(async (req, res) => {
  const booking = await getBooking(req.params.bookingId);
  const unlocked = req.user.role === 'driver'
    ? await driverUnlocked(booking.id, req.user.id)
    : Number(booking.tenant_id) === Number(req.user.id);
  if (!unlocked && Number(booking.driver_id) !== Number(req.user.id)) {
    if (req.user.role !== 'driver' || booking.status !== 'open') {
      throw new ApiError(403, 'not_a_participant', 'You cannot view this moving request.');
    }
  }
  ok(res, 'Moving request loaded.', { booking: shapeBooking(booking, req.user, unlocked) });
}));

app.post('/api/v1/bookings/:bookingId/unlock', asyncRoute(async (req, res) => {
  requireRole(req.user, 'driver');
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [drivers] = await connection.query(
      'SELECT booking_tokens, availability_status FROM drivers WHERE user_id = ? FOR UPDATE',
      [req.user.id],
    );
    const booking = await getBooking(req.params.bookingId, connection, true);
    if (!drivers[0] || drivers[0].availability_status !== 'available') {
      throw new ApiError(409, 'driver_unavailable', 'Set your status to available before unlocking requests.');
    }
    if (booking.status !== 'open') {
      throw new ApiError(409, 'booking_not_open', 'This request is no longer open.');
    }

    const [result] = await connection.query(
      'INSERT IGNORE INTO driver_booking_unlocks (driver_id, booking_id) VALUES (?, ?)',
      [req.user.id, booking.id],
    );
    if (result.affectedRows > 0) {
      if (Number(drivers[0].booking_tokens) < 1) {
        throw new ApiError(402, 'token_required', 'Buy one booking token to unlock this request.');
      }
      await connection.query(
        'UPDATE drivers SET booking_tokens = booking_tokens - 1 WHERE user_id = ?',
        [req.user.id],
      );
    }
    await connection.commit();
    io.to(tenantRoom(booking.tenant_id)).emit('booking:unlocked', {
      booking_id: Number(booking.id),
      driver: {
        id: Number(req.user.id),
        name: req.user.name,
        vehicle_type: req.user.vehicle_type,
        vehicle_plate: req.user.vehicle_plate,
      },
    });
    ok(res, result.affectedRows > 0
      ? 'Request unlocked. You can now chat and negotiate the price.'
      : 'This request was already unlocked.', {
      booking: shapeBooking(await getBooking(booking.id), req.user, true),
      token_spent: result.affectedRows > 0 ? 1 : 0,
    });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}));

app.post('/api/v1/bookings/:bookingId/cancel', asyncRoute(async (req, res) => {
  requireRole(req.user, 'user');
  const [result] = await pool.query(
    "UPDATE moving_bookings SET status = 'cancelled' WHERE id = ? AND tenant_id = ? AND status = 'open'",
    [req.params.bookingId, req.user.id],
  );
  if (!result.affectedRows) {
    throw new ApiError(409, 'cannot_cancel', 'Only your open moving requests can be cancelled.');
  }
  io.emit('booking:status', { booking_id: Number(req.params.bookingId), status: 'cancelled' });
  ok(res, 'Your moving request has been cancelled.');
}));

app.post('/api/v1/bookings/:bookingId/offers', asyncRoute(async (req, res) => {
  const offer = await createOffer(req.user, req.params.bookingId, req.body);
  ok(res, req.user.role === 'driver'
    ? 'Your price offer was sent to the tenant.'
    : 'Your counteroffer was sent to the driver.', { offer }, 201);
}));

app.get('/api/v1/bookings/:bookingId/offers', asyncRoute(async (req, res) => {
  const { booking, driverId } = await requireConversationAccess(
    req.user,
    req.params.bookingId,
    req.query.driver_id,
  );
  const [offers] = await pool.query(
    `SELECT o.*, u.name AS sender_name, u.role AS sender_role
       FROM moving_booking_offers o
       JOIN users u ON u.id = o.sender_id
      WHERE o.booking_id = ? AND o.driver_id = ?
      ORDER BY o.id ASC`,
    [booking.id, driverId],
  );
  ok(res, 'Price negotiation loaded.', { offers, driver_id: driverId });
}));

app.post('/api/v1/bookings/:bookingId/offers/:offerId/accept', asyncRoute(async (req, res) => {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const booking = await getBooking(req.params.bookingId, connection, true);
    const [offers] = await connection.query(
      `SELECT * FROM moving_booking_offers
        WHERE id = ? AND booking_id = ? AND status = 'pending'
        FOR UPDATE`,
      [req.params.offerId, booking.id],
    );
    const offer = offers[0];
    if (!offer || booking.status !== 'open') {
      throw new ApiError(409, 'offer_unavailable', 'This price offer is no longer available.');
    }

    const isTenant = req.user.role === 'user'
      && Number(booking.tenant_id) === Number(req.user.id)
      && Number(offer.sender_id) === Number(offer.driver_id);
    const isDriver = req.user.role === 'driver'
      && Number(offer.driver_id) === Number(req.user.id)
      && Number(offer.sender_id) === Number(booking.tenant_id);
    if (!isTenant && !isDriver) {
      throw new ApiError(403, 'cannot_accept_own_offer', 'Only the other person can accept this price.');
    }

    await connection.query(
      "UPDATE moving_booking_offers SET status = 'rejected' WHERE booking_id = ? AND status = 'pending'",
      [booking.id],
    );
    await connection.query(
      "UPDATE moving_booking_offers SET status = 'accepted' WHERE id = ?",
      [offer.id],
    );
    await connection.query(
      "UPDATE moving_bookings SET driver_id = ?, agreed_amount = ?, status = 'accepted' WHERE id = ?",
      [offer.driver_id, offer.amount, booking.id],
    );
    await connection.commit();
    const updated = await getBooking(booking.id);
    const event = {
      booking_id: Number(booking.id),
      status: 'accepted',
      agreed_amount: Number(offer.amount),
      driver_id: Number(offer.driver_id),
    };
    io.to(conversationRoom(booking.id, offer.driver_id)).emit('offer:accepted', event);
    io.to(tenantRoom(booking.tenant_id)).emit('offer:accepted', event);
    io.to(driverRoom(offer.driver_id)).emit('offer:accepted', event);
    ok(res, 'Price agreed. The driver is now assigned to this move.', {
      booking: shapeBooking(updated, req.user, true),
    });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}));

app.post('/api/v1/bookings/:bookingId/messages', asyncRoute(async (req, res) => {
  const message = await createMessage(req.user, req.params.bookingId, req.body);
  ok(res, 'Message sent.', { message }, 201);
}));

app.get('/api/v1/bookings/:bookingId/messages', asyncRoute(async (req, res) => {
  const { booking, driverId } = await requireConversationAccess(
    req.user,
    req.params.bookingId,
    req.query.driver_id,
  );
  const afterId = Math.max(0, Number(req.query.after_id || 0));
  const [messages] = await pool.query(
    `SELECT m.*, u.name AS sender_name, u.role AS sender_role
       FROM moving_booking_messages m
       JOIN users u ON u.id = m.sender_id
      WHERE m.booking_id = ? AND m.driver_id = ? AND m.id > ?
      ORDER BY m.id ASC
      LIMIT 200`,
    [booking.id, driverId, afterId],
  );
  await pool.query(
    `UPDATE moving_booking_messages
        SET read_at = COALESCE(read_at, NOW())
      WHERE booking_id = ? AND driver_id = ? AND sender_id <> ?`,
    [booking.id, driverId, req.user.id],
  );
  ok(res, 'Conversation loaded.', { messages, driver_id: driverId });
}));

app.post('/api/v1/bookings/:bookingId/complete', asyncRoute(async (req, res) => {
  requireRole(req.user, 'driver');
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const booking = await getBooking(req.params.bookingId, connection, true);
    if (booking.status !== 'accepted' || Number(booking.driver_id) !== Number(req.user.id)) {
      throw new ApiError(409, 'cannot_complete', 'Only your active job can be marked complete.');
    }
    await connection.query("UPDATE moving_bookings SET status = 'completed' WHERE id = ?", [booking.id]);
    await connection.query(
      'UPDATE drivers SET total_earnings = total_earnings + ? WHERE user_id = ?',
      [booking.agreed_amount || 0, req.user.id],
    );
    await connection.commit();
    const event = { booking_id: Number(booking.id), status: 'completed' };
    io.to(conversationRoom(booking.id, req.user.id)).emit('booking:status', event);
    io.to(tenantRoom(booking.tenant_id)).emit('booking:status', event);
    ok(res, 'Move completed. The tenant can now rate your service.');
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}));

app.post('/api/v1/bookings/:bookingId/rating', asyncRoute(async (req, res) => {
  requireRole(req.user, 'user');
  const booking = await getBooking(req.params.bookingId);
  if (booking.status !== 'completed' || Number(booking.tenant_id) !== Number(req.user.id) || !booking.driver_id) {
    throw new ApiError(403, 'rating_not_allowed', 'You can rate your driver after a completed move.');
  }
  const rating = Number(req.body.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new ApiError(422, 'invalid_rating', 'Choose a rating from 1 to 5 stars.');
  }
  const comment = String(req.body.comment || '').trim().slice(0, 500) || null;
  await pool.query(
    `INSERT INTO moving_driver_ratings (booking_id, tenant_id, driver_id, rating, comment)
     VALUES (?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE rating = VALUES(rating), comment = VALUES(comment)`,
    [booking.id, req.user.id, booking.driver_id, rating, comment],
  );
  const [summary] = await pool.query(
    `SELECT ROUND(AVG(rating), 1) AS rating, COUNT(*) AS rating_count
       FROM moving_driver_ratings WHERE driver_id = ?`,
    [booking.driver_id],
  );
  io.to(driverRoom(booking.driver_id)).emit('driver:rating', summary[0]);
  ok(res, 'Thank you. Your driver rating has been saved.', { driver_rating: summary[0] });
}));

app.patch('/api/v1/drivers/me/location', asyncRoute(async (req, res) => {
  const location = await updateDriverLocation(req.user, req.body);
  ok(res, 'Driver location updated.', { location });
}));

app.patch('/api/v1/drivers/me/availability', asyncRoute(async (req, res) => {
  requireRole(req.user, 'driver');
  const availability = req.body.availability_status === 'available' ? 'available' : 'unavailable';
  await pool.query('UPDATE drivers SET availability_status = ? WHERE user_id = ?', [
    availability,
    req.user.id,
  ]);
  ok(res, `You are now ${availability}.`, { availability_status: availability });
}));

app.patch('/api/v1/drivers/me/profile', asyncRoute(async (req, res) => {
  requireRole(req.user, 'driver');
  const vehicleType = String(req.body.vehicle_type || req.user.vehicle_type || '').trim();
  const vehicleCapacity = String(req.body.vehicle_capacity || req.user.vehicle_capacity || '').trim();
  const vehiclePlate = String(req.body.vehicle_plate || '').trim().toUpperCase();
  const serviceArea = String(req.body.service_area || req.user.service_area || '').trim();
  if (!vehicleType || !vehicleCapacity || !vehiclePlate || !serviceArea) {
    throw new ApiError(
      422,
      'missing_driver_details',
      'Vehicle type, capacity, number plate and service area are required.',
    );
  }
  await pool.query(
    `UPDATE drivers
        SET vehicle_type = ?, vehicle_capacity = ?, vehicle_plate = ?, service_area = ?
      WHERE user_id = ?`,
    [
      vehicleType.slice(0, 50),
      vehicleCapacity.slice(0, 100),
      vehiclePlate.slice(0, 30),
      serviceArea.slice(0, 255),
      req.user.id,
    ],
  );
  ok(res, 'Your driver and vehicle details have been updated.', {
    driver: {
      id: Number(req.user.id),
      name: req.user.name,
      vehicle_type: vehicleType,
      vehicle_capacity: vehicleCapacity,
      vehicle_plate: vehiclePlate,
      service_area: serviceArea,
    },
  });
}));

app.get('/api/v1/drivers/me', asyncRoute(async (req, res) => {
  requireRole(req.user, 'driver');
  const [ratings] = await pool.query(
    `SELECT COALESCE(ROUND(AVG(rating), 1), 0) AS rating, COUNT(*) AS rating_count
       FROM moving_driver_ratings WHERE driver_id = ?`,
    [req.user.id],
  );
  ok(res, 'Driver profile loaded.', {
    driver: {
      id: Number(req.user.id),
      name: req.user.name,
      phone: req.user.phone,
      vehicle_type: req.user.vehicle_type,
      vehicle_capacity: req.user.vehicle_capacity,
      vehicle_plate: req.user.vehicle_plate,
      service_area: req.user.service_area,
      availability_status: req.user.availability_status,
      booking_tokens: Number(req.user.booking_tokens || 0),
      rating: Number(ratings[0].rating || 0),
      rating_count: Number(ratings[0].rating_count || 0),
    },
  });
}));

io.use(async (socket, next) => {
  try {
    const apiKey = socket.handshake.auth?.apiKey || socket.handshake.headers['x-api-key'];
    if (!checkApiKey(apiKey)) throw new ApiError(401, 'invalid_api_key', 'Invalid API key.');
    socket.user = await loadUser(
      socket.handshake.auth?.userId || socket.handshake.headers['x-user-id'],
    );
    next();
  } catch (error) {
    next(new Error(error.code || 'unauthenticated'));
  }
});

io.on('connection', socket => {
  const user = socket.user;
  socket.join(user.role === 'driver' ? driverRoom(user.id) : tenantRoom(user.id));

  socket.on('booking:join', async (payload = {}, acknowledge = () => {}) => {
    try {
      const { booking, driverId } = await requireConversationAccess(
        user,
        payload.booking_id,
        payload.driver_id,
      );
      socket.join(conversationRoom(booking.id, driverId));
      acknowledge({ status: 'success', booking_id: Number(booking.id), driver_id: driverId });
    } catch (error) {
      acknowledge({ status: 'error', code: error.code, message: error.message });
    }
  });

  socket.on('message:send', async (payload = {}, acknowledge = () => {}) => {
    try {
      const message = await createMessage(user, payload.booking_id, payload);
      acknowledge({ status: 'success', message });
    } catch (error) {
      acknowledge({ status: 'error', code: error.code, message: error.message });
    }
  });

  socket.on('offer:submit', async (payload = {}, acknowledge = () => {}) => {
    try {
      const offer = await createOffer(user, payload.booking_id, payload);
      acknowledge({ status: 'success', offer });
    } catch (error) {
      acknowledge({ status: 'error', code: error.code, message: error.message });
    }
  });

  socket.on('driver:location', async (payload = {}, acknowledge = () => {}) => {
    try {
      const location = await updateDriverLocation(user, payload);
      acknowledge({ status: 'success', location });
    } catch (error) {
      acknowledge({ status: 'error', code: error.code, message: error.message });
    }
  });
});

app.use((req, res) => {
  res.status(404).json({
    status: 'error',
    code: 'route_not_found',
    message: 'This marketplace API route does not exist.',
  });
});

const port = Number(process.env.PORT || 3000);
server.listen(port, () => {
  console.log(`Moving marketplace API listening on port ${port}`);
});
