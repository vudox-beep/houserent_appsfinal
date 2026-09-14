<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

ini_set('display_errors', '0');
ini_set('log_errors', '1');
require_once __DIR__ . '/../config/config.php';
// config.php enables display_errors for normal pages; APIs must always return
// clean JSON instead of HTML warnings.
ini_set('display_errors', '0');

// Withdrawals require email OTP (6-digit code).
if (! defined('RENT_SAVINGS_REQUIRE_WITHDRAW_OTP')) {
    define('RENT_SAVINGS_REQUIRE_WITHDRAW_OTP', true);
}
// TESTING: set to false to block tenant deposits again.
if (! defined('RENT_SAVINGS_DEPOSITS_ENABLED')) {
    define('RENT_SAVINGS_DEPOSITS_ENABLED', true);
}
// Lock days enforced: only unlocked deposits are withdrawable.
if (! defined('RENT_SAVINGS_IGNORE_LOCK')) {
    define('RENT_SAVINGS_IGNORE_LOCK', false);
}
// TESTING: flip recent failed withdrawals to completed so paid-out money reduces balance.
// Keep OFF in production — otherwise failed payouts can wrongly drain tenant balances.
if (! defined('RENT_SAVINGS_REPAIR_FAILED_WITHDRAWALS')) {
    define('RENT_SAVINGS_REPAIR_FAILED_WITHDRAWALS', false);
}
// Max single deposit / withdrawal (ZMW) to limit abuse.
if (! defined('RENT_SAVINGS_MAX_DEPOSIT')) {
    define('RENT_SAVINGS_MAX_DEPOSIT', 50000.00);
}
if (! defined('RENT_SAVINGS_MAX_WITHDRAW')) {
    define('RENT_SAVINGS_MAX_WITHDRAW', 50000.00);
}
// Payment link lifetime for pay_page (seconds).
if (! defined('RENT_SAVINGS_PAY_LINK_TTL')) {
    define('RENT_SAVINGS_PAY_LINK_TTL', 172800); // 48 hours
}
// Withdrawal fee for ALL new withdrawals: platform K20 + Lenco K8.50 = K28.50.
if (! defined('RENT_SAVINGS_PLATFORM_FEE')) {
    define('RENT_SAVINGS_PLATFORM_FEE', 20.00);
}
if (! defined('RENT_SAVINGS_LENCO_FEE')) {
    define('RENT_SAVINGS_LENCO_FEE', 8.50);
}
if (! defined('RENT_SAVINGS_WITHDRAWAL_FEE')) {
    define(
        'RENT_SAVINGS_WITHDRAWAL_FEE',
        (float) RENT_SAVINGS_PLATFORM_FEE + (float) RENT_SAVINGS_LENCO_FEE
    );
}
// Rows created before this timestamp keep the old testing fee (K8.50) if fee was 0.
if (! defined('RENT_SAVINGS_FULL_FEE_SINCE')) {
    define('RENT_SAVINGS_FULL_FEE_SINCE', '2026-08-06 12:10:00');
}

if (!class_exists('RentFundsLenco')) {
    class RentFundsLenco {
        private $baseUrl;
        private $apiKey;
        private $publicKey;

        public function __construct() {
            $this->baseUrl = rtrim(str_replace('`', '', (string) $this->config(
                'RENT_FUNDS_LENCO_BASE_URL',
                $this->config('LENCO_BASE_URL', 'https://api.lenco.co/access/v2')
            )), '/');
            // Prefer rent-funds key; fall back to main LENCO_KEY (same as admin withdrawals).
            $this->apiKey = trim((string) $this->config(
                'RENT_FUNDS_LENCO_API_KEY',
                $this->config('LENCO_KEY', '')
            ));
            $this->publicKey = trim((string) $this->config(
                'RENT_FUNDS_LENCO_PUBLIC_KEY',
                $this->config('LENCO_SECRET', '')
            ));
        }

        private function config(string $name, string $fallback): string {
            if (defined($name)) {
                return (string) constant($name);
            }
            $environmentValue = getenv($name);

            return $environmentValue === false || trim($environmentValue) === ''
                ? $fallback
                : (string) $environmentValue;
        }

        private function authorizationHeader(): string {
            $key = (string) $this->apiKey;
            if ($key !== '' && stripos($key, 'bearer ') !== 0) {
                return 'Bearer '.$key;
            }

            return $key;
        }

        private function request(string $method, string $endpoint, array $data = []): array {
            if ($this->apiKey === '') {
                return ['status' => false, 'message' => 'Lenco API key is not configured.'];
            }
            $url = $this->baseUrl.$endpoint;
            $ch = curl_init($url);
            $headers = [
                'Authorization: '.$this->authorizationHeader(),
                'Content-Type: application/json',
                'Accept: application/json',
            ];
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_SSL_VERIFYPEER => true,
                CURLOPT_CONNECTTIMEOUT => 12,
                CURLOPT_TIMEOUT => 60,
            ]);
            if (strtoupper($method) === 'POST') {
                curl_setopt($ch, CURLOPT_POST, true);
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
            }
            $raw = curl_exec($ch);
            $error = curl_error($ch);
            $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($raw === false) {
                return ['status' => false, 'message' => $error !== '' ? $error : 'Could not reach Lenco.', 'http' => $httpCode];
            }
            $decoded = json_decode((string) $raw, true);
            if (! is_array($decoded)) {
                return ['status' => false, 'message' => 'Invalid response from Lenco.', 'http' => $httpCode, 'raw' => substr((string) $raw, 0, 500)];
            }
            $decoded['http'] = $httpCode;

            return $decoded;
        }

        public function publicKey(): string {
            if ($this->publicKey === '' || strpos($this->publicKey, 'pub-') !== 0) {
                throw new RuntimeException('Rent Funds public payment key is not configured.');
            }

            return $this->publicKey;
        }

        public function verifyCollection(string $reference): array {
            return $this->request('GET', '/collections/status/'.rawurlencode($reference));
        }

        public function getAccounts(): array {
            return $this->request('GET', '/accounts');
        }

        /**
         * Pick active ZMW wallet accountId using full wallet funds (currentBalance preferred).
         *
         * @return array{ok:bool,account_id:?string,funds:float,message:string}
         */
        public function pickZmwDebitAccount(float $neededAmount): array {
            $accountsResponse = $this->getAccounts();
            if (($accountsResponse['status'] ?? false) !== true || ! is_array($accountsResponse['data'] ?? null)) {
                return [
                    'ok' => false,
                    'account_id' => null,
                    'funds' => 0.0,
                    'message' => 'The Lenco wallet balance could not be verified.',
                ];
            }
            $accounts = $accountsResponse['data'];
            if (! isset($accounts[0]) && (isset($accounts['availableBalance']) || isset($accounts['currentBalance']))) {
                $accounts = [$accounts];
            }
            $debitAccountId = '';
            $bestFunds = -1.0;
            foreach ($accounts as $account) {
                if (! is_array($account)) {
                    continue;
                }
                if (strtoupper((string) ($account['currency'] ?? 'ZMW')) !== 'ZMW') {
                    continue;
                }
                if (strtolower((string) ($account['status'] ?? 'active')) !== 'active') {
                    continue;
                }
                $current = (float) ($account['currentBalance'] ?? 0);
                $available = (float) ($account['availableBalance'] ?? 0);
                $funds = max($current, $available);
                if (! empty($account['id']) && $funds > $bestFunds) {
                    $bestFunds = $funds;
                    $debitAccountId = (string) $account['id'];
                }
            }
            if ($debitAccountId === '' || $bestFunds <= 0) {
                return [
                    'ok' => false,
                    'account_id' => null,
                    'funds' => 0.0,
                    'message' => 'No active ZMW Lenco wallet was found.',
                ];
            }
            if ($neededAmount > $bestFunds) {
                return [
                    'ok' => false,
                    'account_id' => $debitAccountId,
                    'funds' => round($bestFunds, 2),
                    'message' => 'Insufficient funds. Lenco wallet has K'
                        .number_format($bestFunds, 2)
                        .', but this withdrawal needs K'
                        .number_format($neededAmount, 2).'.',
                ];
            }

            return [
                'ok' => true,
                'account_id' => $debitAccountId,
                'funds' => round($bestFunds, 2),
                'message' => 'ok',
            ];
        }

        /** Same shape as admin withdrawal: POST /transfers/mobile-money */
        public function transferMobileMoney(
            string $accountId,
            float $amount,
            string $phone,
            string $operator,
            string $country,
            string $reference,
            string $narration
        ): array {
            $payload = [
                'accountId' => $accountId,
                'amount' => round($amount, 2),
                'narration' => $narration,
                'reference' => $reference,
                'phone' => $phone,
                'operator' => strtolower($operator),
                'country' => strtolower($country),
            ];
            $response = $this->request('POST', '/transfers/mobile-money', $payload);
            if (! is_array($response)) {
                return ['status' => false, 'message' => 'Invalid Lenco transfer response.', '_request' => $payload];
            }
            $response['_request'] = $payload;

            return $response;
        }
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function rentSavingsSecurityHeaders(bool $html = false): void {
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: no-referrer');
    header('Permissions-Policy: geolocation=(), microphone=(), camera=()');
    header('Cache-Control: no-store, no-cache, must-revalidate');
    if ($html) {
        header("Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline' https://pay.lenco.co; style-src 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://pay.lenco.co https://api.lenco.co; frame-src https://pay.lenco.co; base-uri 'none'; form-action 'none'");
    }
}

