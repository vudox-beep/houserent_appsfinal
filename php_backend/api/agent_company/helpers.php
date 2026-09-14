<?php
/**
 * Helpers for Agent + Private Company (separate from dealers).
 * Does not alter or depend on dealer profile APIs.
 */

function hr_ac_ensure_tables(PDO $conn): void
{
    static $done = false;
    if ($done) {
        return;
    }
    $done = true;

    // users.role is often an ENUM without agent/company — expand it or inserts become "user".
    hr_ac_ensure_user_roles($conn);

    $conn->exec(
        "CREATE TABLE IF NOT EXISTS agents (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL UNIQUE,
            subscription_status VARCHAR(20) NOT NULL DEFAULT 'inactive',
            subscription_expiry DATETIME NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_agents_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    $conn->exec(
        "CREATE TABLE IF NOT EXISTS private_companies (
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    $conn->exec(
        "CREATE TABLE IF NOT EXISTS request_agent_messages (
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
}

/**
 * Ensure users.role can store agent + company.
 */
function hr_ac_ensure_user_roles(PDO $conn): void
{
    try {
        $col = $conn->query("SHOW COLUMNS FROM users LIKE 'role'")->fetch(PDO::FETCH_ASSOC);
        if (!$col) {
            return;
        }
        $type = strtolower((string) ($col['Type'] ?? ''));
        if (strpos($type, 'enum(') === 0) {
            if (strpos($type, "'agent'") === false || strpos($type, "'company'") === false) {
                $conn->exec(
                    "ALTER TABLE users
                     MODIFY COLUMN role ENUM('user','tenant','dealer','agent','company','driver','admin')
                     NOT NULL DEFAULT 'user'"
                );
            }
        }
    } catch (Throwable $e) {
        // Host may lack ALTER privilege — registration will fail loudly below.
    }
}

function hr_ac_create_user(PDO $conn, array $data): int
{
    hr_ac_ensure_user_roles($conn);

    $role = strtolower(trim((string) ($data['role'] ?? '')));
    if (!in_array($role, ['agent', 'company'], true)) {
        throw new RuntimeException('Invalid agent/company role');
    }

    $stmt = $conn->prepare(
        'INSERT INTO users
         (name, email, password, role, phone, whatsapp_number, verification_token, token_expiry, is_verified)
         VALUES
         (:name, :email, :password, :role, :phone, :whatsapp, :token, :expiry, :is_verified)'
    );
    $stmt->execute([
        ':name' => $data['name'],
        ':email' => $data['email'],
        ':password' => password_hash($data['password'], PASSWORD_DEFAULT),
        ':role' => $role,
        ':phone' => $data['phone'],
        ':whatsapp' => '',
        ':token' => $data['verification_token'],
        ':expiry' => $data['token_expiry'],
        ':is_verified' => 0,
    ]);

    $userId = (int) $conn->lastInsertId();
    if ($userId < 1) {
        throw new RuntimeException('Failed to create user');
    }

    // Confirm role stuck (ENUM without agent/company silently becomes empty/"user").
    $check = $conn->prepare('SELECT role FROM users WHERE id = ? LIMIT 1');
    $check->execute([$userId]);
    $savedRole = strtolower(trim((string) $check->fetchColumn()));
    if ($savedRole !== $role) {
        $conn->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);
        throw new RuntimeException(
            'Database users.role does not allow "' . $role .
            '". Run sql/agent_company_tables.sql (ALTER users.role) on the server.'
        );
    }

    return $userId;
}
