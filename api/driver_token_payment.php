<?php
/**
 * Driver booking-token payments (Lenco) — same flow as tenant_contact_payment.php
 * (tenant "life / pay once" copy), different API + 3 token packages.
 *
 * Packages (ZMW):
 *   starter → 2 tokens · K20
 *   plus    → 3 tokens · K50
 *   pro     → 5 tokens · K89
 *
 * Security:
 *  - Server-side package prices only (client cannot set tokens/amount)
 *  - Credit only after Lenco confirms success
 *  - Row locks + status flip prevent double-credit under concurrent verifies
 *  - Per IP / user rate limits
 *
 * Live URL: https://houseforrent.site/api/driver_token_payment.php
 */
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');

$configPaths = [
    __DIR__ . '/../config/config.php',
    __DIR__ . '/../php_backend/config/config.php',
];
foreach ($configPaths as $cfg) {
    if (is_file($cfg)) {
        require_once $cfg;
        break;
    }
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
                return 'Bearer '.$key;
            }

            return $key;
        }

        private function request($method, $endpoint, $data = [])
        {
            $url = $this->baseUrl.$endpoint;
            $ch = curl_init();
            $headers = [
                'Authorization: '.$this->getAuthorizationHeader(),
                'Content-Type: application/json',
                'Accept: application/json',
            ];
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 35);
            curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 12);
            if ($method === 'POST') {
                curl_setopt($ch, CURLOPT_POST, 1);
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
            }
            $response = curl_exec($ch);
            $error = curl_error($ch);
            $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($error) {
                return ['status' => false, 'message' => $error];
            }
            $decoded = json_decode((string) $response, true);
            if (! is_array($decoded)) {
                return ['status' => false, 'message' => 'Invalid Lenco response', 'http' => $code];
            }

            return $decoded;
        }

        public function normalizePhone($phone, $countryIso = 'zm')
        {
            $digits = preg_replace('/\D+/', '', $phone);
            $codes = [
                'zm' => '260', 'mw' => '265', 'ke' => '254', 'ug' => '256',
                'tz' => '255', 'rw' => '250', 'gh' => '233', 'ng' => '234',
                'za' => '27', 'zw' => '263', 'bw' => '267', 'mz' => '258',
                'na' => '264',
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
                'reference' => 'DRVTOK-'.uniqid().'-'.time(),
                'type' => 'mobile-money',
                'mobileMoneyDetails' => [
                    'country' => strtoupper($country),
                    'phone' => $normalizedPhone,
                    'operator' => strtolower($operator),
                ],
                'bearer' => 'customer',
            ];
            $response = $this->request('POST', '/collections/mobile-money', $payload);
            if (isset($response['status']) && $response['status'] === true && ! isset($response['data']['reference'])) {
                $response['data']['reference'] = $payload['reference'];
            }

            return $response;
        }

        public function verifyTransaction($reference)
        {
            $reference = preg_replace('/[^A-Za-z0-9_\-.]/', '', (string) $reference);
            if ($reference === '' || strlen($reference) > 120) {
                return ['status' => false, 'message' => 'Invalid reference'];
            }

            return $this->request('GET', '/collections/status/'.$reference);
        }
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

/** @return array<string, array{id:string,tokens:int,price:float,label:string}> */
function driver_token_packages(): array
{
    return [
        'starter' => [
            'id' => 'starter',
            'tokens' => 2,
            'price' => 20.0,
            'label' => 'Starter',
        ],
        'plus' => [
            'id' => 'plus',
            'tokens' => 3,
            'price' => 50.0,
            'label' => 'Plus',
        ],
        'pro' => [
            'id' => 'pro',
            'tokens' => 5,
            'price' => 89.0,
            'label' => 'Pro',
        ],
    ];
}

function driver_token_client_ip(): string
{
    $ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    if (strpos($ip, ',') !== false) {
        $ip = trim(explode(',', $ip)[0]);
    }

    return preg_replace('/[^0-9a-fA-F:.]/', '', $ip) ?: '0.0.0.0';
}

