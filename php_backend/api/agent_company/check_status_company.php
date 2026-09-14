<?php
/**
 * Private company check status — COPY of dealer/check_status.php (original left untouched).
 * Folder: php_backend/api/agent_company/check_status_company.php
 *
 * Uses `private_companies` table (not dealers). Role must be company.
 * Fee: K300/month. Extra action: save_company_details.
 * Protected: Bearer auth, token user only, rate limits, load-safe queries.
 */
ob_start();
ini_set('display_errors', '0');
error_reporting(E_ALL);
@set_time_limit(30);

header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../auth.php';
require_once __DIR__ . '/helpers.php';

$limiterPath = __DIR__ . '/../includes/RateLimiter.php';
if (is_file($limiterPath)) {
    require_once $limiterPath;
}

function hr_company_status_json(array $payload, int $code = 200): void
{
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($payload);
    exit;
}

function hr_company_client_ip(): string
{
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        return (string) $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
    if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        return trim(explode(',', (string) $_SERVER['HTTP_X_FORWARDED_FOR'])[0]);
    }
    return (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
}

try {
    if (!isset($conn) || !($conn instanceof PDO)) {
        if (class_exists('Database')) {
            $conn = (new Database())->connect();
        }
    }
    if (!($conn instanceof PDO)) {
        hr_company_status_json(['status' => 'error', 'message' => 'Database connection failed'], 500);
    }
} catch (Throwable $e) {
    hr_company_status_json(['status' => 'error', 'message' => 'Database connection failed'], 500);
}

$ip = hr_company_client_ip();
if (class_exists('RateLimiter')) {
    $limiter = new RateLimiter(60, 60);
    if (!$limiter->check($ip . '_check_status_company')) {
        hr_company_status_json([
            'status' => 'error',
            'message' => 'Too many requests. Please slow down and try again.',
        ], 429);
    }
}

$authUser = authorize(['company', 'admin']);
$tokenUserId = (int) $authUser['id'];

if (class_exists('RateLimiter')) {
    $userLimiter = new RateLimiter(120, 60);
    if (!$userLimiter->check('company_status_uid_' . $tokenUserId)) {
        hr_company_status_json([
            'status' => 'error',
            'message' => 'Too many requests for this account. Please wait a moment.',
        ], 429);
    }
}

hr_ac_ensure_tables($conn);

$contentType = (string) ($_SERVER['CONTENT_TYPE'] ?? $_SERVER['HTTP_CONTENT_TYPE'] ?? '');
$isMultipart = stripos($contentType, 'multipart/form-data') !== false;
$data = [];
if ($isMultipart) {
    $data = $_POST;
} else {
    $raw = file_get_contents('php://input');
    if (is_string($raw) && $raw !== '') {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            $data = $decoded;
        }
    }
    if (empty($data) && !empty($_POST)) {
        $data = $_POST;
    }
    if (empty($data) && !empty($_GET)) {
        $data = $_GET;
    }
}

$action = (string) ($data['action'] ?? $_POST['action'] ?? $_GET['action'] ?? '');
$user_id = $tokenUserId;

if ($user_id < 1) {
    hr_company_status_json(['status' => 'error', 'message' => 'User ID required', 'is_locked' => true], 401);
}

