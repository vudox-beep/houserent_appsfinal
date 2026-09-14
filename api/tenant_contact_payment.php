<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once __DIR__ . '/../config/config.php';

// If LencoAPI is not found via include, use this embedded version
if (!class_exists('LencoAPI')) {
    class LencoAPI { 
        private $baseUrl; 
        private $apiKey; 

        public function __construct() { 
            $this->baseUrl = defined('LENCO_BASE_URL') ? rtrim(str_replace('`', '', LENCO_BASE_URL), '/') : 'https://api.lenco.co/access/v2'; 
            $this->apiKey = defined('LENCO_KEY') ? LENCO_KEY : ''; 
        } 

        private function getAuthorizationHeader() { 
            $key = (string) $this->apiKey; 
            $normalized = strtolower($key); 

            if ($key !== '' && strpos($normalized, 'bearer ') !== 0) { 
                return 'Bearer ' . $key; 
            } 

            return $key; 
        } 

        private function request($method, $endpoint, $data = []) { 
            $url = $this->baseUrl . $endpoint; 
            $ch = curl_init(); 
            
            $headers = [ 
                'Authorization: ' . $this->getAuthorizationHeader(), 
                'Content-Type: application/json', 
                'Accept: application/json' 
            ]; 

            curl_setopt($ch, CURLOPT_URL, $url); 
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); 
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers); 
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // For dev/localhost 

            if ($method === 'POST') { 
                curl_setopt($ch, CURLOPT_POST, 1); 
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data)); 
            } 

            $response = curl_exec($ch); 
            $error = curl_error($ch); 
            curl_close($ch); 

            if ($error) { 
                return ['status' => false, 'message' => $error]; 
            } 

            return json_decode($response, true); 
        } 

        public function normalizePhone($phone, $countryIso = 'zm') { 
            $digits = preg_replace('/\D+/', '', $phone); 
            
            // Extended African country codes 
            $codes = [ 
                'zm' => '260', 
                'mw' => '265', 
                'ke' => '254', 
                'ug' => '256', 
                'tz' => '255', 
                'rw' => '250', 
                'gh' => '233', 
                'ng' => '234', 
                'za' => '27', 
                'zw' => '263', 
                'bw' => '267', 
                'mz' => '258', 
                'ls' => '266', 
                'sz' => '266', 
                'na' => '264', 
                'ao' => '244', 
                'cd' => '243' 
            ]; 

            $countryCode = $codes[strtolower($countryIso)] ?? '260'; 

            // If number starts with country code, strip it 
            if (strpos($digits, $countryCode) === 0) { 
                $digits = substr($digits, strlen($countryCode)); 
            } 

            // Strip leading zero 
            if (strpos($digits, '0') === 0) { 
                $digits = ltrim($digits, '0'); 
            } 

            return $digits; 
        } 

        public function initiateMobileMoney($amount, $currency, $phone, $operator, $country = 'zm') { 
            $normalizedPhone = $this->normalizePhone($phone, $country); 
            
            // Correct payload structure for Lenco Mobile Money 
            $payload = [ 
                'amount' => number_format((float) $amount, 2, '.', ''), 
                'currency' => $currency, 
                'reference' => 'SUB-' . uniqid() . '-' . time(), 
                'type' => 'mobile-money', 
                'mobileMoneyDetails' => [ 
                    'country' => strtoupper($country), // ZM or MW 
                    'phone' => $normalizedPhone, 
                    'operator' => strtolower($operator), 
                ], 
                'bearer' => 'customer', 
            ]; 

            $response = $this->request('POST', '/collections/mobile-money', $payload); 
            
            // If response doesn't have reference but was successful, add our generated reference for tracking 
            if (isset($response['status']) && $response['status'] === true && !isset($response['data']['reference'])) { 
                $response['data']['reference'] = $payload['reference']; 
            } 
            
            return $response; 
        } 

        public function verifyTransaction($reference) { 
            return $this->request('GET', '/collections/status/' . $reference); 
        } 
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

try {
    $conn = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
        DB_USER,
        DB_PASS
    );
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $conn->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
} catch (PDOException $e) {
    header('Content-Type: application/json');
    echo json_encode([
        'status' => 'error',
        'message' => 'Database connection failed'
    ]);
    exit;
}

/**
 * Tenant Pro helpers — keep existing actions/response shapes.
 * Backstop: reconcile pending Lenco payments + block double pay when already active.
 */
function tcp_success_statuses() {
    return ['successful', 'success', 'completed', 'paid', 'approved'];
}

