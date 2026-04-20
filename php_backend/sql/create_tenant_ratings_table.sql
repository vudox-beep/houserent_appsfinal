CREATE TABLE IF NOT EXISTS tenant_ratings (
  id int(11) NOT NULL AUTO_INCREMENT,
  dealer_id int(11) NOT NULL,
  tenant_id int(11) NOT NULL,
  rental_id int(11) NULL,
  rating tinyint(3) unsigned NOT NULL,
  review TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_tenant_rating_dealer_tenant (dealer_id, tenant_id),
  KEY idx_tenant_rating_tenant (tenant_id),
  KEY idx_tenant_rating_dealer (dealer_id),
  CONSTRAINT fk_tenant_rating_dealer FOREIGN KEY (dealer_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_tenant_rating_tenant FOREIGN KEY (tenant_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_tenant_rating_rental FOREIGN KEY (rental_id) REFERENCES rentals(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
