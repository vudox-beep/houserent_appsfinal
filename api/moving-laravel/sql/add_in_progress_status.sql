-- Allow drivers to Start ride (accepted → in_progress).
-- Safe to run on MySQL/MariaDB even if the column is already VARCHAR.

ALTER TABLE moving_bookings
  MODIFY COLUMN status VARCHAR(32) NOT NULL DEFAULT 'open';