function tcp_is_success_status($status) {
    return in_array(strtolower(trim((string) $status)), tcp_success_statuses(), true);
}

function tcp_user_has_premium(PDO $conn, $userId) {
    $stmt = $conn->prepare(
        "SELECT id FROM premium_contacts WHERE user_id = ? AND status = 'active' LIMIT 1"
    );
    $stmt->execute([$userId]);
    return (bool) $stmt->fetch();
}

function tcp_ensure_pending_transaction(PDO $conn, $userId, $reference, $amount = 5.0, $currency = 'ZMW') {
    $reference = trim((string) $reference);
    if ($reference === '') {
        return;
    }
    $check = $conn->prepare('SELECT id FROM transactions WHERE reference = ? LIMIT 1');
    $check->execute([$reference]);
    if ($check->fetch()) {
        return;
    }
    try {
        $stmt = $conn->prepare(
            "INSERT INTO transactions (user_id, reference, amount, currency, status, payment_method, message)
             VALUES (?, ?, ?, ?, 'pending', 'mobile-money', 'Tenant Contact Access Fee')"
        );
        $stmt->execute([$userId, $reference, $amount, $currency]);
    } catch (Exception $e) {
        // Unique race is fine — another request inserted it.
    }
}

function tcp_activate_premium(PDO $conn, $userId, $reference, array $resData) {
    $amount = isset($resData['amount']) ? (float) $resData['amount'] : 5.00;
    $currency = $resData['currency'] ?? 'ZMW';
    $lenco_reference = $resData['lencoReference'] ?? ($resData['reference'] ?? $reference);
    $payment_type = $resData['type'] ?? 'mobile-money';

    $operator = null;
    $phone_number = null;
    $account_name = null;
    $operator_transaction_id = null;
    if (!empty($resData['mobileMoneyDetails']) && is_array($resData['mobileMoneyDetails'])) {
        $operator = $resData['mobileMoneyDetails']['operator'] ?? null;
        $phone_number = $resData['mobileMoneyDetails']['phone'] ?? null;
        $account_name = $resData['mobileMoneyDetails']['accountName'] ?? null;
        $operator_transaction_id = $resData['mobileMoneyDetails']['operatorTransactionId'] ?? null;
    }

    tcp_ensure_pending_transaction($conn, $userId, $reference, $amount, $currency);

    $stmt = $conn->prepare(
        "UPDATE transactions SET status = 'successful', lenco_reference = ? WHERE reference = ?"
    );
    $stmt->execute([$lenco_reference, $reference]);

    $checkPremium = $conn->prepare('SELECT id FROM premium_contacts WHERE user_id = ? LIMIT 1');
    $checkPremium->execute([$userId]);
    if (!$checkPremium->fetch()) {
        $stmtPremium = $conn->prepare(
            "INSERT INTO premium_contacts
                (user_id, transaction_reference, amount_paid, lenco_reference, payment_type, operator, phone_number, account_name, operator_transaction_id, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')"
        );
        $stmtPremium->execute([
            $userId,
            $reference,
            $amount,
            $lenco_reference,
            $payment_type,
            $operator,
            $phone_number,
            $account_name,
            $operator_transaction_id,
        ]);
    } else {
        $stmtPremium = $conn->prepare(
            "UPDATE premium_contacts
             SET status = 'active',
                 transaction_reference = ?,
                 amount_paid = ?,
                 lenco_reference = ?,
                 payment_type = ?,
                 operator = ?,
                 phone_number = ?,
                 account_name = ?,
                 operator_transaction_id = ?
             WHERE user_id = ?"
        );
        $stmtPremium->execute([
            $reference,
            $amount,
            $lenco_reference,
            $payment_type,
            $operator,
            $phone_number,
            $account_name,
            $operator_transaction_id,
            $userId,
        ]);
    }
}

/**
 * Settle one reference from a Lenco verify payload.
 * Pending/processing do NOT unlock access (avoids free unlock).
 * Successful settles are idempotent (safe to call again).
 *
 * @return array{ok:bool,status:string,message:string,has_paid:bool}
 */
function tcp_settle_from_lenco(PDO $conn, $userId, $reference, array $result) {
    if (!(isset($result['status']) && $result['status'] === true)) {
        return [
            'ok' => false,
            'status' => 'error',
            'message' => 'Verification failed',
            'has_paid' => tcp_user_has_premium($conn, $userId),
        ];
    }

    $resData = is_array($result['data'] ?? null) ? $result['data'] : [];
    $payStatus = strtolower((string) ($resData['status'] ?? ''));

    if (tcp_is_success_status($payStatus)) {
        try {
            tcp_activate_premium($conn, $userId, $reference, $resData);
        } catch (Exception $e) {
            // If already active from a parallel request, still report success.
            if (tcp_user_has_premium($conn, $userId)) {
                return [
                    'ok' => true,
                    'status' => 'success',
                    'message' => 'Payment already recorded',
                    'has_paid' => true,
                ];
            }
            return [
                'ok' => false,
                'status' => 'error',
                'message' => 'Could not save payment. Please retry verify.',
                'has_paid' => false,
            ];
        }

        return [
            'ok' => true,
            'status' => 'success',
            'message' => 'Payment successful',
            'has_paid' => true,
        ];
    }

    if (in_array($payStatus, ['pending', 'processing'], true)) {
        return [
            'ok' => false,
            'status' => $payStatus,
            'message' => 'Payment is ' . $payStatus,
            'has_paid' => tcp_user_has_premium($conn, $userId),
        ];
    }

    return [
        'ok' => false,
        'status' => $payStatus !== '' ? $payStatus : 'error',
        'message' => 'Payment is ' . ($payStatus !== '' ? $payStatus : 'unknown'),
        'has_paid' => tcp_user_has_premium($conn, $userId),
    ];
}

/** Re-check recent pending Tenant Pro txs with Lenco (missed callback / closed WebView). */
function tcp_reconcile_pending(PDO $conn, $userId) {
    if (tcp_user_has_premium($conn, $userId)) {
        return true;
    }

    try {
        $stmt = $conn->prepare(
            "SELECT reference FROM transactions
             WHERE user_id = ?
               AND status = 'pending'
               AND (message LIKE '%Tenant Contact%' OR message LIKE '%Contact Access%')
               AND created_at >= (NOW() - INTERVAL 7 DAY)
             ORDER BY id DESC
             LIMIT 8"
        );
        $stmt->execute([$userId]);
        $refs = $stmt->fetchAll(PDO::FETCH_COLUMN);
    } catch (Exception $e) {
        return false;
    }

    if (empty($refs)) {
        return false;
    }

    $lenco = new LencoAPI();
    foreach ($refs as $reference) {
        $reference = trim((string) $reference);
        if ($reference === '') {
            continue;
        }
        try {
            $result = $lenco->verifyTransaction($reference);
            $settled = tcp_settle_from_lenco($conn, $userId, $reference, is_array($result) ? $result : []);
            if (!empty($settled['has_paid'])) {
                return true;
            }
        } catch (Exception $e) {
            // Try next pending reference.
        }
    }

    return tcp_user_has_premium($conn, $userId);
}

// Capture request data properly regardless of Content-Type
$input = file_get_contents("php://input");
$data = json_decode($input, true);

// Fallback to $_REQUEST if JSON is empty
if (empty($data)) {
    $data = $_REQUEST;
}

$action = $data['action'] ?? $_GET['action'] ?? '';
$user_id = $data['user_id'] ?? $_GET['user_id'] ?? '';

if (empty($user_id)) {
    echo json_encode(['status' => 'error', 'message' => 'User ID is required']);
    exit;
}

if ($action === 'get_status') {
    header('Content-Type: application/json');
    // Backstop: if client paid but verify never saved, catch it here.
    $has_paid = tcp_reconcile_pending($conn, $user_id);

    echo json_encode([
        'status' => 'success',
        'has_paid' => $has_paid
    ]);
    exit;
}

if ($action === 'initiate') {
    header('Content-Type: application/json');

    // Prevent paying twice when Tenant Pro is already active.
    if (tcp_user_has_premium($conn, $user_id) || tcp_reconcile_pending($conn, $user_id)) {
        echo json_encode([
            'status' => 'success',
            'message' => 'Premium access is already active on this account.',
            'has_paid' => true,
            'already_paid' => true,
        ]);
        exit;
    }

    $phone = $data['phone'] ?? '';
    $operator = $data['operator'] ?? 'mtn';
    $country = $data['country'] ?? 'zm';
    
    if (empty($phone)) {
        echo json_encode(['status' => 'error', 'message' => 'Phone number is required']);
        exit;
    }
    
    // Normalize phone: Remove spaces, dashes, plus signs
    $phone = preg_replace('/\D/', '', $phone);

    // Phone validation matching the dealer payment logic
    $isValidPhone = false;
    $countryLower = strtolower($country);
    if ($countryLower === 'zm') {
        if (strlen($phone) === 10 && (strpos($phone, '09') === 0 || strpos($phone, '07') === 0 || strpos($phone, '05') === 0)) {
            $isValidPhone = true;
        } elseif (strlen($phone) === 9 && (strpos($phone, '9') === 0 || strpos($phone, '7') === 0 || strpos($phone, '5') === 0)) {
            $isValidPhone = true;
        } elseif (strlen($phone) > 10 && strpos($phone, '260') === 0) {
            $isValidPhone = true;
        }
    } elseif ($countryLower === 'mw') {
        if (strlen($phone) >= 9 && strlen($phone) <= 10) {
            $isValidPhone = true;
        } elseif (strlen($phone) > 10 && strpos($phone, '265') === 0) {
            $isValidPhone = true;
        }
    } else {
        if (strlen($phone) >= 8 && strlen($phone) <= 15) {
            $isValidPhone = true;
        }
    }

    if (!$isValidPhone) {
        echo json_encode([
            'status' => 'error',
            'message' => 'Invalid phone number format for ' . strtoupper($country) . '.'
        ]);
        exit;
    }
    
    $amount = 5.00;
    $currency = 'ZMW';
    $lenco = new LencoAPI();
    
    $response = $lenco->initiateMobileMoney($amount, $currency, $phone, $operator, $country);
    
    if (isset($response['status']) && $response['status'] === true) {
        $reference = $response['data']['reference'] ?? $response['data']['id'] ?? ('TENANT-' . uniqid() . '-' . time());
        
        try {
            $stmt = $conn->prepare("INSERT INTO transactions (user_id, reference, amount, currency, status, payment_method, message) VALUES (?, ?, ?, ?, 'pending', 'mobile-money', 'Tenant Contact Access Fee')");
            $stmt->execute([$user_id, $reference, $amount, $currency]);
            
            echo json_encode([
                'status' => 'success',
                'message' => 'Payment initiated. Check your phone for the prompt.',
                'reference' => $reference,
            ]);
        } catch (Exception $e) {
            echo json_encode(['status' => 'error', 'message' => 'Database error']);
        }
    } else {
        $lencoError = $response['message'] ?? 'Lenco API failed to initiate payment';
        // Add detailed response for debugging
        echo json_encode([
            'status' => 'error',
            'message' => $lencoError,
            'lenco_response' => $response
        ]);
    }
    exit;
}

if ($action === 'verify') {
    header('Content-Type: application/json');
    $reference = $data['reference'] ?? $_GET['reference'] ?? '';
    if (empty($reference)) {
        echo json_encode(['status' => 'error', 'message' => 'Reference is required']);
        exit;
    }

    // Idempotent: already unlocked — do not require another Lenco round-trip.
    if (tcp_user_has_premium($conn, $user_id)) {
        echo json_encode([
            'status' => 'success',
            'message' => 'Payment already recorded',
            'has_paid' => true,
            'already_paid' => true,
        ]);
        exit;
    }

    // Ensure we have a pending row even if pay_page insert was skipped.
    $amountHint = 5.00;
    try {
        $priceStmt = $conn->query("SELECT setting_value FROM settings WHERE setting_key = 'tenant_pro_price'");
        $amountHint = (float) ($priceStmt->fetchColumn() ?: 5);
    } catch (Exception $e) {
    }
    tcp_ensure_pending_transaction($conn, $user_id, $reference, $amountHint);

    $lenco = new LencoAPI();
    $result = $lenco->verifyTransaction($reference);
    $settled = tcp_settle_from_lenco($conn, $user_id, $reference, is_array($result) ? $result : []);

    if (!empty($settled['ok'])) {
        echo json_encode([
            'status' => 'success',
            'message' => $settled['message'] ?? 'Payment successful',
            'has_paid' => true,
        ]);
        exit;
    }

    // Keep pending/processing statuses so the pay page can keep polling.
    if (in_array($settled['status'] ?? '', ['pending', 'processing'], true)) {
        echo json_encode([
            'status' => $settled['status'],
            'message' => $settled['message'] ?? ('Payment is ' . $settled['status']),
            'has_paid' => !empty($settled['has_paid']),
        ]);
        exit;
    }

    echo json_encode([
        'status' => $settled['status'] ?? 'error',
        'message' => $settled['message'] ?? 'Verification failed',
        'has_paid' => !empty($settled['has_paid']),
        'debug' => $result,
    ]);
    exit;
}

if ($action === 'history') {
    header('Content-Type: application/json');
    $stmt = $conn->prepare("SELECT id, amount_paid, payment_type, operator, status, created_at FROM premium_contacts WHERE user_id = ? ORDER BY created_at DESC");
    $stmt->execute([$user_id]);
    $history = $stmt->fetchAll();
    
    echo json_encode([
        'status' => 'success',
        'data' => $history
    ]);
    exit;
}

if ($action === 'pay_page') {
    // Fetch the dynamic price
    $tenant_price_stmt = $conn->query("SELECT setting_value FROM settings WHERE setting_key = 'tenant_pro_price'");
    $tenant_pro_price = $tenant_price_stmt->fetchColumn() ?: '5';

    // Recover paid-but-unsaved purchases before offering another checkout.
    $alreadyPaid = tcp_reconcile_pending($conn, $user_id);

    // Render the Lenco Inline JS page
    $phone = $_REQUEST['phone'] ?? '0970000000';
    $email = $_REQUEST['email'] ?? 'tenant@houserent.site';
    $name = $_REQUEST['name'] ?? 'Tenant';
    $reference = 'ref-' . time() . '-' . $user_id;
    $amount = (int)$tenant_pro_price;
    
    // Split name
    $nameParts = explode(' ', $name);
    $firstName = $nameParts[0];
    $lastName = isset($nameParts[1]) ? $nameParts[1] : 'User';
    
    // Lenco expects the amount in the regular currency denomination (e.g. 5.00 for K5)
    // The previous API version required ngwee/kobo, but the V2 docs state:
    // "The amount field should not be converted to the lowest currency unit."
    $amount_lowest_denom = $amount;

    // Save pending BEFORE Lenco so later verify/get_status can unlock even if WebView closes.
    if (!$alreadyPaid) {
        tcp_ensure_pending_transaction($conn, $user_id, $reference, (float) $amount, 'ZMW');
    }
    
    // Lenco Public Key from your config file
    // The inline JS requires the public key which starts with 'pub-' (LENCO_SECRET in config)
    $publicKey = defined('LENCO_SECRET') ? LENCO_SECRET : (defined('LENCO_KEY') ? LENCO_KEY : 'YOUR_PUBLIC_KEY'); 
    ?>
    <!DOCTYPE html>
    <html>
    <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <!-- Add CSP to explicitly allow Lenco scripts and inline scripts -->
        <meta http-equiv="Content-Security-Policy" content="default-src 'self' https://pay.lenco.co https://api.lenco.co; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://pay.lenco.co https://code.jquery.com https://static.cloudflareinsights.com https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net; font-src 'self' https://fonts.gstatic.com; connect-src 'self' https://api.lenco.co https://pay.lenco.co; frame-src https://pay.lenco.co;">
        
        <title>Premium Contact Access</title>
        <!-- Bootstrap CSS -->
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <!-- Bootstrap Icons -->
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.5/font/bootstrap-icons.css">
        <style>
            body { font-family: Arial, sans-serif; background: #f9f9f9; }
        </style>
        <script src="https://pay.lenco.co/js/v1/inline.js"></script>
        <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    </head>
    <body>
        <div class="container py-5">
            <div class="row justify-content-center">
                <div class="col-md-6 col-lg-5">
                    <div class="text-center mb-4">
                        <h2 class="fw-bold">Premium Access</h2>
                        <p class="text-muted">Unlock contact details for all listings.</p>
                    </div>

                    <?php if ($alreadyPaid): ?>
                    <div class="card border-0 shadow rounded-3 text-center">
                        <div class="card-body p-5">
                            <i class="bi bi-check-circle-fill text-success mb-3" style="font-size: 4rem;"></i>
                            <h3 class="fw-bold mb-3">Already unlocked</h3>
                            <p class="text-muted mb-4">Premium Contact Access is already active. You do not need to pay again.</p>
                            <div class="d-grid">
                                <button type="button" class="btn btn-success btn-lg fw-bold" onclick="finishPayment()">Continue to Contacts</button>
                            </div>
                        </div>
                    </div>
                    <?php else: ?>

                    <div class="card border-0 shadow rounded-3 position-relative overflow-hidden" id="paymentCard">
                        <div class="position-absolute top-0 end-0 bg-warning text-dark px-3 py-1 fw-bold small rounded-bottom-start">RECOMMENDED</div>
                        <div class="card-body p-4 text-center d-flex flex-column">
                            <h5 class="fw-bold text-primary mb-3">Tenant Pro</h5>
                            <h1 class="display-4 fw-bold mb-0">ZMW <?php echo htmlspecialchars(number_format($tenant_pro_price, 2)); ?></h1>
                            <p class="text-muted mb-4">One Time Payment</p>
                            <ul class="list-unstyled text-start mb-auto mx-auto" style="max-width: 250px;">
                                <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i> Direct Call & WhatsApp</li>
                                <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i> Early updates of new listings</li>
                                <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i> Premium call services</li>
                                <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i> Pay once, access forever</li>
                            </ul>
                            
                            <hr class="my-4">
                            
                            <form id="paymentForm" class="text-start">
                                <div class="mb-3">
                                    <label class="form-label fw-bold">Choose Method</label>
                                    <select class="form-select" id="payment_method" name="payment_method" onchange="togglePaymentFields()">
                                        <option value="card">Credit / Debit Card (Visa/Mastercard)</option>
                                        <option value="mobile-money">Mobile Money (Airtel / MTN / Zamtel)</option>
                                    </select>
                                </div>

                                <div id="mobile_money_fields" style="display: none;" class="bg-light p-3 rounded mb-3">
                                    <div class="mb-3">
                                        <label for="country" class="form-label small text-uppercase fw-bold">Country</label>
                                        <select class="form-select" id="country" name="country" onchange="updatePhonePlaceholder()">
                                            <option value="zm" data-code="260" selected>Zambia (+260)</option>
                                            <option value="mw" data-code="265">Malawi (+265)</option>
                                            <option value="ke" data-code="254">Kenya (+254)</option>
                                            <option value="ug" data-code="256">Uganda (+256)</option>
                                            <option value="tz" data-code="255">Tanzania (+255)</option>
                                            <option value="rw" data-code="250">Rwanda (+250)</option>
                                            <option value="gh" data-code="233">Ghana (+233)</option>
                                            <option value="ng" data-code="234">Nigeria (+234)</option>
                                            <option value="za" data-code="27">South Africa (+27)</option>
                                            <option value="zw" data-code="263">Zimbabwe (+263)</option>
                                            <option value="bw" data-code="267">Botswana (+267)</option>
                                            <option value="na" data-code="264">Namibia (+264)</option>
                                            <option value="mz" data-code="258">Mozambique (+258)</option>
                                        </select>
                                    </div>
                                    <div class="mb-3">
                                        <label for="phoneInput" class="form-label small text-uppercase fw-bold">Mobile Number</label>
                                        <div class="input-group">
                                            <input type="text" class="form-control" id="phoneInput" name="phoneInput" placeholder="e.g. 097xxxxxxx">
                                            <button class="btn btn-outline-secondary" type="button" onclick="verifyPhoneFormat()">Verify</button>
                                        </div>
                                        <div id="phone-feedback" class="form-text"></div>
                                    </div>
                                </div>

                                <div class="d-grid mt-4">
                                    <button type="button" id="payButton" class="btn btn-primary btn-lg" onclick="initiateLencoPayment()">Proceed to Pay</button>
                                </div>
                                <p class="text-danger text-center fw-bold small mt-3 mb-0">Please don't leave this page until your payment has been processed.</p>
                            </form>
                        </div>
                    </div>

                    <!-- SUCCESS CARD -->
                    <div class="card border-0 shadow rounded-3 text-center mt-4" id="successCard" style="display: none;">
                        <div class="card-body p-5">
                            <i class="bi bi-check-circle-fill text-success mb-3" style="font-size: 4rem;"></i>
                            <h3 class="fw-bold mb-3">Payment Successful!</h3>
                            <p class="text-muted mb-4">You now have Premium Access. You can view all contact details.</p>
                            
                            <div class="bg-light p-3 rounded-3 mb-4 text-start">
                                <p class="small text-muted mb-1 text-uppercase fw-bold">Receipt Number</p>
                                <p class="fw-bold fs-5 mb-0 font-monospace text-primary" id="receiptNumber">---</p>
                            </div>
                            
                            <div class="d-grid">
                                <button type="button" class="btn btn-success btn-lg fw-bold" onclick="finishPayment()">Continue to Contacts</button>
                            </div>
                        </div>
                    </div>
                    <?php endif; ?>

                </div>
            </div>
        </div>

        <!-- Bootstrap JS Bundle -->
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>

        <script>
        window.successfulPaymentRef = <?php echo $alreadyPaid ? json_encode('already-active') : 'null'; ?>;
        var payReference = <?php echo json_encode($reference); ?>;

        function paymentApiBase() {
            return window.location.pathname.indexOf('/api/') === -1 ? 'api/' : '';
        }

        function showSuccessUi(ref) {
            var paymentCard = document.getElementById('paymentCard');
            if (paymentCard) paymentCard.style.display = 'none';
            var receipt = document.getElementById('receiptNumber');
            if (receipt) receipt.innerText = ref || payReference;
            var successCard = document.getElementById('successCard');
            if (successCard) successCard.style.display = 'block';
            window.successfulPaymentRef = ref || payReference;
        }

        function verifyPaymentOnce(ref) {
            return $.ajax({
                url: paymentApiBase() + 'tenant_contact_payment.php',
                method: 'get',
                dataType: 'json',
                data: {
                    action: 'verify',
                    user_id: '<?php echo addslashes((string) $user_id); ?>',
                    reference: ref
                }
            }).then(function (verifyResponse) {
                if (verifyResponse && (
                    verifyResponse.status === 'success' ||
                    verifyResponse.has_paid === true ||
                    verifyResponse.already_paid === true
                )) {
                    showSuccessUi(ref);
                    return { done: true, pending: false };
                }
                if (verifyResponse && (verifyResponse.status === 'pending' || verifyResponse.status === 'processing')) {
                    return { done: false, pending: true };
                }
                return {
                    done: false,
                    pending: false,
                    message: (verifyResponse && (verifyResponse.message || verifyResponse.status)) || 'Unknown error'
                };
            });
        }

        function pollVerifyUntilSettled(ref, attemptsLeft) {
            attemptsLeft = typeof attemptsLeft === 'number' ? attemptsLeft : 12;
            var btn = document.getElementById('payButton');
            if (attemptsLeft <= 0) {
                if (btn) {
                    btn.innerHTML = 'Proceed to Pay';
                    btn.disabled = false;
                }
                alert('Payment is still confirming. If money left your phone, reopen contacts — unlocking will finish automatically.');
                return;
            }
            verifyPaymentOnce(ref).done(function (state) {
                if (state.done) {
                    if (btn) {
                        btn.innerHTML = 'Proceed to Pay';
                        btn.disabled = false;
                    }
                    return;
                }
                if (state.pending) {
                    if (btn) btn.innerHTML = 'Confirming... (' + attemptsLeft + ')';
                    setTimeout(function () {
                        pollVerifyUntilSettled(ref, attemptsLeft - 1);
                    }, 4000);
                    return;
                }
                if (btn) {
                    btn.innerHTML = 'Proceed to Pay';
                    btn.disabled = false;
                }
                alert('Payment status: ' + (state.message || 'Unknown error'));
            }).fail(function () {
                if (btn) btn.innerHTML = 'Retrying verify...';
                setTimeout(function () {
                    pollVerifyUntilSettled(ref, attemptsLeft - 1);
                }, 4000);
            });
        }

        function togglePaymentFields() {
            var method = document.getElementById('payment_method').value;
            var mmFields = document.getElementById('mobile_money_fields');
            if (method === 'mobile-money') {
                mmFields.style.display = 'block';
                document.getElementById('phoneInput').focus();
            } else {
                mmFields.style.display = 'none';
            }
        }

        function verifyPhoneFormat() {
            var inputPhone = document.getElementById('phoneInput').value;
            var country = document.getElementById('country').value;
            var feedback = document.getElementById('phone-feedback');
            
            var cleanPhone = inputPhone.replace(/\D/g, '');
            var isValid = false;
            var message = "";

            if (country === 'zm') {
                if (cleanPhone.length === 10 && (cleanPhone.startsWith('09') || cleanPhone.startsWith('07') || cleanPhone.startsWith('05'))) {
                    isValid = true;
                    message = "Valid Zambia Format";
                } else if (cleanPhone.length === 9 && (cleanPhone.startsWith('9') || cleanPhone.startsWith('7') || cleanPhone.startsWith('5'))) {
                    isValid = true;
                    message = "Valid Zambia Format (will be normalized)";
                } else if (cleanPhone.length > 10 && cleanPhone.startsWith('260')) {
                    isValid = true;
                    message = "Valid Zambia Format (with country code)";
                } else {
                    message = "Invalid format. Expected 10 digits starting with 09/07/05.";
                }
            } else if (country === 'mw') {
                if (cleanPhone.length >= 9 && cleanPhone.length <= 10) {
                    isValid = true;
                    message = "Valid Malawi Format";
                } else {
                    message = "Invalid length for Malawi.";
                }
            } else {
                if (cleanPhone.length >= 8 && cleanPhone.length <= 15) {
                    isValid = true;
                    message = "Format looks okay";
                } else {
                    message = "Invalid length";
                }
            }

            if (isValid) {
                feedback.className = "form-text text-success fw-bold";
                feedback.innerHTML = '<i class="bi bi-check-circle"></i> ' + message;
            } else {
                feedback.className = "form-text text-danger fw-bold";
                feedback.innerHTML = '<i class="bi bi-x-circle"></i> ' + message;
            }
            return isValid;
        }

        function updatePhonePlaceholder() {
            var countrySelect = document.getElementById('country');
            var selectedOption = countrySelect.options[countrySelect.selectedIndex];
            var code = selectedOption.getAttribute('data-code');
            document.getElementById('phoneInput').placeholder = "e.g. " + code + "xxxxxxx";
            document.getElementById('phone-feedback').innerHTML = "";
        }

        function initiateLencoPayment() {
            if (typeof LencoPay === 'undefined') {
                alert('Payment system is loading. Please check your internet connection or try again.');
                console.error('LencoPay SDK not loaded');
                return;
            }

            var method = document.getElementById('payment_method').value;
            var customerPhone = '<?php echo addslashes($phone); ?>';
            
            // Lenco works best when we pass both channels to the popup 
            // and let the user select/confirm their method there.
            var channels = ["card", "mobile-money"];
            
            if (method === 'mobile-money') {
                var inputPhone = document.getElementById('phoneInput').value;
                if (!inputPhone) {
                    alert("Please enter a valid mobile money number.");
                    return;
                }
                
                // If they clicked proceed without verifying, verify now
                if (!verifyPhoneFormat()) {
                    alert("Please enter a valid phone number format before proceeding.");
                    return;
                }
                
                var cleanPhone = inputPhone.replace(/\D/g, '');
                var countryCode = document.getElementById('country').options[document.getElementById('country').selectedIndex].getAttribute('data-code');
                
                // Lenco inline JS usually expects the phone number without the country code 
                // if it's a local number, or fully formatted. We ensure it starts with 0 for local.
                if (cleanPhone.startsWith(countryCode)) {
                    cleanPhone = '0' + cleanPhone.substring(countryCode.length);
                } else if (!cleanPhone.startsWith('0') && cleanPhone.length === 9) {
                    cleanPhone = '0' + cleanPhone;
                }
                
                customerPhone = cleanPhone;
            }

            var btn = document.getElementById('payButton');
            btn.innerHTML = 'Loading...';
            btn.disabled = true;
            
            try {
                LencoPay.getPaid({
                    key: '<?php echo $publicKey; ?>',
                    reference: payReference,
                    email: '<?php echo htmlspecialchars($email); ?>',
                    amount: <?php echo $amount_lowest_denom; ?>, // Amount is now normal K5, NOT multiplied by 100 per V2 docs
                    currency: "ZMW",
                    color: "#FFC107", // Bootstrap warning yellow to match app theme
                    channels: channels,
                    customer: {
                        firstName: '<?php echo addslashes($firstName); ?>',
                        lastName: '<?php echo addslashes($lastName); ?>',
                        phone: customerPhone || '0971111111'
                    },
                    onSuccess: function (response) {
                        btn.innerHTML = 'Verifying Payment...';
                        var ref = (response && response.reference) ? response.reference : payReference;
                        window.successfulPaymentRef = ref;
                        // Poll until Lenco settles — covers slow mobile-money confirms.
                        pollVerifyUntilSettled(ref, 12);
                    },
                    onClose: function () {
                        console.log('Payment was not completed, window closed.');
                        // One reconcile attempt in case they paid before closing.
                        verifyPaymentOnce(payReference).always(function () {
                            btn.innerHTML = 'Proceed to Pay';
                            btn.disabled = false;
                        });
                    },
                    onConfirmationPending: function () {
                        btn.innerHTML = 'Waiting for confirmation...';
                        btn.disabled = true;
                        // Keep verifying instead of telling the user to leave.
                        pollVerifyUntilSettled(payReference, 15);
                    }
                });
            } catch (error) {
                console.error("LencoPay execution error:", error);
                alert("Payment initiation failed. See console for details.");
                btn.innerHTML = 'Proceed to Pay';
                btn.disabled = false;
            }
        }

        function finishPayment() {
            var ref = window.successfulPaymentRef || payReference || 'unknown';
            if (window.Flutter) {
                window.Flutter.postMessage(JSON.stringify({ status: 'success', reference: ref }));
            } else {
                // Force reload the page to refresh the lock status
                window.location.reload();
            }
        }
        </script>
    </body>
    </html>
    <?php
    exit;
}

echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
