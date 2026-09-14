-- Allow driver "arrived at destination" before complete.
-- Run once on MySQL (phpMyAdmin / cPanel).
ALTER TABLE moving_bookings
  MODIFY COLUMN status VARCHAR(32) NOT NULL DEFAULT 'open';
