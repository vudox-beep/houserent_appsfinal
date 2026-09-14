-- Optional driver profile photo for client offer cards / live ride UI.
-- Run once on MySQL. Ignore error if column already exists.
ALTER TABLE drivers
  ADD COLUMN photo_url VARCHAR(500) NULL AFTER vehicle_plate;
