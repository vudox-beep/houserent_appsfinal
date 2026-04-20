CREATE TABLE IF NOT EXISTS landlord_ratings (
  id int(11) NOT NULL AUTO_INCREMENT,
  dealer_id int(11) NOT NULL,
  property_id int(11) NOT NULL,
  user_id int(11) NOT NULL,
  rating tinyint(3) unsigned NOT NULL,
  review TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_landlord_rating_user_property (user_id, property_id),
  KEY idx_landlord_rating_dealer (dealer_id),
  KEY idx_landlord_rating_property (property_id),
  CONSTRAINT fk_landlord_rating_dealer FOREIGN KEY (dealer_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_landlord_rating_property FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE,
  CONSTRAINT fk_landlord_rating_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
