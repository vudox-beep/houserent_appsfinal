<?php
/**
 * Agent / Private Company subscription payment.
 * Same Lenco configuration & flow as api/tenant_contact_payment.php —
 * different file, different price / activation target.
 *
 * Company = K300/month → private_companies
 * Agent   = K20/month  → agents
 *
 * Actions: get_status | initiate | verify | history | pay_page
 */
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$configLoaded = false;
foreach ([
    __DIR__ . '/../../../house/config/config.php',
    __DIR__ . '/../../../../house/config/config.php',
    dirname(__DIR__, 3) . '/house/config/config.php',
    __DIR__ . '/../../config/config.php',
] as $cfg) {
    if (is_file($cfg)) {
        require_once $cfg;
        $configLoaded = true;
        break;
    }
}

require_once __DIR__ . '/helpers.php';

$lencoPath = __DIR__ . '/../includes/LencoAPI.php';
if (is_file($lencoPath)) {
    require_once $lencoPath;
}

if (!class_exists('LencoAPI')) {
    class LencoAPI
    {
        private $baseUrl;
        private $apiKey;

        public function __construct()
        {
            $this->baseUrl = defined('LENCO_BASE_URL')
                ? rtrim(str_replace('`', '', LENCO_BASE_URL), '/')
                : 'https://api.lenco.co/access/v2';
            $this->apiKey = defined('LENCO_KEY') ? LENCO_KEY : '';
        }

        private function getAuthorizationHeader()
        {
            $key = (string) $this->apiKey;
            $normalized = strtolower($key);
            if ($key !== '' && strpos($normalized, 'bearer ') !== 0) {
                return 'Bearer ' . $key;
            }
            return $key;
        }

        private function request($method, $endpoint, $data = [])
        {
            $url = $this->baseUrl . $endpoint;
            $ch = curl_init();
            $headers = [
                'Authorization: ' . $this->getAuthorizationHeader(),
                'Content-Type: application/json',
                'Accept: application/json',
            ];
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
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

        public function normalizePhone($phone, $countryIso = 'zm')
        {
            $digits = preg_replace('/\D+/', '', $phone);
            $codes = [
                'zm' => '260', 'mw' => '265', 'ke' => '254', 'ug' => '256',
                'tz' => '255', 'rw' => '250', 'gh' => '233', 'ng' => '234',
                'za' => '27', 'zw' => '263', 'bw' => '267', 'mz' => '258',
            ];
            $countryCode = $codes[strtolower($countryIso)] ?? '260';
            if (strpos($digits, $countryCode) === 0) {
                $digits = substr($digits, strlen($countryCode));
            }
            if (strpos($digits, '0') === 0) {
                $digits = ltrim($digits, '0');
            }
            return $digits;
        }

        public function initiateMobileMoney($amount, $currency, $phone, $operator, $country = 'zm')
        {
            $normalizedPhone = $this->normalizePhone($phone, $country);
            $payload = [
                'amount' => number_format((float) $amount, 2, '.', ''),
                'currency' => $currency,
                'reference' => 'SUB-' . uniqid() . '-' . time(),
                'type' => 'mobile-money',
                'mobileMoneyDetails' => [
                    'country' => strtoupper($country),
                    'phone' => $normalizedPhone,
                    'operator' => strtolower($operator),
                ],
                'bearer' => 'customer',
            ];
            $response = $this->request('POST', '/collections/mobile-money', $payload);
            if (isset($response['status']) && $response['status'] === true && !isset($response['data']['reference'])) {
                $response['data']['reference'] = $payload['reference'];
            }
            return $response;
        }

        public function verifyTransaction($reference)
        {
            return $this->request('GET', '/collections/status/' . $reference);
        }
    }
}

try {
    if (!isset($conn) || !($conn instanceof PDO)) {
        if (defined('DB_HOST') && defined('DB_NAME')) {
            $conn = new PDO(
                'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
                defined('DB_USER') ? DB_USER : 'root',
                defined('DB_PASS') ? DB_PASS : ''
            );
            $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $conn->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        } else {
            require_once __DIR__ . '/../db.php';
        }
    }
    if (!($conn instanceof PDO)) {
        throw new PDOException('No DB');
    }
} catch (PDOException $e) {
    header('Content-Type: application/json');
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed']);
    exit;
}

hr_ac_ensure_tables($conn);

function acp_success_statuses()
{
    return ['successful', 'success', 'completed', 'paid', 'approved'];
}

function acp_is_success_status($status)
{
    return in_array(strtolower(trim((string) $status)), acp_success_statuses(), true);
}

function acp_account_meta(PDO $conn, $userId)
{
    $stmt = $conn->prepare('SELECT id, name, email, phone, role FROM users WHERE id = ? LIMIT 1');
    $stmt->execute([$userId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) {
        return null;
    }
    $role = strtolower(trim((string) ($user['role'] ?? '')));
    if ($role === 'company') {
        return [
            'user' => $user,
            'role' => 'company',
            'table' => 'private_companies',
            'fee' => 300.00,
            'label' => 'Company Pro',
            'tx_message' => 'Private Company Subscription Fee',
        ];
    }
    if ($role === 'agent') {
        return [
            'user' => $user,
            'role' => 'agent',
            'table' => 'agents',
            'fee' => 20.00,
            'label' => 'Agent Pro',
            'tx_message' => 'Agent Subscription Fee',
        ];
    }
    return null;
}

function acp_user_has_subscription(PDO $conn, $userId)
{
    $meta = acp_account_meta($conn, $userId);
    if (!$meta) {
        return false;
    }
    $table = $meta['table'];
    $stmt = $conn->prepare(
        "SELECT subscription_status, subscription_expiry FROM {$table} WHERE user_id = ? LIMIT 1"
    );
    $stmt->execute([$userId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return false;
    }
    if (strtolower(trim((string) ($row['subscription_status'] ?? ''))) !== 'active') {
        return false;
    }
    $expiry = $row['subscription_expiry'] ?? null;
    if ($expiry && strtotime((string) $expiry) < time()) {
        return false;
    }
    return true;
}

function acp_ensure_pending_transaction(PDO $conn, $userId, $reference, $amount, $currency, $message)
{
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
             VALUES (?, ?, ?, ?, 'pending', 'mobile-money', ?)"
        );
        $stmt->execute([$userId, $reference, $amount, $currency, $message]);
    } catch (Exception $e) {
    }
}

function acp_activate_subscription(PDO $conn, $userId, $reference, array $resData)
{
    $meta = acp_account_meta($conn, $userId);
    if (!$meta) {
        throw new RuntimeException('Not agent/company');
    }
    $amount = isset($resData['amount']) ? (float) $resData['amount'] : (float) $meta['fee'];
    $currency = $resData['currency'] ?? 'ZMW';
    $lencoRef = $resData['lencoReference'] ?? ($resData['reference'] ?? $reference);

    acp_ensure_pending_transaction($conn, $userId, $reference, $amount, $currency, $meta['tx_message']);

    try {
        $stmt = $conn->prepare(
            "UPDATE transactions SET status = 'successful', lenco_reference = ? WHERE reference = ?"
        );
        $stmt->execute([$lencoRef, $reference]);
    } catch (Exception $e) {
        $stmt = $conn->prepare("UPDATE transactions SET status = 'successful' WHERE reference = ?");
        $stmt->execute([$reference]);
    }

    $expiry = date('Y-m-d H:i:s', strtotime('+30 days'));
    $upd = $conn->prepare(
        "UPDATE {$meta['table']}
         SET subscription_status = 'active', subscription_expiry = ?
         WHERE user_id = ?"
    );
    $upd->execute([$expiry, $userId]);
}

function acp_settle_from_lenco(PDO $conn, $userId, $reference, array $result)
{
    if (!(isset($result['status']) && $result['status'] === true)) {
        return [
            'ok' => false,
            'status' => 'error',
            'message' => 'Verification failed',
            'has_paid' => acp_user_has_subscription($conn, $userId),
        ];
    }

    $resData = is_array($result['data'] ?? null) ? $result['data'] : [];
    $payStatus = strtolower((string) ($resData['status'] ?? ''));

    if (acp_is_success_status($payStatus)) {
        try {
            acp_activate_subscription($conn, $userId, $reference, $resData);
        } catch (Exception $e) {
            if (acp_user_has_subscription($conn, $userId)) {
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
            'has_paid' => acp_user_has_subscription($conn, $userId),
        ];
    }

    return [
        'ok' => false,
        'status' => $payStatus !== '' ? $payStatus : 'error',
        'message' => 'Payment is ' . ($payStatus !== '' ? $payStatus : 'unknown'),
        'has_paid' => acp_user_has_subscription($conn, $userId),
    ];
}

function acp_reconcile_pending(PDO $conn, $userId)
{
    if (acp_user_has_subscription($conn, $userId)) {
        return true;
    }
    try {
        $stmt = $conn->prepare(
            "SELECT reference FROM transactions
             WHERE user_id = ?
               AND status = 'pending'
               AND (message LIKE '%Company Subscription%' OR message LIKE '%Agent Subscription%')
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
            $settled = acp_settle_from_lenco($conn, $userId, $reference, is_array($result) ? $result : []);
            if (!empty($settled['has_paid'])) {
                return true;
            }
        } catch (Exception $e) {
        }
    }
    return acp_user_has_subscription($conn, $userId);
}

function acp_valid_phone($phone, $country)
{
    $phone = preg_replace('/\D/', '', (string) $phone);
    $c = strtolower($country);
    if ($c === 'zm') {
        if (strlen($phone) === 10 && (strpos($phone, '09') === 0 || strpos($phone, '07') === 0 || strpos($phone, '05') === 0)) {
            return true;
        }
        if (strlen($phone) === 9 && (strpos($phone, '9') === 0 || strpos($phone, '7') === 0 || strpos($phone, '5') === 0)) {
            return true;
        }
        return strlen($phone) > 10 && strpos($phone, '260') === 0;
    }
    if ($c === 'mw') {
        if (strlen($phone) >= 9 && strlen($phone) <= 10) {
            return true;
        }
        return strlen($phone) > 10 && strpos($phone, '265') === 0;
    }
    return strlen($phone) >= 8 && strlen($phone) <= 15;
}

$input = file_get_contents('php://input');
$data = json_decode($input, true);
if (empty($data)) {
    $data = $_REQUEST;
}

$action = $data['action'] ?? $_GET['action'] ?? '';
$user_id = $data['user_id'] ?? $_GET['user_id'] ?? '';

if ($user_id === '' || $user_id === null) {
    header('Content-Type: application/json');
    echo json_encode(['status' => 'error', 'message' => 'User ID is required']);
    exit;
}

$meta = acp_account_meta($conn, $user_id);
if (!$meta) {
    header('Content-Type: application/json');
    echo json_encode(['status' => 'error', 'message' => 'User must be an agent or company account']);
    exit;
}

if ($action === 'get_status') {
    header('Content-Type: application/json');
    $hasPaid = acp_reconcile_pending($conn, $user_id);
    echo json_encode([
        'status' => 'success',
        'has_paid' => $hasPaid,
        'subscription_fee' => $meta['fee'],
        'role' => $meta['role'],
        'is_payment_locked' => !$hasPaid,
    ]);
    exit;
}

if ($action === 'initiate') {
    header('Content-Type: application/json');

    if (acp_user_has_subscription($conn, $user_id) || acp_reconcile_pending($conn, $user_id)) {
        echo json_encode([
            'status' => 'success',
            'message' => 'Subscription is already active on this account.',
            'has_paid' => true,
            'already_paid' => true,
        ]);
        exit;
    }

    $phone = $data['phone'] ?? ($meta['user']['phone'] ?? '');
    $operator = $data['operator'] ?? 'mtn';
    $country = $data['country'] ?? 'zm';

    if ($phone === '') {
        echo json_encode(['status' => 'error', 'message' => 'Phone number is required']);
        exit;
    }

    $phone = preg_replace('/\D/', '', $phone);
    if (!acp_valid_phone($phone, $country)) {
        echo json_encode([
            'status' => 'error',
            'message' => 'Invalid phone number format for ' . strtoupper($country) . '.',
        ]);
        exit;
    }

    $amount = (float) $meta['fee'];
    $currency = 'ZMW';
    $lenco = new LencoAPI();
    $response = $lenco->initiateMobileMoney($amount, $currency, $phone, $operator, $country);

    if (isset($response['status']) && $response['status'] === true) {
        $reference = $response['data']['reference']
            ?? $response['data']['id']
            ?? ('AC-' . uniqid() . '-' . time());
        try {
            $stmt = $conn->prepare(
                "INSERT INTO transactions (user_id, reference, amount, currency, status, payment_method, message)
                 VALUES (?, ?, ?, ?, 'pending', 'mobile-money', ?)"
            );
            $stmt->execute([$user_id, $reference, $amount, $currency, $meta['tx_message']]);
            echo json_encode([
                'status' => 'success',
                'message' => 'Payment initiated. Check your phone for the prompt.',
                'reference' => $reference,
                'amount' => $amount,
            ]);
        } catch (Exception $e) {
            echo json_encode(['status' => 'error', 'message' => 'Database error']);
        }
    } else {
        echo json_encode([
            'status' => 'error',
            'message' => $response['message'] ?? 'Lenco API failed to initiate payment',
            'lenco_response' => $response,
        ]);
    }
    exit;
}

if ($action === 'verify') {
    header('Content-Type: application/json');
    $reference = $data['reference'] ?? $_GET['reference'] ?? '';
    if ($reference === '') {
        echo json_encode(['status' => 'error', 'message' => 'Reference is required']);
        exit;
    }

    if (acp_user_has_subscription($conn, $user_id)) {
        echo json_encode([
            'status' => 'success',
            'message' => 'Payment already recorded',
            'has_paid' => true,
            'already_paid' => true,
        ]);
        exit;
    }

    acp_ensure_pending_transaction(
        $conn,
        $user_id,
        $reference,
        (float) $meta['fee'],
        'ZMW',
        $meta['tx_message']
    );

    $lenco = new LencoAPI();
    $result = $lenco->verifyTransaction($reference);
    $settled = acp_settle_from_lenco($conn, $user_id, $reference, is_array($result) ? $result : []);

    if (!empty($settled['ok'])) {
        echo json_encode([
            'status' => 'success',
            'message' => $settled['message'] ?? 'Payment successful',
            'has_paid' => true,
        ]);
        exit;
    }

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
    ]);
    exit;
}

