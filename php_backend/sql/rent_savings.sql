-- Rent Savings ledger for HouseRent Africa tenants.
-- Run once against the atphieleqa_house database before deploying the API.

CREATE TABLE IF NOT EXISTS `rent_savings_accounts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `tenant_id` int(11) NOT NULL,
  `rent_goal` decimal(12,2) NOT NULL DEFAULT 2500.00,
  `target_date` date DEFAULT NULL,
  `currency` varchar(3) NOT NULL DEFAULT 'ZMW',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_rent_savings_tenant` (`tenant_id`),
  CONSTRAINT `fk_rent_savings_tenant` FOREIGN KEY (`tenant_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `rent_savings_transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `account_id` bigint unsigned NOT NULL,
  `tenant_id` int(11) NOT NULL,
  `type` enum('deposit','withdrawal') NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `fee` decimal(12,2) NOT NULL DEFAULT 0.00,
  `net_amount` decimal(12,2) NOT NULL,
  `currency` varchar(3) NOT NULL DEFAULT 'ZMW',
  `status` enum('pending','completed','failed','cancelled') NOT NULL DEFAULT 'pending',
  `reference` varchar(100) NOT NULL,
  `provider_reference` varchar(255) DEFAULT NULL,
  `payment_method` varchar(50) DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `operator` varchar(30) DEFAULT NULL,
  `lock_days` int unsigned DEFAULT NULL,
  `lock_until` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_rent_savings_reference` (`reference`),
  KEY `idx_rent_savings_tenant_status` (`tenant_id`,`status`),
  KEY `idx_rent_savings_unlock` (`tenant_id`,`lock_until`),
  CONSTRAINT `fk_rent_savings_transaction_account` FOREIGN KEY (`account_id`) REFERENCES `rent_savings_accounts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_rent_savings_transaction_tenant` FOREIGN KEY (`tenant_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
