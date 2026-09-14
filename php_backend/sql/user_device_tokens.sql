-- Run once on the same MySQL database used by the notification API.
-- This table is additive and does not alter website notification tables.
CREATE TABLE IF NOT EXISTS user_device_tokens (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    fcm_token VARCHAR(512) NOT NULL,
    platform VARCHAR(20) NOT NULL DEFAULT 'android',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_user_device_tokens_fcm_token (fcm_token),
    KEY idx_user_device_tokens_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Run this too if the table already exists with VARCHAR(255).
ALTER TABLE user_device_tokens
    MODIFY fcm_token VARCHAR(512) NOT NULL;
