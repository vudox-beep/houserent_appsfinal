<?php
/**
 * Private company registration (separate from landlord/dealer register.php).
 * POST /php_backend/api/agent_company/register_company.php
 *
 * Creates users.role = 'company' + row in `private_companies` table.
 * Same panel in the app; monthly fee K300. Company details completed after login.
 */
ob_start();
header('Content-Type: application/json; charset=UTF-8');

try {
    $bootstrap = __DIR__ . '/../includes/site_bootstrap.php';
    $helpers = __DIR__ . '/../includes/registration_helpers.php';
    $acHelpers = __DIR__ . '/helpers.php';
    $limiter = __DIR__ . '/../includes/RateLimiter.php';
    $cors = __DIR__ . '/../cors.php';

    foreach ([$bootstrap, $helpers, $acHelpers, $limiter] as $file) {
        if (!is_file($file)) {
            throw new RuntimeException('Missing: ' . basename($file));
        }
    }

    require_once $bootstrap;
    require_once $helpers;
    require_once $acHelpers;
    hr_api_bootstrap();
    require_once $cors;
    require_once $limiter;
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Company registration unavailable.',
        'error' => $e->getMessage(),
    ]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    hr_json_error('Invalid request method', 405);
}

global $conn;
hr_ac_ensure_tables($conn);

$ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
} elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $ip = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'])[0]);
}

$limiter = new RateLimiter(8, 900);
if ($limiter->isBlocked($ip . '_register_company')) {
    hr_json_error('Too many registration attempts. Please try again later.');
}

$data = json_decode(file_get_contents('php://input'), true);
if (!is_array($data)) {
    $data = $_POST;
}

$name = trim((string) ($data['name'] ?? ''));
$email = strtolower(trim((string) ($data['email'] ?? '')));
$password = (string) ($data['password'] ?? '');
$confirmPassword = (string) ($data['confirm_password'] ?? $password);
$phone = trim((string) ($data['phone'] ?? ''));
$referralCode = strtoupper(trim((string) ($data['referral_code'] ?? '')));

if ($name === '' || $email === '' || $password === '') {
    hr_json_error('Name, email, and password are required');
}
if ($phone === '') {
    hr_json_error('Phone number is required');
}
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    hr_json_error('Please use a valid email address');
}
if ($password !== $confirmPassword) {
    hr_json_error('Passwords do not match');
}
if (strlen($password) < 8) {
    hr_json_error('Password must be at least 8 characters');
}

$referrer = null;
if ($referralCode !== '') {
    $referrer = hr_find_dealer_by_referral($conn, $referralCode);
    if (!$referrer) {
        hr_json_error('Invalid referral code. Please check and try again.');
    }
}

try {
    $exists = $conn->prepare('SELECT id FROM users WHERE email = :email LIMIT 1');
    $exists->execute([':email' => $email]);
    if ($exists->fetchColumn()) {
        $limiter->record($ip . '_register_company');
        hr_json_error('Email already registered');
    }

    $token = bin2hex(random_bytes(32));
    $tokenExpiry = date('Y-m-d H:i:s', strtotime('+24 hours'));

    $conn->beginTransaction();

    $userId = hr_ac_create_user($conn, [
        'name' => $name,
        'email' => $email,
        'password' => $password,
        'role' => 'company',
        'phone' => $phone,
        'verification_token' => $token,
        'token_expiry' => $tokenExpiry,
    ]);

    // No free trial — K300 after company details.
    $companyStmt = $conn->prepare(
        'INSERT INTO private_companies
         (user_id, company_details_complete, subscription_status, subscription_expiry, monthly_fee)
         VALUES (:user_id, 0, \'inactive\', NULL, 300.00)'
    );
    $companyStmt->execute([':user_id' => $userId]);

    if ($referrer && !empty($referrer['id'])) {
        try {
            $attach = $conn->prepare(
                'UPDATE users SET referred_by_user_id = :referrer, referral_registered_at = NOW()
                 WHERE id = :id AND referral_registered_at IS NULL'
            );
            $attach->execute([
                ':referrer' => (int) $referrer['id'],
                ':id' => $userId,
            ]);
        } catch (Throwable $e) {
            // optional
        }
    }

    $conn->commit();

    $emailSent = hr_send_registration_verification_email($email, $name, $token);
    $payload = [
        'user_id' => $userId,
        'role' => 'company',
        'subscription_fee' => 300,
        'needs_company_details' => true,
    ];

    if ($emailSent) {
        hr_json_success(
            'Company registration successful! Please check your email to verify your account. After login you will complete company details and pay K300/month.',
            $payload
        );
    }

    hr_json_success(
        'Company registration successful, but failed to send email. Use resend verification on the login screen.',
        $payload
    );
} catch (Throwable $e) {
    if ($conn instanceof PDO && $conn->inTransaction()) {
        $conn->rollBack();
    }
    hr_json_error('Server error', 500, $e->getMessage());
}
