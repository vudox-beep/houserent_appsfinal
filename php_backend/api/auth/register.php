<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../db.php';
require_once '../auth.php';

// Handle preflight OPTIONS request for CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) $data = $_POST;

$name = $data['name'] ?? '';
$email = $data['email'] ?? '';
$password = $data['password'] ?? '';
$phone = $data['phone'] ?? '';
$role = $data['role'] ?? 'user';

if (empty($name) || empty($email) || empty($password)) {
    echo json_encode(['status' => 'error', 'message' => 'Name, email, and password are required']);
    exit;
}

try {
    // Check if user exists
    $stmt = $conn->prepare("SELECT id FROM users WHERE email = ?");
    $stmt->execute([$email]);
    if ($stmt->rowCount() > 0) {
        echo json_encode(['status' => 'error', 'message' => 'Email already registered']);
        exit;
    }

    $token = bin2hex(random_bytes(32));
    $expiry = date('Y-m-d H:i:s', strtotime('+24 hours'));
    $hashedPassword = password_hash($password, PASSWORD_BCRYPT);
    $userRole = ($role === 'dealer') ? 'dealer' : 'user';

    // Insert user
    $stmt = $conn->prepare("INSERT INTO users (name, email, password, role, phone, verification_token, token_expiry) VALUES (?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([$name, $email, $hashedPassword, $userRole, $phone, $token, $expiry]);
    $userId = $conn->lastInsertId();

    if ($userRole === 'dealer') {
        $stmt = $conn->prepare("INSERT INTO dealers (user_id, subscription_status) VALUES (?, 'inactive')");
        $stmt->execute([$userId]);
    }

    // Attempt to send verification email using SimpleSMTP
    require_once '../../config/config.php';
    require_once '../includes/SimpleSMTP.php';
    $mailer = new SimpleSMTP(SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS);
    
    $verifyLink = SITE_URL . "/php_backend/api/auth/verify_email.php?token=" . urlencode($token);
    $subject = "Verify Your Account - " . SITE_NAME;
    
    $body = "
    <div style='font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:20px;border:1px solid #ddd;border-radius:10px;'>
        <h2 style='color:#2c3e50;text-align:center;'>Welcome to " . SITE_NAME . ", $name!</h2>
        <p>Please verify your email address by clicking the button below:</p>
        <div style='text-align:center;margin:25px 0;'> 
            <a href='$verifyLink' style='display:inline-block;background-color:#FFC107;color:#000;padding:12px 24px;text-decoration:none;border-radius:5px;font-weight:bold;'>Verify Email Address</a>
        </div>
        <p>Or copy this link:</p>
        <p style='word-break:break-all;color:#007bff;'>$verifyLink</p>
    </div>
    ";
    
    if ($mailer->send($email, $subject, $body, SITE_NAME)) {
        echo json_encode([
            'status' => 'success',
            'message' => 'Registration successful. Please check your email to verify your account.'
        ]);
    } else {
        echo json_encode([
            'status' => 'success', // Still success because the account was created
            'message' => 'Registration successful, but we could not send the verification email. Please contact support.'
        ]);
    }

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Server error', 'error' => $e->getMessage()]);
}
?>