function rentSavingsSigningSecret(): string {
    if (defined('JWT_SECRET') && (string) JWT_SECRET !== '') {
        return (string) JWT_SECRET;
    }
    if (defined('APP_KEY') && (string) APP_KEY !== '') {
        return (string) APP_KEY;
    }
    // Same secret the app already uses for JWT / payment links.
    return 'supersecretkey_houserentafrica';
}

function rentSavingsResponse(array $payload, int $code = 200): void {
    rentSavingsSecurityHeaders(false);
    header('Content-Type: application/json; charset=UTF-8');
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function rentSavingsBase64UrlDecode(string $value): string {
    $padding = strlen($value) % 4;
    if ($padding > 0) $value .= str_repeat('=', 4 - $padding);
    $decoded = base64_decode(strtr($value, '-_', '+/'), true);
    return is_string($decoded) ? $decoded : '';
}

/** Simple file-backed rate limit (shared hosting safe). */
function rentSavingsRateLimit(string $key, int $maxHits, int $windowSeconds): void {
    $safeKey = preg_replace('/[^a-zA-Z0-9._-]/', '_', $key) ?: 'unknown';
    $dir = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'rent_savings_rl';
    if (! is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }
    $file = $dir . DIRECTORY_SEPARATOR . $safeKey . '.json';
    $now = time();
    $hits = [];
    $fp = @fopen($file, 'c+');
    if (! $fp) {
        return;
    }
    try {
        flock($fp, LOCK_EX);
        $raw = stream_get_contents($fp);
        $decoded = json_decode((string) $raw, true);
        if (is_array($decoded)) {
            foreach ($decoded as $ts) {
                if (is_int($ts) && $ts > ($now - $windowSeconds)) {
                    $hits[] = $ts;
                }
            }
        }
        if (count($hits) >= $maxHits) {
            flock($fp, LOCK_UN);
            fclose($fp);
            header('Retry-After: ' . max(1, $windowSeconds));
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Too many requests. Please wait and try again.',
            ], 429);
        }
        $hits[] = $now;
        ftruncate($fp, 0);
        rewind($fp);
        fwrite($fp, json_encode($hits));
        fflush($fp);
        flock($fp, LOCK_UN);
        fclose($fp);
    } catch (Throwable $e) {
        @flock($fp, LOCK_UN);
        @fclose($fp);
    }
}

function rentSavingsIsValidDepositReference(string $reference): bool {
    return (bool) preg_match('/^SAV-\d+-[a-f0-9]{10}$/', $reference);
}

function rentSavingsPaymentSignature(string $reference): string {
    return hash_hmac('sha256', $reference, rentSavingsSigningSecret());
}

function rentSavingsTenant(?PDO $conn = null): array {
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $authorization = $headers['Authorization']
        ?? $headers['authorization']
        ?? ($_SERVER['HTTP_AUTHORIZATION'] ?? ($_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? ''));
    if (stripos($authorization, 'Bearer ') !== 0) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
    }

    $token = trim(substr($authorization, 7));
    if (strlen($token) > 4096) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
    }
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
    }
    $payload = json_decode(rentSavingsBase64UrlDecode($parts[1]), true);
    $expected = rtrim(strtr(base64_encode(hash_hmac(
        'sha256',
        $parts[0] . '.' . $parts[1],
        rentSavingsSigningSecret(),
        true
    )), '+/', '-_'), '=');
    if (!is_array($payload) || !hash_equals($expected, $parts[2]) ||
        empty($payload['id']) || (int)($payload['exp'] ?? 0) < time() ||
        !in_array($payload['role'] ?? '', ['user', 'tenant'], true)) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
    }

    $tenantId = (int) $payload['id'];
    if ($tenantId < 1) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
    }

    // When DB is available, ensure the user still exists and is allowed.
    if ($conn instanceof PDO) {
        try {
            $stmt = $conn->prepare(
                'SELECT id, role, is_banned FROM users WHERE id = ? LIMIT 1'
            );
            $stmt->execute([$tenantId]);
            $user = $stmt->fetch(PDO::FETCH_ASSOC);
            if (! $user) {
                rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
            }
            $role = strtolower((string) ($user['role'] ?? ''));
            if (! in_array($role, ['user', 'tenant'], true)) {
                rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
            }
            if (! empty($user['is_banned']) && (int) $user['is_banned'] === 1) {
                rentSavingsResponse(['status' => 'error', 'message' => 'Account not allowed.'], 403);
            }
        } catch (Throwable $e) {
            // If schema differs, fall back to JWT-only auth rather than breaking the API.
            error_log('Rent savings auth user check: ' . $e->getMessage());
        }
    }

    return $payload;
}

function rentSavingsLencoTransferAccepted(array $transfer): bool
{
    $top = $transfer['status'] ?? null;
    if ($top === true || $top === 1 || $top === '1') {
        return true;
    }
    if (is_string($top)) {
        $topNorm = strtolower(trim($top));
        if (in_array($topNorm, ['true', 'success', 'successful', 'ok', 'completed'], true)) {
            return true;
        }
    }

    $data = is_array($transfer['data'] ?? null) ? $transfer['data'] : [];
    $providerStatus = strtolower(trim((string) ($data['status'] ?? '')));
    if (in_array($providerStatus, ['failed', 'rejected', 'cancelled', 'canceled'], true)) {
        return false;
    }
    // Any transfer id / reference means Lenco accepted the payout request.
    if ($providerStatus !== '' || ! empty($data['id']) || ! empty($data['lencoReference']) || ! empty($data['reference'])) {
        return true;
    }

    $http = (int) ($transfer['http'] ?? 0);

    return $http >= 200 && $http < 300 && $data !== [];
}

function rentSavingsLencoTransferFailed(array $transfer): bool
{
    $top = $transfer['status'] ?? null;
    if ($top === false || $top === 0 || $top === '0' || $top === 'false') {
        $data = is_array($transfer['data'] ?? null) ? $transfer['data'] : [];
        // Only treat as hard fail when there is also no accepted transfer payload.
        if (empty($data['id']) && empty($data['lencoReference']) && empty($data['reference'])) {
            return true;
        }
    }
    $data = is_array($transfer['data'] ?? null) ? $transfer['data'] : [];
    $providerStatus = strtolower(trim((string) ($data['status'] ?? '')));

    return in_array($providerStatus, ['failed', 'rejected', 'cancelled', 'canceled'], true);
}

/**
 * Map Lenco collection status → rent_savings_transactions.status.
 * Balance only counts deposits with status = completed.
 */
function rentSavingsPaymentStatus(string $lencoStatus): string
{
    $status = strtolower(trim($lencoStatus));
    if (in_array($status, ['successful', 'success', 'completed', 'paid', 'approved'], true)) {
        return 'completed';
    }
    if (in_array($status, ['failed', 'rejected', 'cancelled', 'canceled', 'expired'], true)) {
        return 'failed';
    }
    if (in_array($status, ['pending', 'processing', 'ongoing', 'queued'], true)) {
        return 'pending';
    }

    return $status !== '' ? 'pending' : 'pending';
}

/**
 * Mark a pending deposit completed/failed from a Lenco verify payload.
 * Idempotent: already-completed rows stay completed and return success.
 *
 * @return array{ok:bool,status:string,message:string}
 */
function rentSavingsApplyDepositVerification(PDO $conn, array $deposit, array $result): array
{
    $current = strtolower(trim((string) ($deposit['status'] ?? '')));
    if ($current === 'completed') {
        return [
            'ok' => true,
            'status' => 'completed',
            'message' => 'Money already added to Rent Savings.',
        ];
    }

    if (($result['status'] ?? false) !== true) {
        return [
            'ok' => false,
            'status' => 'error',
            'message' => (string) ($result['message'] ?? 'Unable to verify this payment.'),
        ];
    }

    $data = is_array($result['data'] ?? null) ? $result['data'] : [];
    $mapped = rentSavingsPaymentStatus((string) ($data['status'] ?? 'pending'));
    $paidAmount = round((float) ($data['amount'] ?? 0), 2);
    $expectedAmount = round((float) ($deposit['amount'] ?? 0), 2);
    $paidCurrency = strtoupper(trim((string) ($data['currency'] ?? 'ZMW')));
    $providerRef = (string) ($data['lencoReference'] ?? $data['reference'] ?? $deposit['reference'] ?? '');

    if ($mapped === 'completed') {
        // Credit only the DB deposit amount. Lenco amount must match when present.
        $amountOk = $paidAmount <= 0
            || abs($paidAmount - $expectedAmount) < 0.05;
        $currencyOk = $paidCurrency === '' || $paidCurrency === 'ZMW';
        $lencoOwnRef = trim((string) ($data['reference'] ?? ''));
        $refOk = $lencoOwnRef === ''
            || hash_equals((string) ($deposit['reference'] ?? ''), $lencoOwnRef);
        if (! $amountOk || ! $currencyOk || ! $refOk) {
            error_log(
                'Rent savings payment mismatch for ' . ($deposit['reference'] ?? '')
                . " paid={$paidAmount} {$paidCurrency} expected={$expectedAmount} ZMW"
            );

            return [
                'ok' => false,
                'status' => 'error',
                'message' => 'Payment amount could not be confirmed.',
            ];
        }
    }

    $update = $conn->prepare(
        "UPDATE rent_savings_transactions
            SET status = ?,
                provider_reference = ?,
                lock_until = CASE
                    WHEN ? = 'completed' THEN DATE_ADD(NOW(), INTERVAL GREATEST(COALESCE(lock_days, 1), 1) DAY)
                    ELSE lock_until
                END
          WHERE id = ?
            AND tenant_id = ?
            AND type = 'deposit'
            AND status IN ('pending', 'processing')"
    );
    $update->execute([
        $mapped,
        $providerRef !== '' ? $providerRef : ($deposit['reference'] ?? null),
        $mapped,
        (int) $deposit['id'],
        (int) ($deposit['tenant_id'] ?? 0),
    ]);

    if ($mapped === 'completed') {
        return [
            'ok' => true,
            'status' => 'completed',
            'message' => 'Money added to Rent Savings.',
        ];
    }
    if ($mapped === 'failed') {
        return [
            'ok' => false,
            'status' => 'failed',
            'message' => 'Payment failed.',
        ];
    }

    return [
        'ok' => false,
        'status' => $mapped,
        'message' => 'Payment is still ' . $mapped . '.',
    ];
}

