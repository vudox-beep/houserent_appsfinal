<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../db.php';
require_once '../includes/SimpleMailer.php';

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

$action = $data['action'] ?? '';
$site_url = "https://houseforrent.site/php_backend/api/auth";
$site_name = "HouseRent Africa";

if ($action === 'forgot_password') {
    // --- FORGOT PASSWORD ---
    $email = $data['email'] ?? '';
    
    if (empty($email)) {
        echo json_encode(['status' => 'error', 'message' => 'Email is required']);
        exit;
    }

    $stmt = $conn->prepare("SELECT id FROM users WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($user) {
        $token = bin2hex(random_bytes(32));
        $expiry = date('Y-m-d H:i:s', strtotime('+1 hour'));

        $upd = $conn->prepare("UPDATE users SET reset_token = ?, reset_expires = ? WHERE id = ?");
        if ($upd->execute([$token, $expiry, $user['id']])) {
            $resetLink = $site_url . "/reset_password.php?token=" . $token;
            
            $subject = "Reset Your Password - " . $site_name;
            $body = "
            <div style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;'>
                <h2 style='color: #333;'>Password Reset Request</h2>
                <p>Hi,</p>
                <p>We received a request to reset your password. Click the button below to create a new password:</p>
                <div style='text-align: center; margin: 30px 0;'>
                    <a href='$resetLink' style='background-color: #fbbf24; color: #000; padding: 12px 25px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block;'>Reset Password</a>
                </div>
                <p>If the button doesn't work, copy and paste this link into your browser:</p>
                <p style='word-break: break-all; color: #666; font-size: 14px;'>$resetLink</p>
                <p>This link expires in 1 hour.</p>
                <p>If you didn't ask for this, please ignore this email.</p>
            </div>
            ";

            $mailer = new SimpleMailer();
            if ($mailer->send($email, $subject, $body)) {
                echo json_encode(['status' => 'success', 'message' => 'Password reset link sent to your email.']);
            } else {
                echo json_encode(['status' => 'error', 'message' => 'Failed to send email. Please try again later.']);
            }
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Database error. Could not set token.']);
        }
    } else {
        // For security, always return success even if email doesn't exist
        echo json_encode(['status' => 'success', 'message' => 'If your email is registered, a reset link has been sent.']);
    }

} elseif ($action === 'resend_verification') {
    // --- RESEND EMAIL VERIFICATION ---
    $email = $data['email'] ?? '';
    
    if (empty($email)) {
        echo json_encode(['status' => 'error', 'message' => 'Email is required']);
        exit;
    }
    
    $stmt = $conn->prepare("SELECT id, name, is_verified, verification_token FROM users WHERE email = ?");
    $stmt->execute([$email]);
    $u = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($u) {
        if (isset($u['is_verified']) && $u['is_verified'] == 1) {
            echo json_encode(['status' => 'error', 'message' => 'Account is already verified.']);
            exit;
        }
        
        $token = bin2hex(random_bytes(32));
        $expiry = date('Y-m-d H:i:s', strtotime('+24 hours'));
        
        $upd = $conn->prepare("UPDATE users SET verification_token = ?, token_expiry = ? WHERE id = ?");
        $upd->execute([$token, $expiry, $u['id']]);
        
        $verifyLink = $site_url . "/verify_email.php?token=" . $token;
        $subject = "Verify Your Account - " . $site_name;
        $name = htmlspecialchars($u['name']);
        
        $body = "
        <div style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;'>
            <h2 style='color: #333;'>Welcome to " . $site_name . ", $name!</h2>
            <p>Please verify your email address to activate your account by clicking the button below:</p>
            <div style='text-align: center; margin: 30px 0;'>
                <a href='$verifyLink' style='background-color: #fbbf24; color: #000; padding: 12px 25px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block;'>Verify Email Address</a>
            </div>
            <p>If the button doesn't work, copy and paste this link into your browser:</p>
            <p style='word-break: break-all; color: #666; font-size: 14px;'>$verifyLink</p>
            <p>This link will expire in 24 hours.</p>
        </div>
        ";
        
        $mailer = new SimpleMailer();
        if ($mailer->send($email, $subject, $body)) {
            echo json_encode(['status' => 'success', 'message' => 'Verification email resent successfully.']);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Failed to send email.']);
        }
    } else {
        echo json_encode(['status' => 'error', 'message' => 'User not found.']);
    }

} else {
    echo json_encode(['status' => 'error', 'message' => 'Invalid action. Supported actions: forgot_password, resend_verification']);
}
?>