/** Simple durable rate limit (many users OK; blocks spam / brute force). */
function driver_token_rate_limit(string $bucket, int $max, int $windowSec): void
{
    $dir = sys_get_temp_dir().'/houserent_drvtok_rl';
    if (! is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }
    $key = hash('sha256', $bucket);
    $file = $dir.'/'.$key.'.json';
    $now = time();
    $fp = @fopen($file, 'c+');
    if (! $fp) {
        return;
    }
    flock($fp, LOCK_EX);
    $raw = stream_get_contents($fp);
    $state = json_decode((string) $raw, true);
    if (! is_array($state) || (int) ($state['reset'] ?? 0) < $now) {
        $state = ['count' => 0, 'reset' => $now + $windowSec];
    }
    $state['count'] = (int) $state['count'] + 1;
    $ok = $state['count'] <= $max;
    ftruncate($fp, 0);
    rewind($fp);
    fwrite($fp, json_encode($state));
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    if (! $ok) {
        header('Content-Type: application/json');
        http_response_code(429);
        echo json_encode([
            'status' => 'error',
            'message' => 'Too many requests. Please wait a moment and try again.',
        ]);
        exit;
    }
}

function driver_token_json_error(string $message, int $code = 400): void
{
    header('Content-Type: application/json');
    http_response_code($code);
    echo json_encode(['status' => 'error', 'message' => $message]);
    exit;
}

function ensure_driver_token_tables(PDO $conn): void
{
    $conn->exec(
        "CREATE TABLE IF NOT EXISTS driver_token_purchases (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            reference VARCHAR(191) NOT NULL,
            package_id VARCHAR(32) NOT NULL,
            tokens INT NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            status VARCHAR(32) NOT NULL DEFAULT 'pending',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            credited_at TIMESTAMP NULL DEFAULT NULL,
            UNIQUE KEY uq_driver_token_ref (reference),
            KEY idx_driver_token_user (user_id),
            KEY idx_driver_token_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    try {
        $conn->exec('ALTER TABLE driver_token_purchases ADD COLUMN credited_at TIMESTAMP NULL DEFAULT NULL');
    } catch (Throwable $e) {
        // column may already exist
    }
}

/** Atomic credit — safe when many users verify at once. */
function credit_driver_tokens(PDO $conn, int $userId, int $tokens): void
{
    if ($tokens < 1 || $tokens > 100) {
        throw new RuntimeException('Invalid token credit amount');
    }
    $exists = $conn->prepare('SELECT user_id FROM drivers WHERE user_id = ? LIMIT 1 FOR UPDATE');
    $exists->execute([$userId]);
    if (! $exists->fetch()) {
        $ins = $conn->prepare(
            'INSERT INTO drivers (
                user_id, vehicle_type, vehicle_capacity, vehicle_plate,
                service_area, availability_status, booking_tokens, total_earnings
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 0)'
        );
        $ins->execute([$userId, 'Truck', '1 tonne', 'PENDING', 'Lusaka', 'available', $tokens]);

        return;
    }
    $upd = $conn->prepare(
        'UPDATE drivers SET booking_tokens = COALESCE(booking_tokens, 0) + ? WHERE user_id = ?'
    );
    $upd->execute([$tokens, $userId]);
}

function driver_user_is_valid(PDO $conn, int $userId): bool
{
    $stmt = $conn->prepare(
        'SELECT id FROM users WHERE id = ? AND (is_banned IS NULL OR is_banned = 0) LIMIT 1'
    );
    $stmt->execute([$userId]);

    return (bool) $stmt->fetch();
}

function package_for_amount(array $packages, float $amount): ?array
{
    foreach ($packages as $pkg) {
        if (abs($amount - (float) $pkg['price']) < 0.011) {
            return $pkg;
        }
    }

    return null;
}

/**
 * Confirm Lenco success + credit exactly once (concurrent-safe).
 *
 * @return array{ok:bool,status:string,message:string,tokens?:int,booking_tokens?:int}
 */