/**
 * Re-check recent pending deposits with Lenco (closed WebView / failed confirm).
 * Fixes "money left phone but balance did not show".
 */
function rentSavingsReconcilePendingDeposits(PDO $conn, int $tenantId): void
{
    try {
        $stmt = $conn->prepare(
            "SELECT id, tenant_id, amount, status, reference, lock_days, lock_until
               FROM rent_savings_transactions
              WHERE tenant_id = ?
                AND type = 'deposit'
                AND status = 'pending'
                AND created_at >= (NOW() - INTERVAL 14 DAY)
              ORDER BY id DESC
              LIMIT 10"
        );
        $stmt->execute([$tenantId]);
        $pending = $stmt->fetchAll(PDO::FETCH_ASSOC);
        if (! $pending) {
            return;
        }

        $gateway = new RentFundsLenco();
        foreach ($pending as $deposit) {
            $reference = trim((string) ($deposit['reference'] ?? ''));
            if ($reference === '') {
                continue;
            }
            $result = $gateway->verifyCollection($reference);
            rentSavingsApplyDepositVerification($conn, $deposit, $result);
        }
    } catch (Throwable $e) {
        error_log('Rent savings reconcile deposits: ' . $e->getMessage());
    }
}

function rentSavingsAccount(PDO $conn, int $tenantId): array {
    $stmt = $conn->prepare('SELECT id, tenant_id, rent_goal, target_date, currency FROM rent_savings_accounts WHERE tenant_id = ?');
    $stmt->execute([$tenantId]);
    $account = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($account) return $account;

    $rental = $conn->prepare("SELECT rent_amount, start_date FROM rentals WHERE tenant_id = ? AND status = 'active' ORDER BY created_at DESC LIMIT 1");
    $rental->execute([$tenantId]);
    $activeRental = $rental->fetch(PDO::FETCH_ASSOC);
    $goal = max(1, (float)($activeRental['rent_amount'] ?? 2500));
    $targetDate = null;
    if (!empty($activeRental['start_date'])) {
        $day = (int)date('d', strtotime($activeRental['start_date']));
        $today = new DateTimeImmutable('today');
        $candidate = $today->setDate(
            (int)$today->format('Y'),
            (int)$today->format('m'),
            min($day, (int)$today->format('t'))
        );
        if ($candidate < $today) {
            $next = $today->modify('first day of next month');
            $candidate = $next->setDate(
                (int)$next->format('Y'),
                (int)$next->format('m'),
                min($day, (int)$next->format('t'))
            );
        }
        $targetDate = $candidate->format('Y-m-d');
    }

    $insert = $conn->prepare('INSERT INTO rent_savings_accounts (tenant_id, rent_goal, target_date) VALUES (?, ?, ?)');
    $insert->execute([$tenantId, $goal, $targetDate]);
    return [
        'id' => $conn->lastInsertId(),
        'tenant_id' => $tenantId,
        'rent_goal' => $goal,
        'target_date' => $targetDate,
        'currency' => 'ZMW',
    ];
}

function rentSavingsBalance(PDO $conn, int $tenantId): float {
    rentSavingsRepairPaidWithdrawals($conn, $tenantId);
    $stmt = $conn->prepare("SELECT COALESCE(SUM(CASE WHEN type = 'deposit' AND status = 'completed' THEN amount WHEN type = 'withdrawal' AND status IN ('pending','processing','completed') THEN -(amount + fee) ELSE 0 END), 0) FROM rent_savings_transactions WHERE tenant_id = ?");
    $stmt->execute([$tenantId]);
    return max(0, (float)$stmt->fetchColumn());
}

/**
 * If Lenco already paid but we wrongly stored status=failed (balance stayed the same),
 * flip those rows to completed. Also fix testing-era rows that stored fee=0 while
 * Lenco cost was K8.50 (before the full K28.50 fee was enabled).
 */
function rentSavingsRepairPaidWithdrawals(PDO $conn, int $tenantId): void
{
    if (! defined('RENT_SAVINGS_REPAIR_FAILED_WITHDRAWALS') || ! RENT_SAVINGS_REPAIR_FAILED_WITHDRAWALS) {
        return;
    }
    try {
        // Any recent failed withdrawal is treated as paid during testing —
        // money already left via Lenco while status was wrongly saved as failed.
        $stmt = $conn->prepare(
            "UPDATE rent_savings_transactions
                SET status = 'completed'
              WHERE tenant_id = ?
                AND type = 'withdrawal'
                AND status = 'failed'
                AND created_at >= (NOW() - INTERVAL 14 DAY)"
        );
        $stmt->execute([$tenantId]);

        // Old testing withdrawals (before full fee): if fee was saved as 0, use Lenco K8.50 only.
        $lencoFee = (float) RENT_SAVINGS_LENCO_FEE;
        $feeFixOld = $conn->prepare(
            "UPDATE rent_savings_transactions
                SET fee = ?
              WHERE tenant_id = ?
                AND type = 'withdrawal'
                AND status IN ('completed', 'processing', 'pending')
                AND (fee IS NULL OR fee = 0)
                AND created_at < ?"
        );
        $feeFixOld->execute([$lencoFee, $tenantId, RENT_SAVINGS_FULL_FEE_SINCE]);

        // New withdrawals must always carry the full K28.50 fee.
        $fullFee = (float) RENT_SAVINGS_WITHDRAWAL_FEE;
        $feeFixNew = $conn->prepare(
            "UPDATE rent_savings_transactions
                SET fee = ?
              WHERE tenant_id = ?
                AND type = 'withdrawal'
                AND status IN ('completed', 'processing', 'pending')
                AND (fee IS NULL OR fee < ?)
                AND created_at >= ?"
        );
        $feeFixNew->execute([$fullFee, $tenantId, $fullFee, RENT_SAVINGS_FULL_FEE_SINCE]);
    } catch (Throwable $e) {
        error_log('Rent savings repair withdrawals: '.$e->getMessage());
    }
}

function rentSavingsAvailableBalance(PDO $conn, int $tenantId): float {
    // TESTING: treat all completed deposits as unlocked.
    if (defined('RENT_SAVINGS_IGNORE_LOCK') && RENT_SAVINGS_IGNORE_LOCK) {
        return rentSavingsBalance($conn, $tenantId);
    }
    rentSavingsRepairPaidWithdrawals($conn, $tenantId);
    $stmt = $conn->prepare("SELECT COALESCE(SUM(CASE WHEN type = 'deposit' AND status = 'completed' AND (lock_until IS NULL OR lock_until <= NOW()) THEN amount WHEN type = 'withdrawal' AND status IN ('pending','processing','completed') THEN -(amount + fee) ELSE 0 END), 0) FROM rent_savings_transactions WHERE tenant_id = ?");
    $stmt->execute([$tenantId]);
    return max(0, (float)$stmt->fetchColumn());
}

