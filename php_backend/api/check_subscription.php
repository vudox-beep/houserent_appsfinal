<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once 'db.php';
require_once 'auth.php';

// Handle preflight OPTIONS request for CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) $data = $_POST;
if (!$data) $data = $_GET;

$user_id = $data['user_id'] ?? '';

// Fallback to token if user_id is not explicitly provided
if (empty($user_id)) {
    // If auth.php is included, verifyToken() might be available to extract user id
    if (function_exists('verifyToken')) {
        // Suppress the exit() inside verifyToken if it fails, or manually check headers
        $headers = apache_request_headers();
        if (isset($headers['Authorization'])) {
            $token = str_replace('Bearer ', '', $headers['Authorization']);
            $tokenParts = explode('.', $token);
            if (count($tokenParts) == 3) {
                $payload = json_decode(base64_decode($tokenParts[1]), true);
                if (isset($payload['id'])) {
                    $user_id = $payload['id'];
                }
            }
        }
    }
}

if (empty($user_id)) {
    echo json_encode(['status' => 'error', 'message' => 'User ID required', 'is_locked' => true]);
    exit;
}

// Check user role, identity verification, and name, and verification_doc
$stmtUser = $conn->prepare("SELECT name, role, identity_verified, verification_doc FROM users WHERE id = ?");
$stmtUser->execute([$user_id]);
$user = $stmtUser->fetch(PDO::FETCH_ASSOC);

if (!$user) {
    echo json_encode(['status' => 'error', 'message' => 'User not found', 'is_locked' => true]);
    exit;
}

if ($user['role'] !== 'dealer') {
    echo json_encode(['status' => 'success', 'message' => 'User is not a dealer', 'is_dealer' => false, 'is_locked' => false]);
    exit;
}

$stmt = $conn->prepare("SELECT subscription_status, subscription_expiry FROM dealers WHERE user_id = ?");
$stmt->execute([$user_id]);
$dealerData = $stmt->fetch(PDO::FETCH_ASSOC);

$sub_status = 'inactive';
$expiry = null;

if ($dealerData) {
    $sub_status = strtolower(trim((string)($dealerData['subscription_status'] ?? 'inactive'))); 
    $expiry = $dealerData['subscription_expiry'];
    
    // Check if expired using the robust !empty check provided by the user
    // AND auto-heal logic if status is empty but expiry is valid
    // We must ensure the expiry check is robust
    if ($sub_status !== 'active' && !empty($expiry)) {
        // If expiry is essentially '0000-00-00', ignore it
        if ($expiry !== '0000-00-00 00:00:00' && strtotime($expiry) > time()) {
            $sub_status = 'active';
            $upd = $conn->prepare("UPDATE dealers SET subscription_status = 'active' WHERE user_id = ?");
            $upd->execute([$user_id]);
        }
    } else if ($sub_status === 'active' && !empty($expiry)) {
        if ($expiry !== '0000-00-00 00:00:00' && strtotime($expiry) < time()) {
            $sub_status = 'expired';
            $upd = $conn->prepare("UPDATE dealers SET subscription_status = 'expired' WHERE user_id = ?");
            $upd->execute([$user_id]);
        }
    }
}

// Check identity verification state
$identity_status = 'unverified';
$identity_message = 'Please upload your ID to verify your account.';

if ($user['identity_verified'] == 1) {
    $identity_status = 'verified';
    $identity_message = 'Your identity is verified.';
} elseif ($user['identity_verified'] == 2) {
    $identity_status = 'rejected';
    $identity_message = 'Your identity verification was rejected. Please re-upload your document.';
} elseif ($user['identity_verified'] == 0 && !empty($user['verification_doc'])) {
    // If they have uploaded a doc but it's 0, it means it's pending admin review
    $identity_status = 'pending';
    $identity_message = 'Your identity document is pending admin approval.';
}

// Lock the app if they haven't paid OR if they are rejected/unverified
$is_payment_locked = ($sub_status !== 'active');
$is_identity_locked = ($identity_status === 'unverified' || $identity_status === 'rejected');

// General lock (true if either payment is bad OR identity is not verified/pending)
$is_locked = ($is_payment_locked || $is_identity_locked);

$lock_message = '';
if ($is_payment_locked) {
    $lock_message = 'Your subscription has expired or is inactive. Please make a payment to continue using the app.';
} elseif ($is_identity_locked) {
    $lock_message = $identity_message;
}

// Ensure recent_payments is available when returning the data, as the dashboard needs it!
$recent_payments = [];
try {
    $stmtPayments = $conn->prepare("
        SELECT id, reference, amount, currency, status, payment_method, message as description, created_at, updated_at
        FROM transactions
        WHERE user_id = ?
        ORDER BY created_at DESC
        LIMIT 5
    ");
    $stmtPayments->execute([$user_id]);
    $recent_payments = $stmtPayments->fetchAll(PDO::FETCH_ASSOC);
    if (!$recent_payments) {
        $recent_payments = [];
    }
} catch (PDOException $e) {
    $recent_payments = [];
}

// Fetch total active tenants (checking rentals table instead of tenants)
$active_tenants = 0;
try {
    $stmtTenants = $conn->prepare("SELECT COUNT(*) as total FROM rentals WHERE dealer_id = ? AND status = 'active'");
    $stmtTenants->execute([$user_id]);
    $tenantsData = $stmtTenants->fetch(PDO::FETCH_ASSOC);
    $active_tenants = $tenantsData['total'] ?? 0;
} catch (PDOException $e) {}

// Fetch total property views
$total_views = 0;
try {
    $stmtViews = $conn->prepare("SELECT SUM(views) as total FROM properties WHERE dealer_id = ?");
    $stmtViews->execute([$user_id]);
    $viewsData = $stmtViews->fetch(PDO::FETCH_ASSOC);
    $total_views = $viewsData['total'] ?? 0;
} catch (PDOException $e) {}

$plan_name = ($sub_status === 'active') ? 'Dealer Pro' : 'Free Trial';

echo json_encode([
    'status' => 'success',
    'is_dealer' => true,
    'name' => $user['name'],
    'plan_name' => $plan_name,
    'subscription_status' => $sub_status,
    'subscription_expiry' => $expiry,
    'identity_status' => $identity_status,
    'identity_message' => $identity_message,
    'is_payment_locked' => $is_payment_locked,
    'is_identity_locked' => $is_identity_locked,
    'is_locked' => $is_locked,
    'lock_message' => $lock_message,
    'recent_payments' => $recent_payments,
    'active_tenants' => $active_tenants,
    'total_views' => $total_views
]);
?>