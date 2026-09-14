<?php
ob_start();
header('Content-Type: application/json; charset=UTF-8');

try {
    require_once __DIR__ . '/../includes/site_bootstrap.php';
    require_once __DIR__ . '/../includes/registration_helpers.php';
    hr_api_bootstrap();
} catch (Throwable $e) {
    hr_json_error(
        'Verification service unavailable. Could not load website config/config.php.',
        500,
        $e->getMessage()
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

$data = json_decode(file_get_contents('php://input'), true);
if (!is_array($data)) {
    $data = $_POST;
}

$email = strtolower(trim((string) ($data['email'] ?? '')));
$name = trim((string) ($data['name'] ?? 'User'));

if ($email === '') {
    hr_json_error('Email is required');
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    hr_json_error('Invalid email format');
}

try {
    $stmt = $conn->prepare(
        'SELECT name, verification_token, token_expiry FROM users WHERE email = :email LIMIT 1'
    );
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        hr_json_error('Email not found in our records');
    }

    if (empty($user['verification_token'])) {
        hr_json_error('Email is already verified');
    }

    $token = (string) $user['verification_token'];
    $name = $user['name'] ?: $name;

    $expired = !empty($user['token_expiry']) && strtotime($user['token_expiry']) < time();
    if ($expired || $token === '') {
        $token = bin2hex(random_bytes(32));
        $expiry = date('Y-m-d H:i:s', strtotime('+24 hours'));
        $update = $conn->prepare(
            'UPDATE users SET verification_token = ?, token_expiry = ? WHERE email = ?'
        );
        $update->execute([$token, $expiry, $email]);
    }

    if (hr_send_registration_verification_email($email, $name, $token)) {
        hr_json_success(
            'Verification email sent successfully. Check your inbox and spam folder.',
            ['email' => $email]
        );
    }

    hr_json_error('Failed to send verification email');
} catch (Throwable $e) {
    hr_json_error('Database error', 500, $e->getMessage());
}