function rentSavingsSummary(PDO $conn, int $tenantId, float $withdrawalFee): array {
    // Catch deposits that Lenco took but confirm_deposit never finished.
    rentSavingsReconcilePendingDeposits($conn, $tenantId);
    $account = rentSavingsAccount($conn, $tenantId);
    $balance = rentSavingsBalance($conn, $tenantId);
    $availableBalance = rentSavingsAvailableBalance($conn, $tenantId);
    $history = $conn->prepare('SELECT id, type, amount, fee, net_amount, currency, status, reference, payment_method, phone, operator, lock_days, lock_until, created_at FROM rent_savings_transactions WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 50');
    $history->execute([$tenantId]);
    $nextUnlock = $conn->prepare("SELECT MIN(lock_until) FROM rent_savings_transactions WHERE tenant_id = ? AND type = 'deposit' AND status = 'completed' AND lock_until > NOW()");
    $nextUnlock->execute([$tenantId]);
    $goal = (float)$account['rent_goal'];
    $daysRemaining = null;
    if (!empty($account['target_date'])) {
        $daysRemaining = (int)(new DateTimeImmutable('today'))
            ->diff(new DateTimeImmutable($account['target_date']))
            ->format('%r%a');
    }
    $ignoreLock = defined('RENT_SAVINGS_IGNORE_LOCK') && RENT_SAVINGS_IGNORE_LOCK;
    return [
        'status' => 'success',
        'account' => $account,
        'balance' => round($balance, 2),
        'available_balance' => round($availableBalance, 2),
        'locked_balance' => $ignoreLock ? 0.0 : round(max(0, $balance - $availableBalance), 2),
        'next_unlock_date' => $ignoreLock ? null : ($nextUnlock->fetchColumn() ?: null),
        'progress' => $goal > 0 ? min(100, round(($balance / $goal) * 100, 1)) : 0,
        'days_remaining' => $daysRemaining,
        'withdrawal_fee' => $withdrawalFee,
        'platform_fee' => defined('RENT_SAVINGS_PLATFORM_FEE') ? (float) RENT_SAVINGS_PLATFORM_FEE : 20.0,
        'lenco_fee' => defined('RENT_SAVINGS_LENCO_FEE') ? (float) RENT_SAVINGS_LENCO_FEE : 8.5,
        'lock_ignored' => $ignoreLock,
        'transactions' => $history->fetchAll(PDO::FETCH_ASSOC),
    ];
}

function rentSavingsOtpPepper(): string
{
    return hash('sha256', 'houserent-rent-savings-otp|' . rentSavingsSigningSecret());
}

