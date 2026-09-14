-- Separate tables for Agent + Private Company
-- Do NOT alter the existing `dealers` table.
-- Run in phpMyAdmin / MySQL.
--
-- APIs live in: php_backend/api/agent_company/

-- REQUIRED: allow agent + company on users.role (otherwise accounts become "user"/tenant)
ALTER TABLE users
  MODIFY COLUMN role ENUM('user','tenant','dealer','agent','company','driver','admin')
  NOT NULL DEFAULT 'user';

CREATE TABLE IF NOT EXISTS agents (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL UNIQUE,
  subscription_status VARCHAR(20) NOT NULL DEFAULT 'inactive',
  subscription_expiry DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_agents_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS private_companies (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL UNIQUE,
  company_name VARCHAR(191) NULL,
  company_reg_no VARCHAR(100) NULL,
  company_address VARCHAR(255) NULL,
  company_contact VARCHAR(100) NULL,
  company_details_complete TINYINT(1) NOT NULL DEFAULT 0,
  subscription_status VARCHAR(20) NOT NULL DEFAULT 'inactive',
  subscription_expiry DATETIME NULL,
  monthly_fee DECIMAL(10,2) NOT NULL DEFAULT 300.00,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_companies_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Private chat: agents <-> house-hunt request owners
CREATE TABLE IF NOT EXISTS request_agent_messages (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  request_id INT NOT NULL,
  sender_id INT NOT NULL,
  receiver_id INT NOT NULL,
  message TEXT NOT NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_ram_request (request_id),
  INDEX idx_ram_sender (sender_id),
  INDEX idx_ram_receiver (receiver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Fix accounts that registered as agent/company but ENUM forced them to user:
UPDATE users u
INNER JOIN agents a ON a.user_id = u.id
SET u.role = 'agent'
WHERE u.role <> 'agent';

UPDATE users u
INNER JOIN private_companies c ON c.user_id = u.id
SET u.role = 'company'
WHERE u.role <> 'company';

-- Pricing:
-- landlord/dealer  = dealers flow (K300 after free trial)
-- agent            = agents table (K20)
-- private company  = private_companies table (K300)
