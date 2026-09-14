<?php
ob_start();
header('Content-Type: application/json; charset=UTF-8');

try {
    $bootstrap = __DIR__ . '/../includes/site_bootstrap.php';
    $helpers = __DIR__ . '/../includes/registration_helpers.php';
    $limiter = __DIR__ . '/../includes/RateLimiter.php';
    $cors = __DIR__ . '/../cors.php';

    if (!is_file($bootstrap)) {
        throw new RuntimeException('Missing file: api/includes/site_bootstrap.php — upload it.');
    }
    if (!is_file($helpers)) {
        throw new RuntimeException('Missing file: api/includes/registration_helpers.php — upload it.');
    }
    if (!is_file($limiter)) {
        throw new RuntimeException('Missing file: api/includes/RateLimiter.php — upload it.');
    }

    require_once $bootstrap;
    require_once $helpers;
    hr_api_bootstrap();
    require_once $cors;
    require_once $limiter;
} catch (Throwable $bootstrapError) {
    if (!function_exists('hr_json_error')) {
        http_response_code(500);
        echo json_encode([
            'status' => 'error',
            'message' => 'Registration service unavailable.',
            'error' => $bootstrapError->getMessage(),
        ]);
        exit;
    }
    hr_json_error(
        'Registration service unavailable.',
        500,
        $bootstrapError->getMessage()
    );
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    hr_json_error('Invalid request method', 405);
}

global $conn;

$ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
} elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $ip = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'])[0]);
}

$limiter = new RateLimiter(8, 900);
if ($limiter->isBlocked($ip . '_register')) {
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
$role = trim((string) ($data['role'] ?? 'user'));
$referralCode = strtoupper(trim((string) ($data['referral_code'] ?? '')));
$vehicleType = trim((string) ($data['vehicle_type'] ?? ''));
$vehicleCapacity = trim((string) ($data['vehicle_capacity'] ?? ''));
$serviceArea = trim((string) ($data['service_area'] ?? ''));

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

if (!in_array($role, ['user', 'dealer', 'driver'], true)) {
    hr_json_error('Please select a valid account type');
}

$referrer = null;
if ($role === 'dealer' && $referralCode !== '') {
    $referrer = hr_find_dealer_by_referral($conn, $referralCode);
    if (!$referrer) {
        hr_json_error('Invalid referral code. Please check and try again.');
    }
}

if ($role === 'driver' && ($vehicleType === '' || $vehicleCapacity === '' || $serviceArea === '')) {
    hr_json_error('Please tell us about your moving vehicle and service area.');
}

try {
    $exists = $conn->prepare('SELECT id FROM users WHERE email = :email LIMIT 1');
    $exists->execute([':email' => $email]);
    if ($exists->fetchColumn()) {
        $limiter->record($ip . '_register');
        hr_json_error('Email already registered');
    }

    $trial = hr_fetch_trial_settings($conn);
    $token = bin2hex(random_bytes(32));
    $expiry = date('Y-m-d H:i:s', strtotime('+24 hours'));

    $userId = hr_register_app_user($conn, [
        'name' => $name,
        'email' => $email,
        'password' => $password,
        'role' => $role,
        'phone' => $phone,
        'vehicle_type' => $vehicleType,
        'vehicle_capacity' => $vehicleCapacity,
        'service_area' => $serviceArea,
        'verification_token' => $token,
        'token_expiry' => $expiry,
        'subscription_status' => ($trial['enabled'] && $role === 'dealer') ? 'active' : 'inactive',
        'subscription_expiry' => ($trial['enabled'] && $role === 'dealer')
            ? date('Y-m-d H:i:s', strtotime('+' . $trial['days'] . ' days'))
            : null,
        'referrer_id' => $referrer['id'] ?? null,
    ]);

    $emailSent = hr_send_registration_verification_email($email, $name, $token);

    if ($emailSent) {
        hr_json_success(
            'Registration successful! Please check your email (including spam folder) to verify your account.',
            ['user_id' => $userId]
        );
    }

    hr_json_success(
        'Registration successful, but failed to send email. Use resend verification on the login screen.',
        ['user_id' => $userId]
    );
} catch (Throwable $e) {
    hr_json_error('Server error', 500, $e->getMessage());
}