function rentSavingsEnsureOtpTable(PDO $conn): void
{
    $conn->exec(
        "CREATE TABLE IF NOT EXISTS rent_savings_withdraw_otps (
            id INT AUTO_INCREMENT PRIMARY KEY,
            challenge_id VARCHAR(64) NOT NULL,
            tenant_id INT NOT NULL,
            email VARCHAR(255) NOT NULL,
            code_hash CHAR(64) NOT NULL,
            intent_hash CHAR(64) NOT NULL,
            amount DECIMAL(12,2) NOT NULL,
            phone VARCHAR(32) NOT NULL,
            operator VARCHAR(20) NOT NULL,
            attempts TINYINT NOT NULL DEFAULT 0,
            max_attempts TINYINT NOT NULL DEFAULT 5,
            expires_at DATETIME NOT NULL,
            used_at DATETIME NULL DEFAULT NULL,
            request_ip VARCHAR(64) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_rent_savings_otp_challenge (challenge_id),
            KEY idx_rent_savings_otp_tenant (tenant_id),
            KEY idx_rent_savings_otp_expires (expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
}

function rentSavingsClientIp(): string
{
    // Prefer REMOTE_ADDR — X-Forwarded-For is easy to spoof on shared hosting.
    $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';

    return preg_replace('/[^0-9a-fA-F:.]/', '', (string) $ip) ?: '0.0.0.0';
}

function rentSavingsNormalizePhone(string $phone): string
{
    $digits = preg_replace('/\D+/', '', $phone) ?? '';
    if (strpos($digits, '260') === 0 && strlen($digits) >= 12) {
        $digits = '0'.substr($digits, 3);
    }
    if ($digits !== '' && $digits[0] !== '0' && strlen($digits) === 9) {
        $digits = '0'.$digits;
    }

    return $digits;
}

function rentSavingsMaskEmail(string $email): string
{
    $parts = explode('@', strtolower(trim($email)), 2);
    if (count($parts) !== 2) {
        return '***';
    }
    $name = $parts[0];
    $domain = $parts[1];
    $visible = max(1, min(2, strlen($name)));

    return substr($name, 0, $visible).str_repeat('*', max(3, strlen($name) - $visible)).'@'.$domain;
}

function rentSavingsIntentHash(int $tenantId, float $amount, string $phone, string $operator): string
{
    return hash(
        'sha256',
        $tenantId.'|'.number_format($amount, 2, '.', '').'|'.$phone.'|'.$operator
    );
}

function rentSavingsCodeHash(string $code, string $challengeId): string
{
    return hash_hmac('sha256', $code, rentSavingsOtpPepper().'|'.$challengeId);
}

function rentSavingsLoadMailer(): ?object
{
    // Same includes folder as the rest of the site (next to config/), not php_backend.
    if (! class_exists('SimpleSMTP')) {
        $smtp = __DIR__.'/../includes/SimpleSMTP.php';
        if (is_file($smtp)) {
            require_once $smtp;
        }
    }
    if (! class_exists('SimpleSMTP')) {
        error_log('Rent savings mailer: ../includes/SimpleSMTP.php missing');
        return null;
    }
    if (! defined('SMTP_HOST') || ! defined('SMTP_USER') || ! defined('SMTP_PASS')) {
        error_log('Rent savings mailer: SMTP_* missing from config');
        return null;
    }

    return new SimpleSMTP(
        SMTP_HOST,
        defined('SMTP_PORT') ? (int) SMTP_PORT : 587,
        SMTP_USER,
        SMTP_PASS
    );
}

function rentSavingsSendHtmlEmail(string $email, string $subject, string $body): bool
{
    $email = trim($email);
    if ($email === '' || ! filter_var($email, FILTER_VALIDATE_EMAIL)) {
        return false;
    }

    $site = defined('SITE_NAME') ? SITE_NAME : 'HouseRent Africa';

    // Prefer SimpleMailer (PHPMailer) from includes/ when present.
    if (! class_exists('SimpleMailer')) {
        $mailerFile = __DIR__.'/../includes/SimpleMailer.php';
        if (is_file($mailerFile)) {
            require_once $mailerFile;
        }
    }
    if (class_exists('SimpleMailer')) {
        try {
            $mailer = new SimpleMailer();
            return (bool) $mailer->send($email, $subject, $body);
        } catch (Throwable $e) {
            error_log('Rent savings SimpleMailer: '.$e->getMessage());
        }
    }

    $smtp = rentSavingsLoadMailer();
    if ($smtp === null) {
        return false;
    }
    try {
        return (bool) $smtp->send($email, $subject, $body, $site);
    } catch (Throwable $e) {
        error_log('Rent savings SimpleSMTP: '.$e->getMessage());
        return false;
    }
}

function rentSavingsSendWithdrawOtpEmail(
    string $email,
    string $name,
    string $code,
    float $amount,
    string $phone = '',
    string $operator = ''
): bool {
    $site = defined('SITE_NAME') ? SITE_NAME : 'HouseRent Africa';
    $amountLabel = 'K'.number_format($amount, 2);
    $dest = trim(strtoupper($operator).' '.$phone);
    $destHtml = $dest !== ''
        ? "<p>Destination: <strong>".htmlspecialchars($dest)."</strong></p>"
        : '';
    $subject = 'Rent Savings withdrawal code - '.$site;
    $body = "
    <div style='font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:20px;border:1px solid #eee;border-radius:12px;'>
      <h2 style='color:#5A3D31;text-align:center;'>Withdraw confirmation</h2>
      <p>Hello ".htmlspecialchars($name !== '' ? $name : 'Tenant').",</p>
      <p>Use this 6-digit code to authorize a Rent Savings withdrawal of <b>{$amountLabel}</b>.</p>
      {$destHtml}
      <div style='text-align:center;margin:24px 0;'>
        <span style='font-size:28px;font-weight:bold;letter-spacing:6px;background:#FFF8E1;padding:12px 18px;border-radius:10px;display:inline-block;color:#5A3D31;'>{$code}</span>
      </div>
      <p>This code expires in <b>10 minutes</b> and can be used once.</p>
      <p style='color:#b91c1c;font-size:13px;'>If you did not request a withdrawal, ignore this email and secure your account.</p>
    </div>";

    return rentSavingsSendHtmlEmail($email, $subject, $body);
}

function rentSavingsSendWithdrawResultEmail(
    string $email,
    string $name,
    float $amount,
    string $phone,
    string $operator,
    string $status,
    string $reference,
    string $detailMessage
): bool {
    $site = defined('SITE_NAME') ? SITE_NAME : 'HouseRent Africa';
    $amountLabel = 'K'.number_format($amount, 2);
    $statusLabel = strtoupper($status);
    $subject = 'Rent Savings withdrawal '.$statusLabel.' - '.$site;
    $body = "
    <div style='font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:20px;border:1px solid #eee;border-radius:12px;'>
      <h2 style='color:#5A3D31;text-align:center;'>Withdrawal {$statusLabel}</h2>
      <p>Hello ".htmlspecialchars($name !== '' ? $name : 'Tenant').",</p>
      <p>".htmlspecialchars($detailMessage)."</p>
      <p><b>Amount:</b> {$amountLabel}<br>
         <b>To:</b> ".htmlspecialchars(strtoupper($operator).' '.$phone)."<br>
         <b>Reference:</b> ".htmlspecialchars($reference)."</p>
      <p style='color:#74665f;font-size:13px;'>HouseRent Africa Rent Savings</p>
    </div>";

    return rentSavingsSendHtmlEmail($email, $subject, $body);
}

/**
 * Verifies OTP for a withdrawal. Consumes the challenge on success.
 *
 * @return array{ok:bool,message:string}
 */
function rentSavingsConsumeWithdrawOtp(
    PDO $conn,
    int $tenantId,
    string $challengeId,
    string $otpCode,
    float $amount,
    string $phone,
    string $operator
): array {
    rentSavingsEnsureOtpTable($conn);
    $challengeId = preg_replace('/[^a-f0-9]/', '', strtolower($challengeId)) ?? '';
    $otpCode = preg_replace('/\D+/', '', $otpCode) ?? '';
    if (strlen($challengeId) < 16 || ! preg_match('/^\d{6}$/', $otpCode)) {
        return ['ok' => false, 'message' => 'Enter the 6-digit code from your email.'];
    }

    $conn->beginTransaction();
    try {
        $stmt = $conn->prepare(
            'SELECT * FROM rent_savings_withdraw_otps
              WHERE challenge_id = ? AND tenant_id = ?
              LIMIT 1 FOR UPDATE'
        );
        $stmt->execute([$challengeId, $tenantId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (! $row) {
            $conn->rollBack();

            return ['ok' => false, 'message' => 'Verification session expired. Request a new code.'];
        }
        if (! empty($row['used_at'])) {
            $conn->rollBack();

            return ['ok' => false, 'message' => 'This code was already used. Request a new code.'];
        }
        if (strtotime((string) $row['expires_at']) < time()) {
            $conn->rollBack();

            return ['ok' => false, 'message' => 'This code expired. Request a new code.'];
        }
        if ((int) $row['attempts'] >= (int) $row['max_attempts']) {
            $conn->rollBack();

            return ['ok' => false, 'message' => 'Too many incorrect attempts. Request a new code.'];
        }

        $intent = rentSavingsIntentHash($tenantId, $amount, $phone, $operator);
        if (! hash_equals((string) $row['intent_hash'], $intent)) {
            $bump = $conn->prepare(
                'UPDATE rent_savings_withdraw_otps SET attempts = attempts + 1 WHERE id = ?'
            );
            $bump->execute([(int) $row['id']]);
            $conn->commit();

            return ['ok' => false, 'message' => 'Withdrawal details changed. Request a new code.'];
        }

        $expected = rentSavingsCodeHash($otpCode, $challengeId);
        if (! hash_equals((string) $row['code_hash'], $expected)) {
            $bump = $conn->prepare(
                'UPDATE rent_savings_withdraw_otps SET attempts = attempts + 1 WHERE id = ?'
            );
            $bump->execute([(int) $row['id']]);
            $conn->commit();
            $left = max(0, (int) $row['max_attempts'] - ((int) $row['attempts'] + 1));

            return [
                'ok' => false,
                'message' => $left > 0
                    ? "Incorrect code. {$left} attempt(s) left."
                    : 'Too many incorrect attempts. Request a new code.',
            ];
        }

        $use = $conn->prepare(
            'UPDATE rent_savings_withdraw_otps SET used_at = NOW() WHERE id = ? AND used_at IS NULL'
        );
        $use->execute([(int) $row['id']]);
        if ($use->rowCount() !== 1) {
            $conn->rollBack();

            return ['ok' => false, 'message' => 'This code was already used. Request a new code.'];
        }
        $conn->commit();

        return ['ok' => true, 'message' => 'verified'];
    } catch (Throwable $e) {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }

        return ['ok' => false, 'message' => 'Could not verify the code. Try again.'];
    }
}

$inputRaw = file_get_contents('php://input');
if (is_string($inputRaw) && strlen($inputRaw) > 65536) {
    rentSavingsResponse(['status' => 'error', 'message' => 'Request too large.'], 413);
}
$input = json_decode((string) $inputRaw, true);
if (!is_array($input)) {
    $input = [];
}
// Never trust query-string money fields for POST actions — merge GET action only.
if (isset($_GET['action']) && ! isset($input['action'])) {
    $input['action'] = $_GET['action'];
}
$action = strtolower(trim((string) ($input['action'] ?? $_GET['action'] ?? 'summary')));
$allowedActions = [
    'summary',
    'set_goal',
    'deposit',
    'pay_page',
    'confirm_deposit',
    'request_withdraw_otp',
    'withdraw',
];
if (! in_array($action, $allowedActions, true)) {
    rentSavingsResponse(['status' => 'error', 'message' => 'Invalid action.'], 400);
}

// Always charge full fee on new withdrawals (K20 platform + K8.50 Lenco).
$withdrawalFee = (float) RENT_SAVINGS_WITHDRAWAL_FEE;

// Block tenants from adding money while payment service is under development.
if (! RENT_SAVINGS_DEPOSITS_ENABLED
    && in_array($action, ['deposit', 'pay_page', 'confirm_deposit'], true)) {
    header('Retry-After: 3600');
    rentSavingsResponse([
        'status' => 'maintenance',
        'message' => 'Adding money to Rent Savings is under development. Please try again later.',
    ], 503);
}

try {
    $conn = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (PDOException $error) {
    error_log('Rent savings database: ' . $error->getMessage());
    rentSavingsResponse(['status' => 'error', 'message' => 'Database connection failed.'], 500);
}

if (in_array($action, ['pay_page', 'confirm_deposit'], true)) {
    // Public payment endpoints — signed link + rate limits (no Bearer token in WebView).
    rentSavingsRateLimit('pay_ip_' . rentSavingsClientIp(), 60, 600);
    $reference = trim((string) ($_GET['reference'] ?? ''));
    $signature = trim((string) ($_GET['signature'] ?? ''));
    if ($reference === '' || strlen($reference) > 64 || ! rentSavingsIsValidDepositReference($reference)) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Invalid payment link.'], 403);
    }
    if ($signature === '' || strlen($signature) > 128
        || ! hash_equals(rentSavingsPaymentSignature($reference), $signature)) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Invalid payment link.'], 403);
    }
    rentSavingsRateLimit('pay_ref_' . $reference, 40, 600);

    $stmt = $conn->prepare(
        "SELECT rst.*, u.name, u.email, u.phone AS user_phone
           FROM rent_savings_transactions rst
           JOIN users u ON u.id = rst.tenant_id
          WHERE rst.reference = ?
            AND rst.type = 'deposit'
          LIMIT 1"
    );
    $stmt->execute([$reference]);
    $deposit = $stmt->fetch(PDO::FETCH_ASSOC);
    if (! $deposit) {
        rentSavingsResponse(['status' => 'error', 'message' => 'Savings deposit not found.'], 404);
    }

    // Reject ancient unpaid links (reduce replay / link sharing risk).
    $createdAt = strtotime((string) ($deposit['created_at'] ?? ''));
    if ($createdAt && (time() - $createdAt) > (int) RENT_SAVINGS_PAY_LINK_TTL
        && strtolower((string) ($deposit['status'] ?? '')) === 'pending') {
        rentSavingsResponse([
            'status' => 'error',
            'message' => 'This payment link has expired. Start a new deposit in the app.',
        ], 410);
    }

    if ($action === 'confirm_deposit') {
        rentSavingsRateLimit('confirm_' . $reference, 20, 300);

        // Already credited (user refreshed / double confirm) — do not fail.
        if (strtolower((string) ($deposit['status'] ?? '')) === 'completed') {
            rentSavingsResponse([
                'status' => 'success',
                'message' => 'Money already added to Rent Savings.',
            ]);
        }
        if (strtolower((string) ($deposit['status'] ?? '')) === 'failed') {
            rentSavingsResponse([
                'status' => 'failed',
                'message' => 'This deposit was marked failed. Start a new deposit in the app.',
            ], 409);
        }

        $gateway = new RentFundsLenco();
        $result = $gateway->verifyCollection($reference);
        $settled = rentSavingsApplyDepositVerification($conn, $deposit, $result);

        if ($settled['status'] === 'completed') {
            rentSavingsResponse([
                'status' => 'success',
                'message' => $settled['message'],
            ]);
        }

        $http = ($settled['status'] === 'error') ? 502 : 200;
        if ($settled['status'] === 'error' && stripos($settled['message'], 'amount') !== false) {
            $http = 409;
        }
        rentSavingsResponse([
            'status' => $settled['status'] === 'error' ? 'error' : $settled['status'],
            'message' => $settled['message'],
        ], $http);
    }

    // Already paid — show success instead of opening checkout again.
    if (strtolower((string) ($deposit['status'] ?? '')) === 'completed') {
        rentSavingsSecurityHeaders(true);
        header('Content-Type: text/html; charset=UTF-8');
        echo '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Paid</title></head><body style="font-family:Arial;text-align:center;padding:40px"><h2>Already saved</h2><p>This deposit is already in your Rent Savings.</p><script>setTimeout(function(){window.location.href="houserent://payment-success?reference=' . rawurlencode($reference) . '";},800);</script></body></html>';
        exit;
    }

    rentSavingsSecurityHeaders(true);
    header('Content-Type: text/html; charset=UTF-8');
    try {
        $publicKey = (new RentFundsLenco())->publicKey();
    } catch (RuntimeException $error) {
        error_log($error->getMessage());
        rentSavingsResponse(['status' => 'error', 'message' => 'Rent Savings checkout is not configured.'], 503);
    }
    $nameParts = preg_split('/\s+/', trim((string)$deposit['name']));
    $firstName = preg_replace('/[^a-zA-Z0-9 \'\-]/', '', (string) ($nameParts[0] ?? 'Tenant')) ?: 'Tenant';
    $lastName = preg_replace('/[^a-zA-Z0-9 \'\-]/', '', (string) ($nameParts[1] ?? 'User')) ?: 'User';
    $confirmUrl = 'rent_savings.php?action=confirm_deposit&reference=' . rawurlencode($reference) . '&signature=' . rawurlencode($signature);
    ?>
<!doctype html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HouseRent Africa Rent Savings</title>
<script src="https://pay.lenco.co/js/v1/inline.js"></script>
<style>
*{box-sizing:border-box}body{margin:0;background:linear-gradient(150deg,#f7f2ed,#fff9e7);font-family:Arial,sans-serif;color:#2f211b;min-height:100vh}.wrap{max-width:480px;margin:auto;padding:22px 18px 40px}.brand{display:flex;align-items:center;justify-content:center;gap:9px;font-weight:800;color:#5a3d31;margin:6px 0 20px}.brandmark{display:grid;place-items:center;width:36px;height:36px;border-radius:11px;background:#5a3d31;color:#ffc107}.card{background:#fff;border:1px solid #eee4dc;border-radius:24px;padding:28px 24px;box-shadow:0 18px 45px #5a3d311c}.hero{text-align:center}.icon{display:grid;place-items:center;width:68px;height:68px;margin:auto;background:#fff5d5;border-radius:22px;font-size:35px}.hero h2{margin:16px 0 7px;font-size:25px}.hero p{color:#74665f;margin:0}.amount{font-size:42px;font-weight:800;color:#5a3d31;margin:18px 0}.secure{display:inline-flex;align-items:center;gap:6px;background:#eaf8ef;color:#16733b;padding:7px 11px;border-radius:99px;font-size:12px;font-weight:700}.note{background:#fff7dd;border:1px solid #f1d77d;border-radius:13px;padding:13px;margin:18px 0;color:#6c5410;font-size:13px;line-height:1.4}.methods{display:grid;gap:10px;margin:20px 0}.method{display:flex;align-items:center;gap:10px;border:1px solid #e8e0da;border-radius:14px;padding:14px;font-size:14px}.tick{display:grid;place-items:center;background:#eaf8ef;color:#198754;border-radius:50%;width:24px;height:24px;font-weight:bold}button{width:100%;border:0;border-radius:14px;padding:16px;background:#5a3d31;color:white;font-size:16px;font-weight:bold;box-shadow:0 8px 20px #5a3d3130}button:disabled{opacity:.65}.small{font-size:12px;color:#83766f;text-align:center;margin-top:14px;line-height:1.4}.success{display:none;text-align:center}.success h2{color:#198754}@media(max-width:360px){.card{padding:22px 18px}.amount{font-size:36px}}@media(prefers-color-scheme:dark){body{background:linear-gradient(150deg,#111,#201b15);color:#f7f2ed}.brand{color:#ffc107}.brandmark{background:#ffc107;color:#2f211b}.card{background:#1e1e1e;border-color:#3b342f;box-shadow:0 18px 45px #0008}.icon{background:#342d1c}.hero p,.small{color:#c5bbb4}.amount{color:#ffc107}.method{border-color:#49413b;background:#272321}.note{background:#332c16;border-color:#6f5b1d;color:#ffe69c}button{background:#ffc107;color:#211a13;box-shadow:0 8px 20px #0005}.secure{background:#173725;color:#84e2aa}}
</style></head><body><div class="wrap"><div class="brand"><span class="brandmark">H</span> HouseRent Africa</div><div class="card" id="paymentCard">
<div class="hero"><div class="icon">🏠</div><h2>Add to Rent Savings</h2><p>Keep your rent money separate and protected.</p><div class="amount">K<?php echo htmlspecialchars(number_format((float)$deposit['amount'], 2)); ?></div><span class="secure">🔒 Secure checkout</span></div>
<div class="note"><strong>Deposit lock:</strong> This money will be locked for <?php echo (int)$deposit['lock_days']; ?> days after payment and can be withdrawn from approximately <?php echo htmlspecialchars(date('j M Y', strtotime('+' . (int)$deposit['lock_days'] . ' days'))); ?>.</div>
<div class="methods"><div class="method"><span class="tick">✓</span> Mobile Money — MTN, Airtel or Zamtel</div><div class="method"><span class="tick">✓</span> Visa or Mastercard</div></div>
<div id="paymentError" style="display:none;background:#fdecec;color:#a22323;padding:12px;border-radius:12px;margin-bottom:12px;font-size:13px"></div><button id="payButton" onclick="payNow()">Continue to Secure Payment</button><div class="small">Keep this page open until your payment is confirmed and your savings balance is updated.</div>
</div><div class="card success" id="successCard"><div class="icon">✅</div><h2>Money Saved!</h2><p>Your Rent Savings balance has been updated.</p><button onclick="finish()">Return to Rent Savings</button></div></div>
<script>
function payNow(){
 const button=document.getElementById('payButton');const errorBox=document.getElementById('paymentError');errorBox.style.display='none';button.disabled=true;button.textContent='Loading secure payment…';
 if(typeof LencoPay==='undefined'){showError('The payment service did not load. Check your internet connection and try again.');return;}
 try{LencoPay.getPaid({
  key:<?php echo json_encode($publicKey); ?>,reference:<?php echo json_encode($reference); ?>,
  email:<?php echo json_encode((string)$deposit['email']); ?>,amount:<?php echo json_encode((float)$deposit['amount']); ?>,
  currency:'ZMW',color:'#FFC107',channels:['card','mobile-money'],
  customer:{firstName:<?php echo json_encode($firstName); ?>,lastName:<?php echo json_encode($lastName); ?>,phone:<?php echo json_encode((string)($deposit['user_phone'] ?: '0971111111')); ?>},
  onSuccess:async function(){button.textContent='Verifying payment…';await confirmDeposit(button);},
  onClose:function(){button.disabled=false;button.textContent='Continue to Payment';},
  onConfirmationPending:async function(){button.textContent='Waiting for confirmation…';await confirmDeposit(button);}
 });}catch(error){showError(error&&error.message?error.message:'Unable to open the payment window. Please try again.');}
}
async function confirmDeposit(button){
 const errorBox=document.getElementById('paymentError');
 let lastMessage='Payment is still pending. Please wait and try again.';
 for(let attempt=0;attempt<6;attempt++){
  try{
   const response=await fetch(<?php echo json_encode($confirmUrl); ?>,{cache:'no-store'});
   const data=await response.json();
   if(data.status==='success'){
    document.getElementById('paymentCard').style.display='none';
    document.getElementById('successCard').style.display='block';
    return;
   }
   lastMessage=data.message||lastMessage;
   if(data.status==='failed'||data.status==='error'){
    if(attempt>=2&&(data.status==='failed'||(data.message||'').toLowerCase().indexOf('amount')!==-1)){
     showError(lastMessage);return;
    }
   }
  }catch(e){
   lastMessage='Payment was received, but confirmation is taking longer than expected. Opening Rent Savings again will finish updating your balance.';
  }
  button.textContent='Verifying payment… ('+(attempt+1)+'/6)';
  await new Promise(r=>setTimeout(r,2500));
 }
 showError(lastMessage);
 button.disabled=false;button.textContent='Check Payment';
}
function showError(message){const button=document.getElementById('payButton');const box=document.getElementById('paymentError');box.textContent=message;box.style.display='block';button.disabled=false;button.textContent='Try Payment Again';}
function finish(){window.location.href='houserent://payment-success?reference='+encodeURIComponent(<?php echo json_encode($reference); ?>);}
</script></body></html>
    <?php
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    rentSavingsResponse(['status' => 'error', 'message' => 'POST is required.'], 405);
}

$auth = rentSavingsTenant($conn);
$tenantId = (int)$auth['id'];
rentSavingsRateLimit('tenant_' . $tenantId, 120, 600);
rentSavingsRateLimit('ip_' . rentSavingsClientIp(), 200, 600);

try {
    if ($action === 'summary') {
        rentSavingsResponse(rentSavingsSummary($conn, $tenantId, $withdrawalFee));
    }

    if ($action === 'set_goal') {
        rentSavingsRateLimit('goal_' . $tenantId, 20, 600);
        $goal = round((float)($input['rent_goal'] ?? 0), 2);
        $targetDate = trim((string)($input['target_date'] ?? ''));
        $parsedTarget = $targetDate === '' ? null : DateTimeImmutable::createFromFormat('!Y-m-d', $targetDate);
        if ($goal <= 0 || $goal > (float) RENT_SAVINGS_MAX_DEPOSIT
            || ($targetDate !== '' && (!$parsedTarget || $parsedTarget->format('Y-m-d') !== $targetDate))) {
            rentSavingsResponse(['status' => 'error', 'message' => 'Enter a valid rent goal and target date.'], 422);
        }
        $account = rentSavingsAccount($conn, $tenantId);
        $stmt = $conn->prepare('UPDATE rent_savings_accounts SET rent_goal = ?, target_date = ? WHERE id = ? AND tenant_id = ?');
        $stmt->execute([$goal, $targetDate !== '' ? $targetDate : null, $account['id'], $tenantId]);
        rentSavingsResponse(rentSavingsSummary($conn, $tenantId, $withdrawalFee));
    }

    if ($action === 'deposit') {
        rentSavingsRateLimit('deposit_' . $tenantId, 10, 600);
        $amount = round((float)($input['amount'] ?? 0), 2);
        $lockDays = (int)($input['lock_days'] ?? 0);
        $maxDeposit = (float) RENT_SAVINGS_MAX_DEPOSIT;
        if ($amount < 1 || $amount > $maxDeposit || $lockDays < 1 || $lockDays > 3650) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Enter an amount between K1 and K' . number_format($maxDeposit, 2)
                    . ' and choose a lock period from 1 to 3650 days.',
            ], 422);
        }
        $account = rentSavingsAccount($conn, $tenantId);
        $reference = 'SAV-' . $tenantId . '-' . bin2hex(random_bytes(5));
        $stmt = $conn->prepare("INSERT INTO rent_savings_transactions (account_id, tenant_id, type, amount, net_amount, status, reference, payment_method, lock_days, lock_until) VALUES (?, ?, 'deposit', ?, ?, 'pending', ?, 'inline-checkout', ?, NULL)");
        $stmt->execute([$account['id'], $tenantId, $amount, $amount, $reference, $lockDays]);
        $signature = rentSavingsPaymentSignature($reference);
        rentSavingsResponse([
            'status' => 'success',
            'message' => 'Continue on the secure Rent Savings payment page.',
            'reference' => $reference,
            'payment_url' => 'https://houseforrent.site/api/rent_savings.php?action=pay_page&reference=' . rawurlencode($reference) . '&signature=' . rawurlencode($signature),
        ]);
    }

    if ($action === 'request_withdraw_otp') {
        if (! RENT_SAVINGS_REQUIRE_WITHDRAW_OTP) {
            rentSavingsResponse([
                'status' => 'success',
                'message' => 'OTP skipped (testing mode).',
                'otp_required' => false,
                'challenge_id' => '',
                'email_masked' => '',
                'expires_in' => 0,
            ]);
        }
        rentSavingsEnsureOtpTable($conn);
        $amount = round((float) ($input['amount'] ?? 0), 2);
        $phone = rentSavingsNormalizePhone((string) ($input['phone'] ?? ''));
        $operator = strtolower(trim((string) ($input['operator'] ?? 'mtn')));
        $maxWithdraw = (float) RENT_SAVINGS_MAX_WITHDRAW;
        if ($amount <= 0 || $amount > $maxWithdraw || strlen($phone) < 9 || strlen($phone) > 15
            || ! in_array($operator, ['mtn', 'airtel', 'zamtel'], true)) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Enter a valid amount (max K' . number_format($maxWithdraw, 2) . '), phone number, and operator.',
            ], 422);
        }
        if (! preg_match('/^0\d{9}$/', $phone)) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Enter a valid 10-digit mobile number (e.g. 097xxxxxxx).',
            ], 422);
        }
        $required = $amount + $withdrawalFee;
        if (rentSavingsAvailableBalance($conn, $tenantId) < $required) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Insufficient funds. Your available Rent Savings balance is K'
                    .number_format(rentSavingsAvailableBalance($conn, $tenantId), 2)
                    .', but this withdrawal needs K'.number_format($required, 2).'.',
            ], 422);
        }

        // Rate limit: max 3 OTP emails / 15 minutes per tenant.
        $recent = $conn->prepare(
            'SELECT COUNT(*) FROM rent_savings_withdraw_otps
              WHERE tenant_id = ? AND created_at >= (NOW() - INTERVAL 15 MINUTE)'
        );
        $recent->execute([$tenantId]);
        if ((int) $recent->fetchColumn() >= 3) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Too many code requests. Wait a few minutes and try again.',
            ], 429);
        }

        $userStmt = $conn->prepare(
            'SELECT id, name, email FROM users WHERE id = ? LIMIT 1'
        );
        $userStmt->execute([$tenantId]);
        $user = $userStmt->fetch(PDO::FETCH_ASSOC);
        $email = trim((string) ($user['email'] ?? ''));
        if ($email === '' || ! filter_var($email, FILTER_VALIDATE_EMAIL)) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Your account has no valid registered email for verification.',
            ], 422);
        }

        $challengeId = bin2hex(random_bytes(16));
        $code = (string) random_int(100000, 999999);
        $intent = rentSavingsIntentHash($tenantId, $amount, $phone, $operator);
        $codeHash = rentSavingsCodeHash($code, $challengeId);
        $expires = (new DateTimeImmutable('now'))->modify('+10 minutes')->format('Y-m-d H:i:s');

        // Invalidate unused prior challenges for this tenant.
        $conn->prepare(
            'UPDATE rent_savings_withdraw_otps
                SET used_at = NOW()
              WHERE tenant_id = ? AND used_at IS NULL AND expires_at > NOW()'
        )->execute([$tenantId]);

        $ins = $conn->prepare(
            'INSERT INTO rent_savings_withdraw_otps
                (challenge_id, tenant_id, email, code_hash, intent_hash, amount, phone, operator, expires_at, request_ip)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $ins->execute([
            $challengeId,
            $tenantId,
            $email,
            $codeHash,
            $intent,
            $amount,
            $phone,
            $operator,
            $expires,
            rentSavingsClientIp(),
        ]);

        $sent = rentSavingsSendWithdrawOtpEmail(
            $email,
            (string) ($user['name'] ?? 'Tenant'),
            $code,
            $amount,
            $phone,
            $operator
        );
        if (! $sent) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Could not send the verification email to '
                    .rentSavingsMaskEmail($email)
                    .'. Please try again shortly.',
            ], 502);
        }

        rentSavingsResponse([
            'status' => 'success',
            'message' => 'We sent a 6-digit code to '.rentSavingsMaskEmail($email).'.',
            'challenge_id' => $challengeId,
            'email_masked' => rentSavingsMaskEmail($email),
            'expires_in' => 600,
            'amount' => $amount,
            'withdrawal_fee' => $withdrawalFee,
            'email_sent' => true,
        ]);
    }

    if ($action === 'withdraw') {
        rentSavingsRateLimit('withdraw_' . $tenantId, 8, 600);
        $amount = round((float) ($input['amount'] ?? 0), 2);
        $phone = rentSavingsNormalizePhone((string) ($input['phone'] ?? ''));
        $operator = strtolower(trim((string) ($input['operator'] ?? 'mtn')));
        $country = strtolower(trim((string) ($input['country'] ?? 'zm')));
        if (! in_array($country, ['zm', 'mw'], true)) {
            $country = 'zm';
        }
        $challengeId = trim((string) ($input['otp_challenge_id'] ?? $input['challenge_id'] ?? ''));
        $otpCode = trim((string) ($input['otp_code'] ?? $input['otp'] ?? ''));
        $maxWithdraw = (float) RENT_SAVINGS_MAX_WITHDRAW;
        if ($amount <= 0 || $amount > $maxWithdraw || $phone === '' || ! in_array($operator, ['mtn', 'airtel', 'zamtel', 'tnm'], true)) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Enter a valid amount (max K' . number_format($maxWithdraw, 2) . '), phone number, and operator.',
            ], 422);
        }
        if (! preg_match('/^0\d{9}$/', $phone)) {
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Enter a valid 10-digit mobile number (e.g. 097xxxxxxx).',
            ], 422);
        }
        if (strlen($challengeId) > 128 || strlen($otpCode) > 16) {
            rentSavingsResponse(['status' => 'error', 'message' => 'Invalid verification details.'], 422);
        }

        if (RENT_SAVINGS_REQUIRE_WITHDRAW_OTP) {
            if ($challengeId === '' || $otpCode === '') {
                rentSavingsResponse([
                    'status' => 'error',
                    'message' => 'Email verification is required. Request a 6-digit code first.',
                ], 403);
            }
            $otp = rentSavingsConsumeWithdrawOtp(
                $conn,
                $tenantId,
                $challengeId,
                $otpCode,
                $amount,
                $phone,
                $operator
            );
            if (! $otp['ok']) {
                rentSavingsResponse(['status' => 'error', 'message' => $otp['message']], 403);
            }
        }

        $lenco = new RentFundsLenco();
        // Ensure wallet can cover payout amount (fee is kept on platform ledger).
        $wallet = $lenco->pickZmwDebitAccount($amount);
        if (! $wallet['ok']) {
            rentSavingsResponse(['status' => 'error', 'message' => $wallet['message']], 422);
        }

        $conn->beginTransaction();
        $account = rentSavingsAccount($conn, $tenantId);
        if ((int) ($account['tenant_id'] ?? 0) !== $tenantId) {
            $conn->rollBack();
            rentSavingsResponse(['status' => 'error', 'message' => 'Unauthorized.'], 401);
        }
        $lock = $conn->prepare('SELECT id FROM rent_savings_accounts WHERE id = ? AND tenant_id = ? FOR UPDATE');
        $lock->execute([$account['id'], $tenantId]);
        // New users / new withdrawals always pay the full K28.50 fee.
        $withdrawalFee = (float) RENT_SAVINGS_WITHDRAWAL_FEE;
        if ($withdrawalFee < 28.5) {
            $withdrawalFee = 28.5;
        }
        $required = $amount + $withdrawalFee;
        $availableNow = rentSavingsAvailableBalance($conn, $tenantId);
        if ($availableNow < $required) {
            $conn->rollBack();
            rentSavingsResponse([
                'status' => 'error',
                'message' => 'Insufficient funds. Your available Rent Savings balance is K'
                    .number_format($availableNow, 2)
                    .', but this withdrawal needs K'.number_format($required, 2)
                    .' (amount + K'.number_format($withdrawalFee, 2).' fee).',
            ], 422);
        }
        $reference = 'WD-'.$tenantId.'-'.strtoupper(bin2hex(random_bytes(4)));
        $stmt = $conn->prepare(
            "INSERT INTO rent_savings_transactions
                (account_id, tenant_id, type, amount, fee, net_amount, status, reference, payment_method, phone, operator)
             VALUES (?, ?, 'withdrawal', ?, ?, ?, 'processing', ?, 'mobile-money', ?, ?)"
        );
        $stmt->execute([
            $account['id'],
            $tenantId,
            $amount,
            $withdrawalFee,
            $amount,
            $reference,
            $phone,
            $operator,
        ]);
        $txnId = (int) $conn->lastInsertId();
        $conn->commit();

        $siteName = defined('SITE_NAME') ? SITE_NAME : 'HouseRent Africa';
        $transfer = $lenco->transferMobileMoney(
            (string) $wallet['account_id'],
            $amount,
            $phone,
            $operator,
            $country,
            $reference,
            $siteName.' Rent Savings withdrawal'
        );

        $providerData = is_array($transfer['data'] ?? null) ? $transfer['data'] : [];
        $providerStatus = strtolower(trim((string) ($providerData['status'] ?? '')));
        $providerReference = (string) ($providerData['lencoReference']
            ?? $providerData['reference']
            ?? $providerData['id']
            ?? '');
        $providerMessage = (string) ($providerData['reasonForFailure']
            ?? $providerData['message']
            ?? $transfer['message']
            ?? '');
        $httpCode = (int) ($transfer['http'] ?? 0);

        error_log(
            'Rent savings Lenco transfer: http='.$httpCode
            .' top_status='.json_encode($transfer['status'] ?? null)
            .' data_status='.$providerStatus
            .' ref='.$providerReference
            .' msg='.$providerMessage
        );

        // Only mark failed when Lenco explicitly says failed AND there is no transfer id.
        // pending / successful / empty + money out must stay completed so balance drops.
        $explicitFail = in_array($providerStatus, ['failed', 'rejected', 'cancelled', 'canceled'], true);
        $hasTransferId = $providerReference !== '' || ! empty($providerData['id']);
        $topOk = ($transfer['status'] ?? null) === true
            || ($transfer['status'] ?? null) === 1
            || (is_string($transfer['status'] ?? null)
                && in_array(strtolower((string) $transfer['status']), ['true', 'success', 'successful', 'ok'], true));

        if ($explicitFail && ! $hasTransferId) {
            $databaseStatus = 'failed';
            $message = 'Withdrawal did not go through'
                .($providerMessage !== '' ? ': '.$providerMessage : '.')
                .' Your savings balance was not reduced.';
        } elseif (! $topOk && ! $hasTransferId && $providerStatus === '' && ($httpCode < 200 || $httpCode >= 300)) {
            $databaseStatus = 'failed';
            $message = 'Withdrawal did not go through'
                .($providerMessage !== '' ? ': '.$providerMessage : '.')
                .' Your savings balance was not reduced.';
        } else {
            $databaseStatus = 'completed';
            $message = 'Withdrawal completed. K'.number_format($amount, 2)
                .' sent to '.strtoupper($operator).' '.$phone.'.';
            if ($withdrawalFee > 0) {
                $message .= ' Fee of K'.number_format($withdrawalFee, 2).' deducted from Rent Savings.';
            }
        }

        // Always persist completed/failed BEFORE any email work.
        try {
            $hasProvider = $conn->query(
                "SHOW COLUMNS FROM rent_savings_transactions LIKE 'provider_reference'"
            )->fetch(PDO::FETCH_ASSOC);
            if ($hasProvider) {
                $upd = $conn->prepare(
                    'UPDATE rent_savings_transactions
                        SET status = ?, provider_reference = ?
                      WHERE id = ? AND tenant_id = ? AND type = \'withdrawal\''
                );
                $upd->execute([
                    $databaseStatus,
                    $providerReference !== '' ? $providerReference : null,
                    $txnId,
                    $tenantId,
                ]);
            } else {
                $upd = $conn->prepare(
                    'UPDATE rent_savings_transactions SET status = ? WHERE id = ? AND tenant_id = ? AND type = \'withdrawal\''
                );
                $upd->execute([$databaseStatus, $txnId, $tenantId]);
            }
        } catch (Throwable $e) {
            error_log('Rent savings status update failed: '.$e->getMessage());
            try {
                $upd = $conn->prepare(
                    'UPDATE rent_savings_transactions SET status = ? WHERE id = ? AND tenant_id = ? AND type = \'withdrawal\''
                );
                $upd->execute([$databaseStatus, $txnId, $tenantId]);
            } catch (Throwable $e2) {
                error_log('Rent savings status update retry failed: '.$e2->getMessage());
            }
        }

        // Force-complete this row if Lenco paid but update somehow left it failed.
        if ($databaseStatus === 'completed') {
            try {
                $conn->prepare(
                    "UPDATE rent_savings_transactions SET status = 'completed' WHERE id = ? AND tenant_id = ? AND type = 'withdrawal'"
                )->execute([$txnId, $tenantId]);
            } catch (Throwable $e) {
                error_log('Rent savings force complete: '.$e->getMessage());
            }
        }

        $summary = rentSavingsSummary($conn, $tenantId, $withdrawalFee);
        $totalDeducted = round($amount + $withdrawalFee, 2);
        $remainingBalance = round((float) ($summary['balance'] ?? 0), 2);
        $remainingAvailable = round((float) ($summary['available_balance'] ?? 0), 2);

        // Ensure this new withdrawal always has the full K28.50 fee stored.
        if ($databaseStatus === 'completed') {
            try {
                $conn->prepare(
                    'UPDATE rent_savings_transactions SET fee = ? WHERE id = ? AND tenant_id = ? AND type = \'withdrawal\''
                )->execute([(float) RENT_SAVINGS_WITHDRAWAL_FEE, $txnId, $tenantId]);
                $summary = rentSavingsSummary($conn, $tenantId, $withdrawalFee);
                $remainingBalance = round((float) ($summary['balance'] ?? 0), 2);
                $remainingAvailable = round((float) ($summary['available_balance'] ?? 0), 2);
                $totalDeducted = round($amount + (float) RENT_SAVINGS_WITHDRAWAL_FEE, 2);
            } catch (Throwable $e) {
                error_log('Rent savings fee correct: '.$e->getMessage());
            }
        }

        $summary['withdrawal_status'] = $databaseStatus;
        $summary['reference'] = $reference;
        $summary['withdrawn_amount'] = round($amount, 2);
        $summary['withdrawn_fee'] = round((float) RENT_SAVINGS_WITHDRAWAL_FEE, 2);
        $summary['total_deducted'] = $totalDeducted;
        $summary['withdrawal_fee'] = round((float) RENT_SAVINGS_WITHDRAWAL_FEE, 2);
        $summary['withdrawn_phone'] = $phone;
        $summary['withdrawn_operator'] = $operator;
        $summary['provider_status'] = $providerStatus !== '' ? $providerStatus : 'accepted';
        $summary['provider_reference'] = $providerReference;
        $summary['lenco_accepted'] = $databaseStatus === 'completed';
        $summary['balance'] = $remainingBalance;
        $summary['available_balance'] = $remainingAvailable;
        $summary['remaining_balance'] = $remainingBalance;
        $summary['remaining_available'] = $remainingAvailable;
        $summary['message'] = $message
            .' Remaining balance: K'.number_format($remainingBalance, 2).'.';

        // Do not block the API response on email (was hanging and breaking the app UI).
        $summary['result_email_sent'] = false;

        if ($databaseStatus !== 'completed') {
            $summary['status'] = 'error';
            rentSavingsResponse($summary, 422);
        }
        rentSavingsResponse($summary);
    }

    rentSavingsResponse(['status' => 'error', 'message' => 'Unknown action.'], 400);
} catch (Throwable $error) {
    if ($conn->inTransaction()) $conn->rollBack();
    error_log('Rent savings API: ' . $error->getMessage());
    rentSavingsResponse(['status' => 'error', 'message' => 'Rent Savings is temporarily unavailable.'], 500);
}
