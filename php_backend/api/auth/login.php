<?php 
require_once '../cors.php'; 
require_once '../db.php'; 
require_once '../auth.php'; 

// --- Rate Limiting Start ---
require_once '../includes/RateLimiter.php';
// Max 5 FAILED attempts per 15 minutes. Successful logins never count.
$limiter = new RateLimiter(5, 900);

// Get Real IP to support Cloudflare/Proxies
$ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
} elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
    $ip = trim($ips[0]);
}

if ($limiter->isBlocked($ip . '_login')) {
    http_response_code(200); // Send 200 so Flutter can parse the JSON error easily
    echo json_encode([
        'status' => 'error', 
        'message' => 'Too many failed login attempts. Please try again in 15 minutes.',
        'code' => 'rate_limited'
    ]);
    exit();
}
// --- Rate Limiting End ---

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
        $limiter->record($ip . '_login'); // failed attempt
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
        } elseif ($user['role'] === 'agent') {
            try {
                $subStmt = $conn->prepare("SELECT subscription_status, subscription_expiry FROM agents WHERE user_id = ? LIMIT 1");
                $subStmt->execute([$user['id']]);
                $agentData = $subStmt->fetch(PDO::FETCH_ASSOC);
                if ($agentData) {
                    $sub_status = $agentData['subscription_status'] ?? 'inactive';
                    $expiry = $agentData['subscription_expiry'] ?? null;
                    if ($sub_status === 'active' && !empty($expiry) && strtotime((string)$expiry) < time()) {
                        $sub_status = 'expired';
                        $conn->prepare("UPDATE agents SET subscription_status = 'expired' WHERE user_id = ?")
                            ->execute([$user['id']]);
                    }
                }
            } catch (Throwable $e) {
                $sub_status = 'inactive';
            }
        } elseif ($user['role'] === 'company') {
            try {
                $subStmt = $conn->prepare("SELECT subscription_status, subscription_expiry FROM private_companies WHERE user_id = ? LIMIT 1");
                $subStmt->execute([$user['id']]);
                $companyData = $subStmt->fetch(PDO::FETCH_ASSOC);
                if ($companyData) {
                    $sub_status = $companyData['subscription_status'] ?? 'inactive';
                    $expiry = $companyData['subscription_expiry'] ?? null;
                    if ($sub_status === 'active' && !empty($expiry) && strtotime((string)$expiry) < time()) {
                        $sub_status = 'expired';
                        $conn->prepare("UPDATE private_companies SET subscription_status = 'expired' WHERE user_id = ?")
                            ->execute([$user['id']]);
                    }
                }
            } catch (Throwable $e) {
                $sub_status = 'inactive';
            }
        }

        // Added for drivers only — same email/password login as everyone else.
        $driver = null;
        if ($user['role'] === 'driver') {
            $drvStmt = $conn->prepare("SELECT vehicle_type, vehicle_capacity, vehicle_plate, service_area, availability_status, booking_tokens FROM drivers WHERE user_id = ? LIMIT 1");
            $drvStmt->execute([$user['id']]);
            $driver = $drvStmt->fetch(PDO::FETCH_ASSOC) ?: null;
        }

        $token = generateToken($user['id'], $user['role']); 
        
        $response = [ 
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
        ];

        // Extra fields only when this account is a driver.
        if ($driver !== null) {
            $response["driver"] = $driver;
            $response["user"]["driver"] = $driver;
        }

        $limiter->clear($ip . '_login'); // successful login resets the counter

        http_response_code(200); 
        echo json_encode($response); 
    } else { 
        $limiter->record($ip . '_login'); // failed attempt
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
