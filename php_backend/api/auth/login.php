<?php 
require_once '../cors.php'; 
require_once '../db.php'; 
require_once '../auth.php'; 

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { 
    http_response_code(405); 
    exit(); 
} 

$data = json_decode(file_get_contents("php://input")); 

if (!isset($data->email) || !isset($data->password)) { 
    http_response_code(400); 
    echo json_encode(["message" => "Incomplete data"]); 
    exit(); 
} 

try { 
    $stmt = $conn->prepare("SELECT * FROM users WHERE email = ?"); 
    $stmt->execute([$data->email]); 
    
    if ($stmt->rowCount() == 0) { 
        http_response_code(200); 
        echo json_encode([
            "status" => "error",
            "message" => "Invalid email or password",
            "code" => "invalid_credentials"
        ]); 
        exit(); 
    } 

    $user = $stmt->fetch(); 

    if (password_verify($data->password, $user['password'])) { 
        // Check if banned 
        if (isset($user['is_banned']) && $user['is_banned'] == 1) { 
            http_response_code(200); 
            echo json_encode([ 
                "status" => "error", 
                "message" => "Your account has been banned.", 
                "code" => "banned" 
            ]); 
            exit(); 
        } 

        // Check if email verified 
        // If verification_token is NOT null/empty, it means they haven't clicked the link in their email yet! 
        if (!empty($user['verification_token'])) { 
            http_response_code(200); 
            echo json_encode([ 
                "status" => "error", 
                "message" => "Please verify your email address before logging in.", 
                "code" => "email_unverified" 
            ]); 
            exit(); 
        }

        $sub_status = 'inactive'; 
        if ($user['role'] === 'dealer') { 
            $subStmt = $conn->prepare("SELECT subscription_status, subscription_expiry FROM dealers WHERE user_id = ?"); 
            $subStmt->execute([$user['id']]); 
            $dealerData = $subStmt->fetch(PDO::FETCH_ASSOC); 
            
            if ($dealerData) { 
                $sub_status = $dealerData['subscription_status']; 
                $expiry = $dealerData['subscription_expiry']; 
                if ($sub_status === 'active' && !empty($expiry) && strtotime($expiry) < time()) { 
                    $sub_status = 'expired'; 
                    $upd = $conn->prepare("UPDATE dealers SET subscription_status = 'expired' WHERE user_id = ?"); 
                    $upd->execute([$user['id']]); 
                } 
            } 
            // We no longer block login for inactive subscriptions. 
            // The frontend dashboard will handle the lockout UI. 
        } 

        $token = generateToken($user['id'], $user['role']); 
        
        http_response_code(200); 
        echo json_encode([ 
            "status" => "success", 
            "id" => $user['id'], 
            "name" => $user['name'], 
            "email" => $user['email'], 
            "role" => $user['role'], 
            "identity_verified" => $user['identity_verified'] ?? 0, 
            "subscription_status" => $sub_status, 
            "token" => $token, 
            "user" => [ 
                "id" => $user['id'], 
                "name" => $user['name'], 
                "email" => $user['email'], 
                "role" => $user['role'], 
                "identity_verified" => $user['identity_verified'] ?? 0, 
                "subscription_status" => $sub_status, 
                "token" => $token 
            ] 
        ]); 
    } else { 
        http_response_code(200); 
        echo json_encode([
            "status" => "error",
            "message" => "Invalid email or password",
            "code" => "invalid_credentials"
        ]); 
    } 
} catch (Exception $e) { 
    http_response_code(500); 
    echo json_encode(["message" => "Server error"]); 
} 
?>