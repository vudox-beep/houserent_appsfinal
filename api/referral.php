<?php 
 header('Content-Type: application/json'); 
 header('Access-Control-Allow-Origin: *'); 
 header('Access-Control-Allow-Methods: GET, POST, OPTIONS'); 
 header('Access-Control-Allow-Headers: Content-Type, Authorization'); 
 
 // Adjusted paths to reach php_backend/config
 require_once '../php_backend/config/config.php'; 
 require_once '../php_backend/config/db.php'; 
 
 if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { 
     http_response_code(200); 
     exit(); 
 } 
 
 $data = json_decode(file_get_contents('php://input'), true); 
 if (empty($data)) $data = $_POST; 
 if (empty($data)) $data = $_GET; 
 
 $action = strtolower(trim((string)($data['action'] ?? 'dashboard'))); 
 $user_id = $data['user_id'] ?? $_POST['user_id'] ?? $_GET['user_id'] ?? ''; 
 
 if (empty($user_id)) { 
     $headers = function_exists('getallheaders') ? getallheaders() : []; 
     $authorization = $headers['Authorization'] ?? $headers['authorization'] ?? ($_SERVER['HTTP_AUTHORIZATION'] ?? ''); 
 
     if (!empty($authorization) && stripos($authorization, 'Bearer ') === 0) { 
         $token = trim(substr($authorization, 7)); 
         $tokenParts = explode('.', $token); 
         if (count($tokenParts) === 3) { 
             $payload = json_decode(base64_decode($tokenParts[1]), true); 
             if (!empty($payload['id'])) { 
                 $user_id = $payload['id']; 
             } 
         } 
     } 
 } 
 
 if (empty($user_id)) { 
     echo json_encode([ 
         'status' => 'error', 
         'message' => 'User ID is required' 
     ]); 
     exit; 
 } 
 
 try { 
     $db = new Database(); 
     $conn = $db->connect(); 
 
     // Fetch User Info
     $stmtUser = $conn->prepare("SELECT id, name, email, role, referral_code FROM users WHERE id = ? LIMIT 1"); 
     $stmtUser->execute([(int)$user_id]); 
     $user = $stmtUser->fetch(PDO::FETCH_ASSOC); 
 
     if (!$user) { 
         echo json_encode([ 
             'status' => 'error', 
             'message' => 'User not found' 
         ]); 
         exit; 
     } 
 
     if (strtolower((string)$user['role']) !== 'dealer') { 
         echo json_encode([ 
             'status' => 'error', 
             'message' => 'Only dealer accounts can access referrals' 
         ]); 
         exit; 
     } 
 
     // Fetch Stats
     $stmtStats = $conn->prepare("
         SELECT 
             (SELECT COUNT(*) FROM users WHERE referred_by_user_id = ?) as total_referrals,
             (SELECT COUNT(*) FROM users WHERE referred_by_user_id = ? AND referral_registered_at IS NOT NULL) as successful_referrals,
             (SELECT COUNT(*) FROM users WHERE referred_by_user_id = ? AND referral_registered_at IS NULL) as pending_referrals,
             (SELECT IFNULL(SUM(amount), 0) FROM referral_rewards WHERE referrer_user_id = ?) as total_earnings,
             (SELECT COUNT(*) FROM referral_rewards WHERE referrer_user_id = ? AND reward_type = 'milestone_bonus') as milestone_awarded
     ");
     $stmtStats->execute([(int)$user_id, (int)$user_id, (int)$user_id, (int)$user_id, (int)$user_id]);
     $stats = $stmtStats->fetch(PDO::FETCH_ASSOC);
 
     // Fetch Referrals List
     $stmtRefs = $conn->prepare("
         SELECT id, name, email, created_at, referral_registered_at 
         FROM users 
         WHERE referred_by_user_id = ? 
         ORDER BY created_at DESC LIMIT 50
     ");
     $stmtRefs->execute([(int)$user_id]);
     $referrals = $stmtRefs->fetchAll(PDO::FETCH_ASSOC);
 
     // Fetch Rewards History
     $stmtRewards = $conn->prepare("
         SELECT r.*, u.name as referred_name, u.email as referred_email 
         FROM referral_rewards r
         LEFT JOIN users u ON r.referred_user_id = u.id
         WHERE r.referrer_user_id = ?
         ORDER BY r.created_at DESC LIMIT 50
     ");
     $stmtRewards->execute([(int)$user_id]);
     $rewards = $stmtRewards->fetchAll(PDO::FETCH_ASSOC);
 
     $referralLink = rtrim(SITE_URL, '/') . '/register.php?ref=' . urlencode((string)($user['referral_code'] ?? '')); 
     $shareMessage = "Grow your real estate business with HouseRent Africa! 🏠 Register as a dealer today to unlock unlimited listings, featured properties, and advanced analytics. Join the leading property platform in Zambia. Sign up here: " . $referralLink; 
 
     $mappedReferrals = array_map(function ($row) { 
         $isVerified = !empty($row['referral_registered_at']); 
         return [ 
             'id' => (int)$row['id'], 
             'name' => $row['name'], 
             'email' => $row['email'], 
             'joined_at' => $row['created_at'], 
             'verified_at' => $row['referral_registered_at'], 
             'status' => $isVerified ? 'verified' : 'pending' 
         ]; 
     }, $referrals); 
 
     $mappedRewards = array_map(function ($row) { 
         return [ 
             'id' => (int)$row['id'], 
             'reward_type' => $row['reward_type'], 
             'amount' => (float)$row['amount'], 
             'notes' => $row['notes'], 
             'referred_name' => $row['referred_name'] ?? null, 
             'referred_email' => $row['referred_email'] ?? null, 
             'created_at' => $row['created_at'] 
         ]; 
     }, $rewards); 
 
     echo json_encode([ 
         'status' => 'success', 
         'message' => 'Referral dashboard data fetched successfully', 
         'data' => [ 
             'dealer' => [ 
                 'id' => (int)$user['id'], 
                 'name' => $user['name'], 
                 'email' => $user['email'] 
             ], 
             'settings' => [ 
                 'currency' => defined('CURRENCY') ? CURRENCY : 'K', 
                 'subscription_commission_percent' => defined('REFERRAL_SUBSCRIPTION_COMMISSION_PERCENT') ? (float)REFERRAL_SUBSCRIPTION_COMMISSION_PERCENT : 10.0, 
                 'withdrawal_instructions' => 'To withdraw your referral earnings, please contact the administrator directly for processing.' 
             ], 
             'summary' => [ 
                 'referral_code' => $user['referral_code'] ?? '', 
                 'referral_link' => $referralLink, 
                 'share_message' => $shareMessage, 
                 'successful_referrals' => (int)$stats['successful_referrals'], 
                 'pending_referrals' => (int)$stats['pending_referrals'], 
                 'total_earnings' => (float)$stats['total_earnings'], 
                 'milestone_awarded' => (int)$stats['milestone_awarded'] >= 1 
             ], 
             'referrals' => $mappedReferrals, 
             'rewards' => $mappedRewards 
         ] 
     ]); 
 } catch (Exception $e) { 
     echo json_encode([ 
         'status' => 'error', 
         'message' => 'System error: ' . $e->getMessage() 
     ]); 
 } 
 ?>
