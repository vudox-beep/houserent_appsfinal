<?php 
header('Content-Type: application/json'); 
header('Access-Control-Allow-Origin: *'); 
header('Access-Control-Allow-Methods: POST, OPTIONS'); 
header('Access-Control-Allow-Headers: Content-Type, Authorization'); 

$config_path = dirname(__FILE__) . '/../../config/config.php'; 
$smtp_path = dirname(__FILE__) . '/../../includes/SimpleSMTP.php'; 

require_once $config_path; 
require_once $smtp_path; 
require_once '../db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { 
    http_response_code(200); 
    exit(); 
} 

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { 
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method']); 
    exit; 
} 

$data = json_decode(file_get_contents('php://input'), true); 
if (empty($data)) { 
    $data = $_POST; 
} 

$email = trim($data['email'] ?? ''); 
$name = trim($data['name'] ?? 'User'); 
$verify_link = trim($data['verify_link'] ?? ''); 
$token = trim($data['verification_token'] ?? ''); 

if (empty($email)) { 
    echo json_encode(['status' => 'error', 'message' => 'Email is required']); 
    exit; 
} 

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { 
    echo json_encode(['status' => 'error', 'message' => 'Invalid email format']); 
    exit; 
} 

if (empty($verify_link) && !empty($token)) { 
    $verify_link = SITE_URL . '/php_backend/api/auth/verify_email.php?token=' . urlencode($token); 
} 

if (empty($verify_link)) { 
    // Lookup token in DB
    try {
        global $conn;
        $stmt = $conn->prepare("SELECT name, verification_token, email_verified FROM users WHERE email = :email");
        $stmt->execute([':email' => $email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user) {
            echo json_encode(['status' => 'error', 'message' => 'Email not found in our records']);
            exit;
        }
        
        if ($user['email_verified']) {
            echo json_encode(['status' => 'error', 'message' => 'Email is already verified']);
            exit;
        }
        
        $token = $user['verification_token'];
        $name = $user['name'] ?: $name;
        
        if (empty($token)) {
            // Generate a new token if they somehow don't have one
            $token = bin2hex(random_bytes(32));
            $expiry = date('Y-m-d H:i:s', strtotime('+24 hours'));
            $update = $conn->prepare("UPDATE users SET verification_token = ?, token_expiry = ? WHERE email = ?");
            $update->execute([$token, $expiry, $email]);
        }
        
        $verify_link = SITE_URL . '/php_backend/api/auth/verify_email.php?token=' . urlencode($token); 
    } catch (PDOException $e) {
        echo json_encode(['status' => 'error', 'message' => 'Database error']);
        exit;
    }
} 

if (empty($verify_link)) { 
    echo json_encode(['status' => 'error', 'message' => 'Verify link or verification token is required']); 
    exit; 
} 

$subject = 'Verify Your Email - ' . SITE_NAME; 
$body = " 
<div style='font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:20px;border:1px solid #ddd;border-radius:10px;'> 
    <h2 style='color:#2c3e50;text-align:center;'>Welcome to " . SITE_NAME . "</h2> 
    <p>Hello {$name},</p> 
    <p>Please verify your email address by clicking the button below:</p> 
    <div style='text-align:center;margin:25px 0;'> 
        <a href='{$verify_link}' style='background-color:#007bff;color:#fff;padding:12px 24px;text-decoration:none;border-radius:5px;font-weight:bold;'>Verify My Email</a> 
    </div> 
    <p>If the button does not work, copy and paste this link:</p> 
    <p style='word-break:break-all;color:#007bff;'>{$verify_link}</p> 
</div>"; 

$mailer = new SimpleSMTP(SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS); 
$sent = $mailer->send($email, $subject, $body, SITE_NAME); 

if ($sent) { 
    echo json_encode([ 
        'status' => 'success', 
        'message' => 'Verification email sent successfully', 
        'email' => $email 
    ]); 
} else { 
    echo json_encode([ 
        'status' => 'error', 
        'message' => 'Failed to send verification email' 
    ]); 
} 
?>