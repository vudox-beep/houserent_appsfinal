CREATE TABLE `premium_contacts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `transaction_reference` varchar(255) NOT NULL,
  `amount_paid` decimal(10,2) NOT NULL DEFAULT '5.00',
  `lenco_reference` varchar(255) DEFAULT NULL,
  `payment_type` varchar(50) DEFAULT NULL,
  `operator` varchar(50) DEFAULT NULL,
  `phone_number` varchar(20) DEFAULT NULL,
  `account_name` varchar(255) DEFAULT NULL,
  `operator_transaction_id` varchar(255) DEFAULT NULL,
  `status` enum('active','inactive') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `fk_premium_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;