function settle_driver_token_purchase(
    PDO $conn,
    array $packages,
    int $userId,
    string $reference,
    array $lencoData
): array {
    $payStatus = strtolower((string) ($lencoData['status'] ?? ''));
    // Only hard-success statuses credit tokens (pending must NOT credit — prevents free tokens).
    $successStatuses = ['successful', 'success', 'completed', 'paid', 'approved'];
    if (! in_array($payStatus, $successStatuses, true)) {
        return [
            'ok' => false,
            'status' => $payStatus !== '' ? $payStatus : 'pending',
            'message' => 'Payment is '.$payStatus.'. Tokens will be added when Lenco confirms success.',
        ];
    }

    $paidAmount = isset($lencoData['amount']) ? (float) $lencoData['amount'] : 0.0;
    $lencoRef = (string) ($lencoData['lencoReference'] ?? $lencoData['reference'] ?? $reference);

    $conn->beginTransaction();
    try {
        // Serialize concurrent verify calls for the same reference.
        $lockName = 'drvtok_'.substr(hash('sha256', $reference), 0, 48);
        $lock = $conn->query("SELECT GET_LOCK(".$conn->quote($lockName).", 8)")->fetchColumn();
        if ((int) $lock !== 1) {
            $conn->rollBack();

            return ['ok' => false, 'status' => 'busy', 'message' => 'Payment is being processed. Retry shortly.'];
        }

        $pending = $conn->prepare(
            'SELECT * FROM driver_token_purchases WHERE reference = ? LIMIT 1 FOR UPDATE'
        );
        $pending->execute([$reference]);
        $row = $pending->fetch();

        if ($row && (int) $row['user_id'] !== $userId) {
            $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
            $conn->rollBack();

            return ['ok' => false, 'status' => 'error', 'message' => 'Reference does not belong to this account'];
        }

        if (! $row) {
            // Only attach a brand-new successful Lenco payment to a matching package amount.
            $pkg = package_for_amount($packages, $paidAmount);
            if ($pkg === null) {
                $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
                $conn->rollBack();

                return ['ok' => false, 'status' => 'error', 'message' => 'Unknown or unmatched payment amount'];
            }
            $ins = $conn->prepare(
                "INSERT INTO driver_token_purchases
                    (user_id, reference, package_id, tokens, amount, status)
                 VALUES (?, ?, ?, ?, ?, 'pending')"
            );
            $ins->execute([$userId, $reference, $pkg['id'], $pkg['tokens'], $pkg['price']]);
            $pending->execute([$reference]);
            $row = $pending->fetch();
        }

        if (! $row) {
            $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
            $conn->rollBack();

            return ['ok' => false, 'status' => 'error', 'message' => 'Unknown token purchase reference'];
        }

        // Force server package amounts (never trust stored tokens if package_id known).
        $pkg = $packages[$row['package_id']] ?? package_for_amount($packages, (float) $row['amount']);
        if ($pkg === null) {
            $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
            $conn->rollBack();

            return ['ok' => false, 'status' => 'error', 'message' => 'Invalid package on purchase'];
        }

        if ($paidAmount > 0 && abs($paidAmount - (float) $pkg['price']) > 0.05) {
            $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
            $conn->rollBack();

            return ['ok' => false, 'status' => 'error', 'message' => 'Paid amount does not match package price'];
        }

        if (($row['status'] ?? '') === 'successful') {
            $bal = $conn->prepare('SELECT booking_tokens FROM drivers WHERE user_id = ? LIMIT 1');
            $bal->execute([$userId]);
            $balance = (int) (($bal->fetch()['booking_tokens'] ?? 0));
            $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
            $conn->commit();

            return [
                'ok' => true,
                'status' => 'success',
                'message' => 'Tokens already credited',
                'tokens' => (int) $pkg['tokens'],
                'booking_tokens' => $balance,
            ];
        }

        // Flip pending → successful atomically so a second request cannot credit again.
        $claim = $conn->prepare(
            "UPDATE driver_token_purchases
                SET status = 'successful',
                    tokens = ?,
                    amount = ?,
                    package_id = ?,
                    credited_at = NOW()
              WHERE id = ? AND status = 'pending'"
        );
        $claim->execute([
            (int) $pkg['tokens'],
            (float) $pkg['price'],
            $pkg['id'],
            (int) $row['id'],
        ]);
        if ($claim->rowCount() !== 1) {
            $bal = $conn->prepare('SELECT booking_tokens FROM drivers WHERE user_id = ? LIMIT 1');
            $bal->execute([$userId]);
            $balance = (int) (($bal->fetch()['booking_tokens'] ?? 0));
            $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
            $conn->commit();

            return [
                'ok' => true,
                'status' => 'success',
                'message' => 'Tokens already credited',
                'tokens' => (int) $pkg['tokens'],
                'booking_tokens' => $balance,
            ];
        }

        credit_driver_tokens($conn, $userId, (int) $pkg['tokens']);

        try {
            $tx = $conn->prepare(
                "UPDATE transactions SET status = 'successful', lenco_reference = ? WHERE reference = ?"
            );
            $tx->execute([$lencoRef, $reference]);
        } catch (Throwable $e) {
        }

        $bal = $conn->prepare('SELECT booking_tokens FROM drivers WHERE user_id = ? LIMIT 1');
        $bal->execute([$userId]);
        $balance = (int) (($bal->fetch()['booking_tokens'] ?? 0));

        $conn->query('SELECT RELEASE_LOCK('.$conn->quote($lockName).')');
        $conn->commit();

        return [
            'ok' => true,
            'status' => 'success',
            'message' => 'Payment successful — tokens added',
            'tokens' => (int) $pkg['tokens'],
            'booking_tokens' => $balance,
        ];
    } catch (Throwable $e) {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }

        return ['ok' => false, 'status' => 'error', 'message' => 'Could not credit tokens'];
    }
}

