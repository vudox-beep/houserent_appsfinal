-- Track which drivers opened / viewed an open shift request.
CREATE TABLE IF NOT EXISTS moving_booking_views (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  driver_id INT UNSIGNED NOT NULL,
  viewed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_booking_driver (booking_id, driver_id),
  KEY idx_booking_viewed (booking_id, viewed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
