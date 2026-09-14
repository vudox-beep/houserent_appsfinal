-- =============================================================================
-- Activate a moving DRIVER as AVAILABLE + PAID (booking tokens)
-- Run in phpMyAdmin / MySQL on the HouseRent database.
--
-- What "paid / activated" means in this app:
--   • users.role              = 'driver'
--   • drivers.availability_status = 'available'  (can go online / see requests)
--   • drivers.booking_tokens  = N                (tokens to unlock requests)
--   • users.is_banned         = 0
-- =============================================================================

-- 1) SET WHO TO ACTIVATE (use ONE of these — leave the others as NULL)
SET @driver_user_id = NULL;          -- e.g. 42
SET @driver_email   = 'driver@example.com';  -- << change this
SET @driver_phone   = NULL;          -- e.g. '0977123456'
SET @tokens_to_give = 50;            -- paid unlock tokens

-- 2) Resolve user id from email / phone if needed
SET @driver_user_id = COALESCE(
  @driver_user_id,
  (SELECT id FROM users WHERE email = @driver_email LIMIT 1),
  (SELECT id FROM users WHERE phone = @driver_phone LIMIT 1)
);

-- Stop early if user was not found
SELECT IF(@driver_user_id IS NULL,
  'ERROR: user not found — set @driver_user_id / @driver_email / @driver_phone',
  CONCAT('Activating user_id=', @driver_user_id)
) AS status_check;

-- 3) Make sure account is a driver and not banned
UPDATE users
SET
  role = 'driver',
  is_banned = 0
WHERE id = @driver_user_id;

-- 4) Ensure a drivers row exists (create if missing)
INSERT INTO drivers (
  user_id,
  vehicle_type,
  vehicle_capacity,
  vehicle_plate,
  service_area,
  availability_status,
  booking_tokens,
  total_earnings
)
SELECT
  @driver_user_id,
  'Truck',
  '1 tonne',
  'PENDING',
  'Lusaka',
  'available',
  @tokens_to_give,
  0
WHERE @driver_user_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM drivers WHERE user_id = @driver_user_id
  );

-- 5) Activate + top up tokens (paid)
UPDATE drivers
SET
  availability_status = 'available',
  booking_tokens = GREATEST(COALESCE(booking_tokens, 0), @tokens_to_give)
WHERE user_id = @driver_user_id;

-- Optional: always SET exact token balance instead of GREATEST:
-- UPDATE drivers SET availability_status = 'available', booking_tokens = @tokens_to_give
-- WHERE user_id = @driver_user_id;

-- 6) Verify
SELECT
  u.id AS user_id,
  u.name,
  u.email,
  u.phone,
  u.role,
  u.is_banned,
  d.availability_status,
  d.booking_tokens,
  d.vehicle_type,
  d.vehicle_plate,
  d.service_area,
  d.total_earnings
FROM users u
LEFT JOIN drivers d ON d.user_id = u.id
WHERE u.id = @driver_user_id;


-- =============================================================================
-- QUICK ONE-LINERS (copy/paste after you know the user id)
-- =============================================================================
--
-- Make user 42 an online paid driver with 50 tokens:
--
--   UPDATE users SET role = 'driver', is_banned = 0 WHERE id = 42;
--   INSERT INTO drivers (user_id, vehicle_type, vehicle_capacity, vehicle_plate,
--     service_area, availability_status, booking_tokens, total_earnings)
--   VALUES (42, 'Truck', '1 tonne', 'ABC123', 'Lusaka', 'available', 50, 0)
--   ON DUPLICATE KEY UPDATE
--     availability_status = 'available',
--     booking_tokens = 50;
--
-- Add 20 more tokens to an existing driver:
--
--   UPDATE drivers SET booking_tokens = booking_tokens + 20 WHERE user_id = 42;
--
-- Find drivers:
--
--   SELECT u.id, u.name, u.email, d.availability_status, d.booking_tokens
--   FROM users u
--   JOIN drivers d ON d.user_id = u.id
--   WHERE u.role = 'driver';
-- =============================================================================
