<?php

function hr_registration_verify_link(string $token): string
{
    $base = defined('SITE_URL') ? SITE_URL : 'https://houseforrent.site';
    return rtrim($base, '/') . '/verify_email.php?token=' . urlencode($token);
}

function hr_build_registration_verification_email(string $name, string $verifyLink): string
{
    $siteName = defined('SITE_NAME') ? SITE_NAME : 'HouseRent Africa';
    $safeName = htmlspecialchars($name, ENT_QUOTES, 'UTF-8');
    $safeLink = htmlspecialchars($verifyLink, ENT_QUOTES, 'UTF-8');

    return "
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body { font-family: Arial, sans-serif; background-color: #f8f9fa; margin: 0; padding: 0; }
            .email-container { max-width: 600px; margin: 20px auto; background-color: #ffffff; border-radius: 8px; overflow: hidden; border: 1px solid #e9ecef; }
            .header { background-color: #fbbf24; padding: 30px; text-align: center; }
            .content { padding: 40px 30px; color: #333333; line-height: 1.6; }
            .button { display: inline-block; background-color: #fbbf24; color: #000; font-weight: bold; padding: 16px 36px; text-decoration: none; border-radius: 6px; }
            .footer { background-color: #f8f9fa; padding: 20px; text-align: center; font-size: 12px; color: #6c757d; }
            .link-copy { margin-top: 20px; font-size: 12px; color: #999; word-break: break-all; }
        </style>
    </head>
    <body>
        <div class='email-container'>
            <div class='header'>
                <h1 style='margin:0;font-size:24px;color:#000;'>" . $siteName . "</h1>
            </div>
            <div class='content'>
                <h2 style='margin-top:0;'>Welcome, {$safeName}!</h2>
                <p>Thanks for signing up. Please verify your email to activate your account.</p>
                <div style='text-align:center;margin:30px 0;'>
                    <a href='{$safeLink}' class='button'>Verify Email Address</a>
                </div>
                <div class='link-copy'>{$safeLink}</div>
            </div>
            <div class='footer'>&copy; " . date('Y') . " {$siteName}</div>
        </div>
    </body>
    </html>";
}

function hr_send_registration_verification_email(string $email, string $name, string $token): bool
{
    $siteName = defined('SITE_NAME') ? SITE_NAME : 'HouseRent Africa';
    $verifyLink = hr_registration_verify_link($token);
    $subject = 'Verify Your Account - ' . $siteName;
    $body = hr_build_registration_verification_email($name, $verifyLink);

    // Prefer website SimpleMailer (same as website register.php) when available.
    $mailerCandidates = [];
    if (defined('SITE_URL')) {
        // Same directory as website config
        $configDir = null;
        try {
            if (function_exists('hr_find_website_config')) {
                $configDir = dirname(hr_find_website_config());
            }
        } catch (Throwable $e) {
            $configDir = null;
        }
        if ($configDir) {
            $mailerCandidates[] = dirname($configDir) . '/includes/SimpleMailer.php';
        }
    }
    $mailerCandidates[] = dirname(__DIR__, 3) . '/house/includes/SimpleMailer.php';
    $mailerCandidates[] = dirname(__DIR__, 2) . '/../includes/SimpleMailer.php';

    foreach ($mailerCandidates as $mailerPath) {
        $real = realpath($mailerPath);
        if ($real && is_file($real)) {
            require_once $real;
            if (class_exists('SimpleMailer')) {
                $mailer = new SimpleMailer();
                return $mailer->send($email, $subject, $body);
            }
        }
    }

    // Fallback: API SimpleSMTP using website SMTP_* constants
    require_once __DIR__ . '/SimpleSMTP.php';
    $mailer = new SimpleSMTP(SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS);
    return $mailer->send($email, $subject, $body, $siteName);
}

function hr_fetch_trial_settings(PDO $conn): array
{
    $enabled = true;
    $days = 30;
    try {
        $stmt = $conn->query(
            "SELECT setting_key, setting_value FROM settings
             WHERE setting_key IN ('enable_free_trial', 'free_trial_duration')"
        );
        $settings = $stmt->fetchAll(PDO::FETCH_KEY_PAIR);
        if (isset($settings['enable_free_trial'])) {
            $enabled = (bool) $settings['enable_free_trial'];
        }
        if (isset($settings['free_trial_duration'])) {
            $days = max(1, (int) $settings['free_trial_duration']);
        }
    } catch (Throwable $e) {
        // settings table optional
    }
    return ['enabled' => $enabled, 'days' => $days];
}

function hr_find_dealer_by_referral(PDO $conn, string $code): ?array
{
    if ($code === '') {
        return null;
    }
    $stmt = $conn->prepare(
        "SELECT id, name, role FROM users WHERE referral_code = :code LIMIT 1"
    );
    $stmt->execute([':code' => strtoupper($code)]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user || strtolower((string) $user['role']) !== 'dealer') {
        return null;
    }
    return $user;
}

function hr_register_app_user(PDO $conn, array $data): int
{
    $role = $data['role'];
    $isVerified = strtolower($role) === 'dealer' ? 0 : 1;

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
        ':is_verified' => $isVerified,
    ]);

    $userId = (int) $conn->lastInsertId();

    if ($role === 'driver') {
        $driverStmt = $conn->prepare(
            'INSERT INTO drivers (user_id, vehicle_type, vehicle_capacity, service_area)
             VALUES (:user_id, :vehicle_type, :vehicle_capacity, :service_area)'
        );
        $driverStmt->execute([
            ':user_id' => $userId,
            ':vehicle_type' => $data['vehicle_type'],
            ':vehicle_capacity' => $data['vehicle_capacity'],
            ':service_area' => $data['service_area'],
        ]);
    }

    if ($role === 'dealer') {
        $subStatus = $data['subscription_status'] ?? 'inactive';
        $subExpiry = $data['subscription_expiry'] ?? null;
        $dealerStmt = $conn->prepare(
            'INSERT INTO dealers (user_id, subscription_status, subscription_expiry)
             VALUES (:user_id, :status, :expiry)
             ON DUPLICATE KEY UPDATE subscription_status = :status, subscription_expiry = :expiry'
        );
        $dealerStmt->execute([
            ':user_id' => $userId,
            ':status' => $subStatus,
            ':expiry' => $subExpiry,
        ]);

        hr_ensure_dealer_referral_code($conn, $userId, $data['name']);

        if (!empty($data['referrer_id']) && (int) $data['referrer_id'] !== $userId) {
            $attach = $conn->prepare(
                'UPDATE users SET referred_by_user_id = :referrer, referral_registered_at = NOW()
                 WHERE id = :id AND referral_registered_at IS NULL'
            );
            $attach->execute([
                ':referrer' => (int) $data['referrer_id'],
                ':id' => $userId,
            ]);
        }
    }

    return $userId;
}

function hr_ensure_dealer_referral_code(PDO $conn, int $dealerId, string $dealerName): string
{
    $stmt = $conn->prepare('SELECT referral_code FROM users WHERE id = :id LIMIT 1');
    $stmt->execute([':id' => $dealerId]);
    $current = (string) ($stmt->fetchColumn() ?: '');
    if ($current !== '') {
        return $current;
    }

    $base = strtoupper(preg_replace('/[^A-Z0-9]/', '', substr($dealerName, 0, 4)));
    if ($base === '') {
        $base = 'DLR';
    }

    for ($i = 0; $i < 20; $i++) {
        $code = $base . str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        $check = $conn->prepare('SELECT id FROM users WHERE referral_code = :code LIMIT 1');
        $check->execute([':code' => $code]);
        if (!$check->fetchColumn()) {
            $upd = $conn->prepare('UPDATE users SET referral_code = :code WHERE id = :id');
            $upd->execute([':code' => $code, ':id' => $dealerId]);
            return $code;
        }
    }

    return $base;
}