if ($action === 'history') {
    header('Content-Type: application/json');
    $stmt = $conn->prepare(
        "SELECT id, reference, amount, currency, status, payment_method, message, created_at, updated_at
         FROM transactions
         WHERE user_id = ?
           AND (message LIKE '%Company Subscription%' OR message LIKE '%Agent Subscription%')
         ORDER BY created_at DESC"
    );
    $stmt->execute([$user_id]);
    $history = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
    echo json_encode(['status' => 'success', 'data' => $history]);
    exit;
}

if ($action === 'pay_page') {
    $alreadyPaid = acp_reconcile_pending($conn, $user_id);
    $phone = $_REQUEST['phone'] ?? ($meta['user']['phone'] ?? '0970000000');
    $email = $_REQUEST['email'] ?? ($meta['user']['email'] ?? 'user@houserent.site');
    $name = $_REQUEST['name'] ?? ($meta['user']['name'] ?? 'Subscriber');
    $reference = 'ac-' . time() . '-' . $user_id;
    $amount = (int) $meta['fee'];
    $planLabel = $meta['label'];
    $feeDisplay = number_format((float) $meta['fee'], 2);

    $nameParts = explode(' ', trim((string) $name));
    $firstName = $nameParts[0] ?: 'User';
    $lastName = $nameParts[1] ?? 'Account';

    if (!$alreadyPaid) {
        acp_ensure_pending_transaction(
            $conn,
            $user_id,
            $reference,
            (float) $amount,
            'ZMW',
            $meta['tx_message']
        );
    }

    $publicKey = defined('LENCO_SECRET')
        ? LENCO_SECRET
        : (defined('LENCO_KEY') ? LENCO_KEY : 'YOUR_PUBLIC_KEY');
    $selfUrl = basename(__FILE__);
    ?>
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?php echo htmlspecialchars($planLabel); ?> — Pay</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.5/font/bootstrap-icons.css">
    <script src="https://pay.lenco.co/js/v1/inline.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <style>
      body { font-family: Arial, sans-serif; background: #f9f9f9; }
      .pay-option {
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        padding: 12px 14px;
        margin-bottom: 10px;
        cursor: pointer;
        background: #fff;
        display: flex;
        align-items: center;
        gap: 12px;
      }
      .pay-option.active {
        border-color: #FFC107;
        background: #fffbeb;
        box-shadow: 0 0 0 2px rgba(255,193,7,.25);
      }
      .pay-option i { font-size: 1.4rem; color: #5A3D31; }
    </style>
</head>
<body>
<div class="container py-4 py-md-5">
  <div class="row justify-content-center">
    <div class="col-md-6 col-lg-5">
      <div class="text-center mb-4">
        <h2 class="fw-bold"><?php echo htmlspecialchars($planLabel); ?></h2>
        <p class="text-muted mb-0">Pay securely with card or mobile money.</p>
      </div>

      <?php if ($alreadyPaid): ?>
      <div class="card border-0 shadow rounded-3 text-center">
        <div class="card-body p-5">
          <i class="bi bi-check-circle-fill text-success mb-3" style="font-size:4rem"></i>
          <h3 class="fw-bold mb-3">Already active</h3>
          <p class="text-muted mb-4">Your subscription is already active.</p>
          <button type="button" class="btn btn-success btn-lg fw-bold w-100" onclick="finishPayment()">Continue</button>
        </div>
      </div>
      <?php else: ?>
      <div class="card border-0 shadow rounded-3" id="paymentCard">
        <div class="card-body p-4 text-center">
          <div class="position-relative">
            <span class="badge bg-warning text-dark position-absolute top-0 end-0">MONTHLY</span>
          </div>
          <h5 class="fw-bold text-primary mb-3"><?php echo htmlspecialchars($planLabel); ?></h5>
          <h1 class="display-5 fw-bold mb-0">ZMW <?php echo htmlspecialchars($feeDisplay); ?></h1>
          <p class="text-muted mb-4">Per Month</p>
          <ul class="list-unstyled text-start mx-auto mb-4" style="max-width:260px">
            <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i>Unlimited listings</li>
            <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i>Featured visibility</li>
            <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i>Leads &amp; dashboard</li>
            <li class="mb-2"><i class="bi bi-check-circle-fill text-primary me-2"></i>Verified badge</li>
          </ul>
          <hr>
          <form class="text-start">
            <label class="form-label fw-bold">Payment gateways</label>
            <input type="hidden" id="payment_method" value="card">

            <div class="pay-option active" data-method="card" onclick="selectPayMethod('card')">
              <i class="bi bi-credit-card-2-front"></i>
              <div>
                <div class="fw-bold">Credit / Debit Card</div>
                <div class="small text-muted">Visa / Mastercard</div>
              </div>
            </div>
            <div class="pay-option" data-method="mobile-money" onclick="selectPayMethod('mobile-money')">
              <i class="bi bi-phone"></i>
              <div>
                <div class="fw-bold">Mobile Money</div>
                <div class="small text-muted">Airtel / MTN / Zamtel</div>
              </div>
            </div>

            <div id="mm_fields" class="bg-light p-3 rounded mb-3" style="display:none">
              <label class="form-label small fw-bold text-uppercase">Mobile Number</label>
              <input type="text" class="form-control" id="phoneInput" value="<?php echo htmlspecialchars((string) $phone); ?>" placeholder="e.g. 097xxxxxxx">
            </div>
            <div class="d-grid mt-3">
              <button type="button" id="payButton" class="btn btn-warning btn-lg fw-bold text-dark" onclick="payNow()">Proceed to Pay</button>
            </div>
            <p class="text-danger text-center fw-bold small mt-3 mb-0">Please don't leave this page until your payment has been processed.</p>
          </form>
        </div>
      </div>
      <div class="card border-0 shadow rounded-3 text-center mt-4" id="successCard" style="display:none">
        <div class="card-body p-5">
          <i class="bi bi-check-circle-fill text-success mb-3" style="font-size:4rem"></i>
          <h3 class="fw-bold mb-3">Payment Successful!</h3>
          <p class="text-muted mb-4">Your subscription is now active.</p>
          <p class="font-monospace text-primary fw-bold" id="receiptNumber">---</p>
          <button type="button" class="btn btn-success btn-lg fw-bold w-100 mt-3" onclick="finishPayment()">Continue</button>
        </div>
      </div>
      <?php endif; ?>
    </div>
  </div>
</div>
<script>
var payReference = <?php echo json_encode($reference); ?>;
var apiFile = <?php echo json_encode($selfUrl); ?>;
var userId = <?php echo json_encode((string) $user_id); ?>;

function selectPayMethod(method) {
  document.getElementById('payment_method').value = method;
  document.querySelectorAll('.pay-option').forEach(function (el) {
    el.classList.toggle('active', el.getAttribute('data-method') === method);
  });
  document.getElementById('mm_fields').style.display = method === 'mobile-money' ? 'block' : 'none';
}

function showSuccess(ref) {
  var card = document.getElementById('paymentCard');
  if (card) card.style.display = 'none';
  var receipt = document.getElementById('receiptNumber');
  if (receipt) receipt.innerText = ref || payReference;
  var ok = document.getElementById('successCard');
  if (ok) ok.style.display = 'block';
}

function verifyOnce(ref) {
  return $.getJSON(apiFile, { action: 'verify', user_id: userId, reference: ref }).then(function (r) {
    if (r && (r.status === 'success' || r.has_paid === true || r.already_paid === true)) {
      showSuccess(ref);
      return { done: true, pending: false };
    }
    if (r && (r.status === 'pending' || r.status === 'processing')) {
      return { done: false, pending: true };
    }
    return { done: false, pending: false, message: (r && r.message) || 'Unknown' };
  });
}

function poll(ref, left) {
  left = typeof left === 'number' ? left : 12;
  var btn = document.getElementById('payButton');
  if (left <= 0) {
    if (btn) { btn.innerHTML = 'Proceed to Pay'; btn.disabled = false; }
    alert('Still confirming. Reopen this page if money left your phone.');
    return;
  }
  verifyOnce(ref).done(function (s) {
    if (s.done) { if (btn) { btn.innerHTML = 'Proceed to Pay'; btn.disabled = false; } return; }
    if (s.pending) {
      if (btn) btn.innerHTML = 'Confirming... (' + left + ')';
      setTimeout(function () { poll(ref, left - 1); }, 4000);
      return;
    }
    if (btn) { btn.innerHTML = 'Proceed to Pay'; btn.disabled = false; }
    alert('Payment status: ' + (s.message || 'Unknown'));
  }).fail(function () {
    if (btn) btn.innerHTML = 'Retrying...';
    setTimeout(function () { poll(ref, left - 1); }, 4000);
  });
}

function payNow() {
  if (typeof LencoPay === 'undefined') {
    alert('Payment system is loading. Please check your internet and try again.');
    return;
  }
  var method = document.getElementById('payment_method').value;
  var customerPhone = <?php echo json_encode((string) $phone); ?>;
  var channels = ['card', 'mobile-money'];
  if (method === 'mobile-money') {
    var p = (document.getElementById('phoneInput').value || '').replace(/\D/g, '');
    if (!p) { alert('Please enter a valid mobile money number.'); return; }
    if (!p.startsWith('0') && p.length === 9) p = '0' + p;
    customerPhone = p;
  }
  var btn = document.getElementById('payButton');
  btn.innerHTML = 'Loading...';
  btn.disabled = true;
  try {
    LencoPay.getPaid({
      key: <?php echo json_encode($publicKey); ?>,
      reference: payReference,
      email: <?php echo json_encode((string) $email); ?>,
      amount: <?php echo (int) $amount; ?>,
      currency: 'ZMW',
      color: '#FFC107',
      channels: channels,
      customer: {
        firstName: <?php echo json_encode($firstName); ?>,
        lastName: <?php echo json_encode($lastName); ?>,
        phone: customerPhone || '0971111111'
      },
      onSuccess: function (response) {
        btn.innerHTML = 'Verifying Payment...';
        var ref = (response && response.reference) ? response.reference : payReference;
        poll(ref, 12);
      },
      onClose: function () {
        verifyOnce(payReference).always(function () {
          btn.innerHTML = 'Proceed to Pay';
          btn.disabled = false;
        });
      },
      onConfirmationPending: function () {
        btn.innerHTML = 'Waiting for confirmation...';
        btn.disabled = true;
        poll(payReference, 15);
      }
    });
  } catch (e) {
    alert('Payment failed to start. Please try again.');
    btn.innerHTML = 'Proceed to Pay';
    btn.disabled = false;
  }
}

function finishPayment() {
  var ref = payReference || 'unknown';
  if (window.Flutter) {
    window.Flutter.postMessage(JSON.stringify({ status: 'success', reference: ref }));
  } else {
    window.location.reload();
  }
}
</script>
</body>
</html>
    <?php
    exit;
}

header('Content-Type: application/json');
echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
