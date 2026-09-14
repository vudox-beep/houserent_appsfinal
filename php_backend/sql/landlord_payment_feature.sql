CREATE TABLE IF NOT EXISTS landlord_payment_features (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    dealer_id BIGINT UNSIGNED NOT NULL,
    reference VARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL DEFAULT 20.00,
    currency VARCHAR(10) NOT NULL DEFAULT 'ZMW',
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    payment_method VARCHAR(50) NOT NULL DEFAULT 'mobile-money',
    expires_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_landlord_payment_features_reference (reference),
    KEY idx_landlord_payment_features_dealer_id (dealer_id),
    KEY idx_landlord_payment_features_status_expires (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS landlord_payout_accounts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    dealer_id BIGINT UNSIGNED NOT NULL,
    phone VARCHAR(30) NOT NULL,
    operator VARCHAR(30) NOT NULL,
    country VARCHAR(10) NOT NULL DEFAULT 'zm',
    account_name VARCHAR(120) NULL,
    is_verified TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_landlord_payout_accounts_dealer_id (dealer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