try {
    $conn = new PDO(
        'mysql:host='.DB_HOST.';dbname='.DB_NAME.';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
    ensure_driver_token_tables($conn);
} catch (PDOException $e) {
    header('Content-Type: application/json');
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed']);
    exit;
}

$raw = file_get_contents('php://input');
$data = [];
if (! empty($raw)) {
    $json = json_decode($raw, true);
    if (is_array($json)) {
        $data = $json;
    } else {
        parse_str($raw, $data);
    }
}
if (empty($data)) {
    $data = $_REQUEST;
}

$action = preg_replace('/[^a-z_]/', '', strtolower((string) ($data['action'] ?? $_GET['action'] ?? '')));
$user_id = (int) ($data['user_id'] ?? $_GET['user_id'] ?? 0);
$packages = driver_token_packages();
$clientIp = driver_token_client_ip();

// Global soft limit — many real buyers OK; blocks floods.
driver_token_rate_limit('ip:'.$clientIp, 120, 60);

if ($action === 'packages') {
    header('Content-Type: application/json');
    echo json_encode([
        'status' => 'success',
        'packages' => array_values($packages),
    ]);
    exit;
}

if ($user_id <= 0) {
    driver_token_json_error('User ID is required');
}

if (! driver_user_is_valid($conn, $user_id)) {
    driver_token_json_error('Invalid or banned account', 403);
}

// Per-user limit on mutating actions.
if (in_array($action, ['initiate', 'verify', 'pay_page'], true)) {
    driver_token_rate_limit('user:'.$user_id.':'.$action, 40, 60);
}

if ($action === 'get_balance') {
    header('Content-Type: application/json');
    $stmt = $conn->prepare('SELECT booking_tokens FROM drivers WHERE user_id = ? LIMIT 1');
    $stmt->execute([$user_id]);
    $row = $stmt->fetch();
    echo json_encode([
        'status' => 'success',
        'booking_tokens' => (int) ($row['booking_tokens'] ?? 0),
        'packages' => array_values($packages),
    ]);
    exit;
}

if ($action === 'history') {
    header('Content-Type: application/json');
    $stmt = $conn->prepare(
        'SELECT id, package_id, tokens, amount, status, reference, created_at
         FROM driver_token_purchases WHERE user_id = ? ORDER BY created_at DESC LIMIT 50'
    );
    $stmt->execute([$user_id]);
    echo json_encode(['status' => 'success', 'data' => $stmt->fetchAll()]);
    exit;
}

if ($action === 'initiate') {
    header('Content-Type: application/json');
    driver_token_rate_limit('initiate:'.$clientIp, 20, 60);
    $packageId = strtolower(trim((string) ($data['package_id'] ?? 'starter')));
    $pkg = $packages[$packageId] ?? null;
    if ($pkg === null) {
        driver_token_json_error('Invalid package');
    }
    $phone = preg_replace('/\D+/', '', (string) ($data['phone'] ?? ''));
    $operator = strtolower(preg_replace('/[^a-z]/', '', (string) ($data['operator'] ?? 'mtn')));
    $country = strtolower(preg_replace('/[^a-z]/', '', (string) ($data['country'] ?? 'zm')));
    if (strlen($phone) < 9 || strlen($phone) > 15) {
        driver_token_json_error('Phone number is required');
    }
    if (! in_array($operator, ['mtn', 'airtel', 'zamtel', 'tnm', 'airtel_money'], true)) {
        $operator = 'mtn';
    }
    if (! in_array($country, ['zm', 'mw'], true)) {
        $country = 'zm';
    }
    // Server price only — ignore any client-supplied amount/tokens.
    $amount = (float) $pkg['price'];
    $currency = 'ZMW';
    $lenco = new LencoAPI();
    $response = $lenco->initiateMobileMoney($amount, $currency, $phone, $operator, $country);
    if (isset($response['status']) && $response['status'] === true) {
        $reference = (string) ($response['data']['reference'] ?? $response['data']['id'] ?? '');
        if ($reference === '') {
            $reference = 'DRVTOK-'.$pkg['id'].'-'.$user_id.'-'.bin2hex(random_bytes(6));
        }
        try {
            $stmt = $conn->prepare(
                "INSERT INTO driver_token_purchases (user_id, reference, package_id, tokens, amount, status)
                 VALUES (?, ?, ?, ?, ?, 'pending')"
            );
            $stmt->execute([$user_id, $reference, $pkg['id'], $pkg['tokens'], $amount]);
            try {
                $tx = $conn->prepare(
                    "INSERT INTO transactions (user_id, reference, amount, currency, status, payment_method, message)
                     VALUES (?, ?, ?, ?, 'pending', 'mobile-money', ?)"
                );
                $tx->execute([
                    $user_id,
                    $reference,
                    $amount,
                    $currency,
                    'Driver tokens '.$pkg['tokens'].' ('.$pkg['id'].')',
                ]);
            } catch (Exception $e) {
                // transactions table optional
            }
            echo json_encode([
                'status' => 'success',
                'message' => 'Payment initiated. Check your phone for the prompt.',
                'reference' => $reference,
                'tokens' => $pkg['tokens'],
                'amount' => $amount,
            ]);
        } catch (Exception $e) {
            driver_token_json_error('Database error', 500);
        }
    } else {
        echo json_encode([
            'status' => 'error',
            'message' => $response['message'] ?? 'Lenco API failed to initiate payment',
        ]);
    }
    exit;
}

if ($action === 'verify') {
    header('Content-Type: application/json');
    driver_token_rate_limit('verify:'.$clientIp, 60, 60);
    $reference = preg_replace('/[^A-Za-z0-9_\-.]/', '', (string) ($data['reference'] ?? $_GET['reference'] ?? ''));
    if ($reference === '' || strlen($reference) > 120) {
        driver_token_json_error('Reference is required');
    }

    $lenco = new LencoAPI();
    $result = $lenco->verifyTransaction($reference);

    if (! (isset($result['status']) && $result['status'] === true)) {
        echo json_encode(['status' => 'error', 'message' => 'Verification failed']);
        exit;
    }

    $resData = is_array($result['data'] ?? null) ? $result['data'] : [];
    $settled = settle_driver_token_purchase($conn, $packages, $user_id, $reference, $resData);

    if ($settled['ok']) {
        echo json_encode([
            'status' => 'success',
            'message' => $settled['message'],
            'tokens_added' => $settled['tokens'] ?? 0,
            'booking_tokens' => $settled['booking_tokens'] ?? 0,
            // Keep aliases used by the pay_page JS success checks.
            'tokens' => $settled['tokens'] ?? 0,
        ]);
        exit;
    }

    echo json_encode([
        'status' => $settled['status'],
        'message' => $settled['message'],
    ]);
    exit;
}

if ($action === 'pay_page') {
    $packageId = strtolower(trim((string) ($_REQUEST['package_id'] ?? 'starter')));
    if (! isset($packages[$packageId])) {
        $packageId = 'starter';
    }
    $pkg = $packages[$packageId];
    $phone = $_REQUEST['phone'] ?? '0970000000';
    $email = $_REQUEST['email'] ?? 'driver@houserent.site';
    $name = $_REQUEST['name'] ?? 'Driver';
    // Cryptographically unique reference (harder to guess / replay).
    $reference = 'DRVTOK-'.$packageId.'-'.$user_id.'-'.bin2hex(random_bytes(8));
    $amount = (float) $pkg['price'];
    $tokens = (int) $pkg['tokens'];

    // Store pending with server package price/tokens only.
    try {
        $stmt = $conn->prepare(
            "INSERT INTO driver_token_purchases (user_id, reference, package_id, tokens, amount, status)
             VALUES (?, ?, ?, ?, ?, 'pending')
             ON DUPLICATE KEY UPDATE package_id = VALUES(package_id), tokens = VALUES(tokens), amount = VALUES(amount)"
        );
        $stmt->execute([$user_id, $reference, $pkg['id'], $tokens, $amount]);
    } catch (Exception $e) {
    }

    $nameParts = explode(' ', $name);
    $firstName = $nameParts[0];
    $lastName = isset($nameParts[1]) ? $nameParts[1] : 'Driver';
    $publicKey = defined('LENCO_SECRET') ? LENCO_SECRET : (defined('LENCO_KEY') ? LENCO_KEY : 'YOUR_PUBLIC_KEY');
    $amount_lowest_denom = $amount;
    $autoOpen = (string) ($_REQUEST['auto'] ?? '') === '1';
    ?>
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <!-- Same CSP style as tenant_contact_payment — allow Lenco checkout frames. -->
    <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; script-src * 'unsafe-inline' 'unsafe-eval'; style-src * 'unsafe-inline'; img-src * data: blob:; connect-src *; frame-src *; child-src *;">
    <title>Buy driver tokens</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.5/font/bootstrap-icons.css">
    <style>
        body { font-family: Arial, sans-serif; background: #111; color: #fff; }
        .pkg { border: 2px solid #333; border-radius: 16px; padding: 14px; cursor: pointer; background: #1a1a1a; }
        .pkg.active { border-color: #FFC107; background: rgba(255,193,7,.12); }
        .card-dark { background: #1a1a1a; color: #fff; }
    </style>
    <script src="https://pay.lenco.co/js/v1/inline.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
</head>
<body>
<div class="container py-4">
    <div class="row justify-content-center">
        <div class="col-md-6 col-lg-5">
            <div class="text-center mb-3">
                <h2 class="fw-bold text-warning">Buy tokens</h2>
                <p class="text-secondary mb-0">Unlock moving requests · HouseRent Africa</p>
            </div>

            <div class="row g-2 mb-3" id="packagePicker">
                <?php foreach ($packages as $p) { ?>
                <div class="col-4">
                    <div class="pkg text-center <?php echo $p['id'] === $packageId ? 'active' : ''; ?>"
                         data-id="<?php echo htmlspecialchars($p['id']); ?>"
                         data-label="<?php echo htmlspecialchars($p['label']); ?>"
                         data-price="<?php echo (float) $p['price']; ?>"
                         data-tokens="<?php echo (int) $p['tokens']; ?>"
                         onclick="selectPackage(this)">
                        <div class="small text-secondary"><?php echo htmlspecialchars($p['label']); ?></div>
                        <div class="fw-bold"><?php echo (int) $p['tokens']; ?> tokens</div>
                        <div class="text-warning fw-bold">K<?php echo number_format((float) $p['price'], 0); ?></div>
                    </div>
                </div>
                <?php } ?>
            </div>

            <div class="card border-0 shadow rounded-3 card-dark" id="paymentCard">
                <div class="card-body p-4 text-center">
                    <h5 class="fw-bold text-warning mb-2" id="pkgLabel"><?php echo htmlspecialchars($pkg['label']); ?></h5>
                    <h1 class="display-5 fw-bold mb-0" id="pkgPrice">ZMW <?php echo number_format($amount, 2); ?></h1>
                    <p class="text-secondary mb-4" id="pkgTokens"><?php echo $tokens; ?> booking tokens</p>

                    <form id="paymentForm" class="text-start">
                        <div class="mb-3">
                            <label class="form-label fw-bold">Choose Method</label>
                            <select class="form-select" id="payment_method" onchange="togglePaymentFields()">
                                <option value="card">Credit / Debit Card</option>
                                <option value="mobile-money">Mobile Money (Airtel / MTN / Zamtel)</option>
                            </select>
                        </div>
                        <div id="mobile_money_fields" style="display:none;" class="bg-dark border border-secondary p-3 rounded mb-3">
                            <div class="mb-3">
                                <label class="form-label small text-uppercase fw-bold">Country</label>
                                <select class="form-select" id="country">
                                    <option value="zm" data-code="260" selected>Zambia (+260)</option>
                                    <option value="mw" data-code="265">Malawi (+265)</option>
                                </select>
                            </div>
                            <div class="mb-0">
                                <label class="form-label small text-uppercase fw-bold">Mobile Number</label>
                                <input type="text" class="form-control" id="phoneInput" placeholder="e.g. 097xxxxxxx" value="<?php echo htmlspecialchars($phone); ?>">
                            </div>
                        </div>
                        <div class="d-grid mt-3">
                            <button type="button" id="payButton" class="btn btn-warning btn-lg fw-bold" onclick="initiateLencoPayment()">Proceed to Pay</button>
                        </div>
                        <p class="text-danger text-center fw-bold small mt-3 mb-0">Stay on this page until payment finishes.</p>
                    </form>
                </div>
            </div>

            <div class="card border-0 shadow rounded-3 text-center mt-4 card-dark" id="successCard" style="display:none;">
                <div class="card-body p-5">
                    <i class="bi bi-check-circle-fill text-success mb-3" style="font-size: 4rem;"></i>
                    <h3 class="fw-bold mb-3">Tokens added!</h3>
                    <p class="text-secondary mb-4" id="successMsg">Your booking tokens were credited.</p>
                    <div class="d-grid">
                        <button type="button" class="btn btn-success btn-lg fw-bold" onclick="finishPayment()">Back to app</button>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
var selectedPackageId = <?php echo json_encode($packageId); ?>;
var selectedPrice = <?php echo json_encode($amount); ?>;
var selectedTokens = <?php echo json_encode($tokens); ?>;
var payReference = <?php echo json_encode($reference); ?>;
var userId = <?php echo (int) $user_id; ?>;

function selectPackage(el) {
    document.querySelectorAll('.pkg').forEach(function (n) { n.classList.remove('active'); });
    el.classList.add('active');
    selectedPackageId = el.getAttribute('data-id');
    selectedPrice = parseFloat(el.getAttribute('data-price'));
    selectedTokens = parseInt(el.getAttribute('data-tokens'), 10);
    var label = el.getAttribute('data-label') || selectedPackageId;
    payReference = 'DRVTOK-' + selectedPackageId + '-' + userId + '-' + Date.now() + '-' + Math.random().toString(16).slice(2, 8);
    document.getElementById('pkgLabel').innerText = label;
    document.getElementById('pkgPrice').innerText = 'ZMW ' + selectedPrice.toFixed(2);
    document.getElementById('pkgTokens').innerText = selectedTokens + ' booking token' + (selectedTokens === 1 ? '' : 's');
}

function togglePaymentFields() {
    var method = document.getElementById('payment_method').value;
    document.getElementById('mobile_money_fields').style.display =
        method === 'mobile-money' ? 'block' : 'none';
}

function resetPayButton() {
    var btn = document.getElementById('payButton');
    if (!btn) return;
    btn.innerHTML = 'Proceed to Pay';
    btn.disabled = false;
}

function initiateLencoPayment() {
    if (typeof LencoPay === 'undefined') {
        alert('Payment system is loading. Check internet and try again.');
        return;
    }
    var method = document.getElementById('payment_method').value;
    var customerPhone = <?php echo json_encode($phone); ?>;
    // Same as tenant life/pay: pass both channels so Lenco UI can open.
    var channels = ["card", "mobile-money"];
    if (method === 'mobile-money') {
        var inputPhone = document.getElementById('phoneInput').value;
        if (!inputPhone) {
            alert('Please enter a valid mobile money number.');
            return;
        }
        var cleanPhone = inputPhone.replace(/\D/g, '');
        if (!cleanPhone.startsWith('0') && cleanPhone.length === 9) cleanPhone = '0' + cleanPhone;
        customerPhone = cleanPhone;
    }
    var btn = document.getElementById('payButton');
    btn.innerHTML = 'Opening Lenco...';
    btn.disabled = true;
    try {
        LencoPay.getPaid({
            key: <?php echo json_encode($publicKey); ?>,
            reference: payReference,
            email: <?php echo json_encode($email); ?>,
            amount: selectedPrice,
            currency: "ZMW",
            color: "#FFC107",
            channels: channels,
            customer: {
                firstName: <?php echo json_encode($firstName); ?>,
                lastName: <?php echo json_encode($lastName); ?>,
                phone: customerPhone || '0971111111'
            },
            onSuccess: function (response) {
                btn.innerHTML = 'Verifying Payment...';
                // Absolute path — works for /api/driver_token_payment (no .php).
                $.ajax({
                    url: '/api/driver_token_payment?action=verify'
                        + '&user_id=' + userId
                        + '&package_id=' + encodeURIComponent(selectedPackageId)
                        + '&reference=' + encodeURIComponent(response.reference || payReference),
                    method: 'get',
                    dataType: 'json',
                    success: function (verifyResponse) {
                        // Only treat hard success as credited (API no longer credits on pending).
                        if (verifyResponse && verifyResponse.status === 'success') {
                            document.getElementById('paymentCard').style.display = 'none';
                            document.getElementById('packagePicker').style.display = 'none';
                            var added = verifyResponse.tokens_added || selectedTokens;
                            document.getElementById('successMsg').innerText = '+' + added + ' tokens added to your account.';
                            document.getElementById('successCard').style.display = 'block';
                            window.successfulPaymentRef = response.reference || payReference;
                        } else {
                            alert('Payment status: ' + ((verifyResponse && verifyResponse.message) || 'Unknown'));
                            resetPayButton();
                        }
                    },
                    error: function () {
                        alert('Could not verify payment. Please check tokens in the app.');
                        resetPayButton();
                    }
                });
            },
            onClose: function () {
                resetPayButton();
            },
            onConfirmationPending: function () {
                alert('Purchase will complete when payment is confirmed.');
                resetPayButton();
            }
        });
        // getPaid returned — checkout UI is open. Do NOT alert "did not open"
        // while the user is still paying (that old 12s timer was a false alarm).
        btn.innerHTML = 'Complete payment in Lenco…';
    } catch (error) {
        alert('Payment initiation failed: ' + (error && error.message ? error.message : error));
        resetPayButton();
    }
}

function finishPayment() {
    window.location.href = 'houserent://payment-success';
}

// Auto-open Lenco (Flutter passes auto=1) — same feel as tenant life/pay.
<?php if ($autoOpen) { ?>
(function waitForLenco() {
    var tries = 0;
    var t = setInterval(function () {
        tries++;
        if (typeof LencoPay !== 'undefined') {
            clearInterval(t);
            initiateLencoPayment();
        } else if (tries > 40) {
            clearInterval(t);
            // Keep form usable if SDK is slow.
        }
    }, 250);
})();
<?php } ?>
</script>
</body>
</html>
    <?php
    exit;
}

header('Content-Type: application/json');
echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
