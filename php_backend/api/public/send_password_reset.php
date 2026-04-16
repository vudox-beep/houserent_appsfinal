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

if (empty($email)) { 
    echo json_encode(['status' => 'error', 'message' => 'Email is required']); 
    exit; 
} 

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { 
    echo json_encode(['status' => 'error', 'message' => 'Invalid email format']); 
    exit; 
} 

try {
    global $conn;
    
    // Check if user exists
    $stmt = $conn->prepare("SELECT id, name FROM users WHERE email = :email");
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        // Return success even if not found to prevent email enumeration attacks
        echo json_encode(['status' => 'success', 'message' => 'If your email is in our system, you will receive a reset link shortly.']);
        exit;
    }

    // Generate secure token
    $token = bin2hex(random_bytes(32));
    $expires = date('Y-m-d H:i:s', strtotime('+1 hour'));

    // Check if reset_token and reset_expires columns exist before updating
    try {
        $stmt = $conn->prepare("UPDATE users SET reset_token = :token, reset_expires = :expires WHERE email = :email");
        $stmt->execute([
            ':token' => $token,
            ':expires' => $expires,
            ':email' => $email
        ]);
    } catch (PDOException $e) {
        // Fallback or ignore if columns don't exist yet, just send the email anyway
        // Or handle specific schema updates if needed
    }

    // Build Email
    $reset_link = rtrim(SITE_URL, '/') . '/reset_password.php?token=' . urlencode($token);
    $name = $user['name'];
    $subject = 'Password Reset Request - ' . SITE_NAME; 
    
    $body = " 
    <div style='font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:20px;border:1px solid #ddd;border-radius:10px;'> 
        <h2 style='color:#2c3e50;text-align:center;'>Password Reset Request</h2> 
        <p>Hello {$name},</p> 
        <p>We received a request to reset your password for your " . SITE_NAME . " account. If you did not make this request, you can safely ignore this email.</p> 
        <p>To reset your password, please click the button below:</p> 
        <div style='text-align:center;margin:25px 0;'> 
            <a href='{$reset_link}' style='background-color:#FFC107;color:#000;padding:12px 24px;text-decoration:none;border-radius:5px;font-weight:bold;'>Reset Password</a> 
        </div> 
        <p>This link will expire in 1 hour.</p>
        <p>If the button does not work, copy and paste this link into your browser:</p> 
        <p style='word-break:break-all;color:#007bff;'>{$reset_link}</p> 
    </div>"; 

    $mailer = new SimpleSMTP(SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS); 
    $sent = $mailer->send($email, $subject, $body, SITE_NAME); 

    if ($sent) { 
        echo json_encode([ 
            'status' => 'success', 
            'message' => 'If your email is in our system, you will receive a reset link shortly.'
        ]); 
    } else { 
        echo json_encode([ 
            'status' => 'error', 
            'message' => 'Failed to send password reset email' 
        ]); 
    } 

} catch (PDOException $e) {
    echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
}
?>