-- Activate / pay driver user_id = 920 (your live row)
-- Run in phpMyAdmin → SQL

UPDATE users
SET role = 'driver', is_banned = 0
WHERE id = 920;

UPDATE drivers
SET
  availability_status = 'available',
  booking_tokens = 50,
  vehicle_plate = COALESCE(NULLIF(TRIM(vehicle_plate), ''), 'ABC920'),
  service_area = COALESCE(NULLIF(TRIM(service_area), ''), 'Lusaka')
WHERE user_id = 920;

-- Verify
SELECT
  u.id, u.name, u.email, u.role, u.is_banned,
  d.availability_status, d.booking_tokens,
  d.vehicle_type, d.vehicle_plate, d.service_area
FROM users u
JOIN drivers d ON d.user_id = u.id
WHERE u.id = 920;
