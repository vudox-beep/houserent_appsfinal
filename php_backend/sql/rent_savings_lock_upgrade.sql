-- Run this only when the Rent Savings tables were created before lock periods
-- were added. Do not run it after a fresh rent_savings.sql installation.

ALTER TABLE `rent_savings_transactions`
  ADD COLUMN `lock_days` INT UNSIGNED DEFAULT NULL AFTER `operator`,
  ADD COLUMN `lock_until` DATETIME DEFAULT NULL AFTER `lock_days`,
  ADD KEY `idx_rent_savings_unlock` (`tenant_id`, `lock_until`);
