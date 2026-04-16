<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../../config/db.php';
require_once '../../auth.php';
require_once '../../includes/LencoAPI.php';

// Handle preflight OPTIONS request for CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method. Must be POST']);
    exit;
}

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) $data = $_POST;

$user_id = $data['user_id'] ?? '';
$action = $data['action'] ?? 'initiate'; // 'initiate' or 'verify'

if (empty($user_id)) {
    echo json_encode(['status' => 'error', 'message' => 'User ID is required']);
    exit;
}

$lenco = new LencoAPI();

// Configuration
$subscription_fee = 20; // e.g., ZMW 20
$currency = 'ZMW';

if ($action === 'initiate') {
    // --- INITIATE PAYMENT (Mobile Money Example) ---
    $phone = $data['phone'] ?? '';
    $operator = $data['operator'] ?? 'mtn'; // mtn, airtel, zamtel
    $country = $data['country'] ?? 'zm';
    
    // First get the user to pull their info (email, name) for Lenco
    $stmtUser = $conn->prepare("SELECT name, email, phone FROM users WHERE id = ?");
    $stmtUser->execute([$user_id]);
    $user = $stmtUser->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        echo json_encode(['status' => 'error', 'message' => 'User not found']);
        exit;
    }

    if (empty($phone)) {
        // Fallback to user profile phone if not provided in request
        $phone = $user['phone'] ?? '';
        if (empty($phone)) {
            echo json_encode(['status' => 'error', 'message' => 'Phone number is required for mobile money']);
            exit;
        }
    }
    
    $amount = $subscription_fee;
    
    // Use the getPaid method equivalent from backend by initiating a transaction
    // LencoAPI.php has initiateMobileMoney which creates a backend collection request.
    $response = $lenco->initiateMobileMoney($amount, $currency, $phone, $operator, $country);
    
    if (isset($response['status']) && $response['status'] === true) {
        // The reference is nested differently sometimes depending on Lenco API version.
        // Usually it's in data -> reference or data -> id
        $reference = $response['data']['reference'] ?? $response['data']['id'] ?? ('SUB-' . uniqid() . '-' . time());
        
        // Save pending transaction to DB
        try {
            $stmt = $conn->prepare("INSERT INTO payments (user_id, reference, amount, method, status, description) VALUES (?, ?, ?, 'mobile-money', 'pending', 'Dealer Subscription')");
            $stmt->execute([$user_id, $reference, $amount]);
        } catch (PDOException $e) {
            // Ignore if payments table doesn't exactly match, or log error
        }
        
        echo json_encode([
            'status' => 'success',
            'message' => 'Payment initiated. Please check your phone for the prompt.',
            'reference' => $reference,
            'lenco_response' => $response['data'] ?? []
        ]);
    } else {
        echo json_encode([
            'status' => 'error',
            'message' => $response['message'] ?? 'Failed to initiate payment'
        ]);
    }

} elseif ($action === 'verify') {
    // --- VERIFY PAYMENT ---
    $reference = $data['reference'] ?? '';
    
    if (empty($reference)) {
        echo json_encode(['status' => 'error', 'message' => 'Reference is required for verification']);
        exit;
    }
    
    $result = $lenco->verifyTransaction($reference);
    
    if (isset($result['status']) && $result['status'] === true) {
        $resData = $result['data'] ?? [];
        $status = strtolower($resData['status'] ?? 'pending');
        $message = "Payment status: " . ucfirst($status);
        
        // Update DB
        try {
            $stmt = $conn->prepare("UPDATE payments SET status = ? WHERE reference = ?");
            $stmt->execute([$status, $reference]);
        } catch (PDOException $e) {}
        
        if ($status === 'successful') {
            // Update User Subscription
            $expiry = date('Y-m-d H:i:s', strtotime('+30 days'));
            try {
                $upd = $conn->prepare("UPDATE dealers SET subscription_status = 'active', subscription_expiry = ? WHERE user_id = ?");
                $upd->execute([$expiry, $user_id]);
            } catch(Exception $e){}
            
            echo json_encode([
                'status' => 'success',
                'message' => 'Payment successful and subscription activated.',
                'payment_status' => 'successful'
            ]);
        } else {
            echo json_encode([
                'status' => 'pending',
                'message' => 'Payment is still ' . $status,
                'payment_status' => $status
            ]);
        }
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Unable to verify transaction']);
    }
} else {
    echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
}
?>