try {
    if ($action === 'save_company_details') {
        if (class_exists('RateLimiter')) {
            $saveLimiter = new RateLimiter(20, 900);
            if (!$saveLimiter->check('company_save_' . $user_id)) {
                hr_company_status_json([
                    'status' => 'error',
                    'message' => 'Too many save attempts. Please try again later.',
                ], 429);
            }
        }

        $companyName = trim((string) ($data['company_name'] ?? ''));
        $regNo = trim((string) ($data['company_reg_no'] ?? ''));
        $address = trim((string) ($data['company_address'] ?? ''));
        $contact = trim((string) ($data['company_contact'] ?? ''));

        if ($companyName === '' || $regNo === '' || $address === '' || $contact === '') {
            hr_company_status_json([
                'status' => 'error',
                'message' => 'Company name, registration number, address, and contact are required.',
            ]);
        }
        if (strlen($companyName) > 191 || strlen($regNo) > 100 || strlen($address) > 255 || strlen($contact) > 100) {
            hr_company_status_json(['status' => 'error', 'message' => 'One or more fields are too long.']);
        }

        $stmt = $conn->prepare(
            'UPDATE private_companies
             SET company_name = ?, company_reg_no = ?, company_address = ?, company_contact = ?,
                 company_details_complete = 1
             WHERE user_id = ?'
        );
        $stmt->execute([$companyName, $regNo, $address, $contact, $user_id]);

        hr_company_status_json([
            'status' => 'success',
            'message' => 'Company details saved. Please pay K300 to activate your monthly plan.',
            'company_details_complete' => true,
            'subscription_fee' => 300,
            'needs_company_details' => false,
        ]);
    }

    if ($action === 'check_email_verification') {
        $stmt = $conn->prepare('SELECT verification_token FROM users WHERE id = ? AND role = ? LIMIT 1');
        $stmt->execute([$user_id, 'company']);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($user) {
            hr_company_status_json([
                'status' => 'success',
                'is_verified' => empty($user['verification_token']),
            ]);
        }
        hr_company_status_json(['status' => 'error', 'message' => 'User not found']);
    }

    if ($action === 'check_dealer_verification' || $action === 'check_company_verification') {
        $stmt = $conn->prepare("SELECT identity_verified FROM users WHERE id = ? AND role = 'company' LIMIT 1");
        $stmt->execute([$user_id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            hr_company_status_json([
                'status' => 'success',
                'identity_verified' => (bool) $row['identity_verified'],
            ]);
        }
        hr_company_status_json(['status' => 'error', 'message' => 'Company not found']);
    }

    // Same upload flow as dealer/check_status.php (folder + DB update), role = company only.
    if ($action === 'upload_verification') {
        if (!isset($_FILES['document']) || $_FILES['document']['error'] !== UPLOAD_ERR_OK) {
            $err = $_FILES['document']['error'] ?? 'NO_FILE';
            hr_company_status_json([
                'status' => 'error',
                'message' => "Please upload a valid document. Error code: $err",
            ]);
        }

        $documentRoot = rtrim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''), '/');
        $uploadDir = $documentRoot . '/assets/images/dealer_docs/';

        if ($documentRoot === '' || !is_dir($documentRoot . '/assets/')) {
            $uploadDir = __DIR__ . '/../../../assets/images/dealer_docs/';
        }

        if (!is_dir($uploadDir)) {
            if (!mkdir($uploadDir, 0755, true)) {
                hr_company_status_json(['status' => 'error', 'message' => 'Failed to create upload directory.']);
            }
        }

        $fileExtension = strtolower(pathinfo($_FILES['document']['name'], PATHINFO_EXTENSION));
        $allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

        if (!in_array($fileExtension, $allowedExtensions)) {
            hr_company_status_json([
                'status' => 'error',
                'message' => 'Invalid file format. Only JPG, PNG, and PDF are allowed.',
            ]);
        }

        $fileName = 'verify_' . $user_id . '_' . time() . '.' . $fileExtension;
        $absoluteTargetPath = $uploadDir . $fileName;

        if (move_uploaded_file($_FILES['document']['tmp_name'], $absoluteTargetPath)) {
            chmod($absoluteTargetPath, 0644);
            $dbPath = 'assets/images/dealer_docs/' . $fileName;

            $stmt = $conn->prepare(
                "UPDATE users SET verification_doc = ?, identity_verified = 0 WHERE id = ? AND role = 'company'"
            );

            if ($stmt->execute([$dbPath, $user_id])) {
                hr_company_status_json([
                    'status' => 'success',
                    'message' => 'Verification document uploaded successfully. Please wait for admin approval.',
                    'document_url' => 'https://houseforrent.site/' . $dbPath,
                ]);
            }
            hr_company_status_json(['status' => 'error', 'message' => 'Failed to update database record']);
        }

        hr_company_status_json([
            'status' => 'error',
            'message' => 'Failed to save file. Ensure folder permissions are correct.',
        ]);
    }

    // Default dashboard status (from private_companies)
    $stmtUser = $conn->prepare(
        "SELECT name, role, identity_verified, verification_doc FROM users WHERE id = ? AND role = 'company' LIMIT 1"
    );
    $stmtUser->execute([$user_id]);
    $user = $stmtUser->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        hr_company_status_json(['status' => 'error', 'message' => 'User not found', 'is_locked' => true]);
    }

    $stmt = $conn->prepare(
        'SELECT * FROM private_companies WHERE user_id = ? LIMIT 1'
    );
    $stmt->execute([$user_id]);
    $companyData = $stmt->fetch(PDO::FETCH_ASSOC);

    $sub_status = 'inactive';
    $expiry = null;
    $detailsComplete = false;
    $fee = 300.0;

    if ($companyData) {
        $sub_status = strtolower(trim((string) ($companyData['subscription_status'] ?? 'inactive')));
        $expiry = $companyData['subscription_expiry'];
        $detailsComplete = (int) ($companyData['company_details_complete'] ?? 0) === 1;
        $fee = (float) ($companyData['monthly_fee'] ?? 300);

        if ($sub_status !== 'active' && !empty($expiry)) {
            if ($expiry !== '0000-00-00 00:00:00' && strtotime((string) $expiry) > time()) {
                $sub_status = 'active';
                $conn->prepare("UPDATE private_companies SET subscription_status = 'active' WHERE user_id = ?")
                    ->execute([$user_id]);
            }
        } elseif ($sub_status === 'active' && !empty($expiry)) {
            if ($expiry !== '0000-00-00 00:00:00' && strtotime((string) $expiry) < time()) {
                $sub_status = 'expired';
                $conn->prepare("UPDATE private_companies SET subscription_status = 'expired' WHERE user_id = ?")
                    ->execute([$user_id]);
            }
        }
    }

    $identity_status = 'unverified';
    $identity_message = 'Please upload your ID to verify your account.';
    if ((int) $user['identity_verified'] === 1) {
        $identity_status = 'verified';
        $identity_message = 'Your identity is verified.';
    } elseif ((int) $user['identity_verified'] === 2) {
        $identity_status = 'rejected';
        $identity_message = 'Your identity verification was rejected. Please re-upload your document.';
    } elseif ((int) $user['identity_verified'] === 0 && !empty($user['verification_doc'])) {
        $identity_status = 'pending';
        $identity_message = 'Your identity document is pending admin approval.';
    }

    $is_payment_locked = ($sub_status !== 'active');
    $is_identity_locked = ($identity_status === 'unverified' || $identity_status === 'rejected');
    $is_locked = $is_payment_locked || !$detailsComplete;
    $lock_message = '';
    if (!$detailsComplete) {
        $lock_message = 'Please complete your company details, then pay K300/month to continue.';
    } elseif ($sub_status === 'expired') {
        $lock_message = 'Your company subscription has expired. Please pay K300 to continue.';
    } elseif ($is_payment_locked) {
        $lock_message = 'Your company subscription is inactive. Please pay K300/month to continue.';
    }

    $plan_name = ($sub_status === 'active') ? 'Company Pro' : 'Company Plan';

    $active_tenants = 0;
    try {
        $stmtTenants = $conn->prepare(
            "SELECT COUNT(*) as total FROM rentals WHERE dealer_id = ? AND status = 'active'"
        );
        $stmtTenants->execute([$user_id]);
        $active_tenants = (int) (($stmtTenants->fetch(PDO::FETCH_ASSOC)['total'] ?? 0));
    } catch (Throwable $e) {
    }

    $total_views = 0;
    try {
        $stmtViews = $conn->prepare('SELECT SUM(views) as total FROM properties WHERE dealer_id = ?');
        $stmtViews->execute([$user_id]);
        $total_views = (int) (($stmtViews->fetch(PDO::FETCH_ASSOC)['total'] ?? 0));
    } catch (Throwable $e) {
    }

    $recent_payments = [];
    try {
        $stmtPayments = $conn->prepare(
            "SELECT id, reference, amount, currency, status, payment_method, message as description, created_at, updated_at
             FROM transactions
             WHERE user_id = ?
             ORDER BY created_at DESC
             LIMIT 5"
        );
        $stmtPayments->execute([$user_id]);
        $recent_payments = $stmtPayments->fetchAll(PDO::FETCH_ASSOC) ?: [];
    } catch (Throwable $e) {
        $recent_payments = [];
    }

    hr_company_status_json([
        'status' => 'success',
        'is_dealer' => false,
        'is_company' => true,
        'role' => 'company',
        'name' => $user['name'],
        'plan_name' => $plan_name,
        'subscription_status' => $sub_status,
        'subscription_expiry' => $expiry,
        'subscription_fee' => $fee,
        'company_name' => $companyData['company_name'] ?? null,
        'company_reg_no' => $companyData['company_reg_no'] ?? null,
        'company_address' => $companyData['company_address'] ?? null,
        'company_contact' => $companyData['company_contact'] ?? null,
        'company_details_complete' => $detailsComplete,
        'needs_company_details' => !$detailsComplete,
        'identity_verified' => $user['identity_verified'],
        'verification_document' => $user['verification_doc'],
        'identity_status' => $identity_status,
        'identity_message' => $identity_message,
        'is_payment_locked' => $is_payment_locked,
        'is_identity_locked' => $is_identity_locked,
        'active_tenants' => $active_tenants,
        'total_views' => $total_views,
        'recent_payments' => $recent_payments,
        'is_locked' => $is_locked,
        'lock_message' => $lock_message,
    ]);
} catch (Throwable $e) {
    hr_company_status_json([
        'status' => 'error',
        'message' => 'Database error',
    ], 500);
}
