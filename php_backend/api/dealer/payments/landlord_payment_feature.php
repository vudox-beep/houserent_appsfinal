<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../../db.php';
require_once '../../includes/LencoAPI.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method. Must be POST']);
    exit();
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input) {
    $input = $_POST;
}

$action = $input['action'] ?? 'get_status';
$dealerId = intval($input['dealer_id'] ?? $input['user_id'] ?? 0);

if ($dealerId <= 0) {
    echo json_encode(['status' => 'error', 'message' => 'Dealer ID is required']);
    exit();
}

$featureFee = 20.00;
$currency = 'ZMW';

function normalizeFeatureStatus(string $status): string {
    $normalized = strtolower(trim($status));
    if (in_array($normalized, ['success', 'successful', 'completed', 'paid'], true)) {
        return 'successful';
    }
    if (in_array($normalized, ['failed', 'declined', 'cancelled', 'canceled'], true)) {
        return 'failed';
    }
    return $normalized === '' ? 'pending' : $normalized;
}

function getLandlordPaymentFeatureStatus(PDO $conn, int $dealerId): array {
    $stmt = $conn->prepare("
        SELECT *
        FROM landlord_payment_features
        WHERE dealer_id = ?
        ORDER BY created_at DESC
        LIMIT 1
    ");
    $stmt->execute([$dealerId]);
    $feature = $stmt->fetch(PDO::FETCH_ASSOC);

    $isActive = false;
    if ($feature) {
        $status = normalizeFeatureStatus((string)($feature['status'] ?? ''));
        $expiresAt = (string)($feature['expires_at'] ?? '');
        $isActive = $status === 'successful'
            && $expiresAt !== ''
            && strtotime($expiresAt) >= time();
    }

    $payoutStmt = $conn->prepare("
        SELECT id, phone, operator, country, account_name, is_verified, created_at, updated_at
        FROM landlord_payout_accounts
        WHERE dealer_id = ?
        ORDER BY updated_at DESC, created_at DESC
        LIMIT 1
    ");
    $payoutStmt->execute([$dealerId]);
    $payoutAccount = $payoutStmt->fetch(PDO::FETCH_ASSOC);

    return [
        'status' => 'success',
        'is_active' => $isActive,
        'feature' => $feature ?: null,
        'payout_account' => $payoutAccount ?: null,
    ];
}

try {
    if ($action === 'get_status') {
        echo json_encode(getLandlordPaymentFeatureStatus($conn, $dealerId));
        exit();
    }

    if ($action === 'save_payout_account') {
        $phone = preg_replace('/\D+/', '', (string)($input['phone'] ?? ''));
        $operator = strtolower(trim((string)($input['operator'] ?? '')));
        $country = strtolower(trim((string)($input['country'] ?? 'zm')));
        $accountName = trim((string)($input['account_name'] ?? ''));

        if ($phone === '' || $operator === '') {
            echo json_encode([
                'status' => 'error',
                'message' => 'Phone and operator are required',
            ]);
            exit();
        }

        if (!in_array($operator, ['mtn', 'airtel', 'zamtel'], true)) {
            echo json_encode([
                'status' => 'error',
                'message' => 'Operator must be mtn, airtel, or zamtel',
            ]);
            exit();
        }

        $stmt = $conn->prepare("
            INSERT INTO landlord_payout_accounts
                (dealer_id, phone, operator, country, account_name, is_verified, updated_at)
            VALUES (?, ?, ?, ?, ?, 0, NOW())
            ON DUPLICATE KEY UPDATE
                phone = VALUES(phone),
                operator = VALUES(operator),
                country = VALUES(country),
                account_name = VALUES(account_name),
                is_verified = 0,
                updated_at = NOW()
        ");
        $stmt->execute([$dealerId, $phone, $operator, $country, $accountName]);

        echo json_encode([
            'status' => 'success',
            'message' => 'Payout account saved',
        ]);
        exit();
    }

    if ($action === 'initiate') {
        $phone = preg_replace('/\D+/', '', (string)($input['phone'] ?? ''));
        $operator = strtolower(trim((string)($input['operator'] ?? 'mtn')));
        $country = strtolower(trim((string)($input['country'] ?? 'zm')));

        if ($phone === '') {
            $stmtUser = $conn->prepare("SELECT phone FROM users WHERE id = ?");
            $stmtUser->execute([$dealerId]);
            $user = $stmtUser->fetch(PDO::FETCH_ASSOC);
            $phone = preg_replace('/\D+/', '', (string)($user['phone'] ?? ''));
        }

        if ($phone === '') {
            echo json_encode([
                'status' => 'error',
                'message' => 'Phone number is required for mobile money',
            ]);
            exit();
        }

        $lenco = new LencoAPI();
        $response = $lenco->initiateMobileMoney($featureFee, $currency, $phone, $operator, $country);

        if (isset($response['status']) && $response['status'] === true) {
            $reference = $response['data']['reference']
                ?? $response['data']['id']
                ?? ('LPF-' . uniqid() . '-' . time());

            $stmt = $conn->prepare("
                INSERT INTO landlord_payment_features
                    (dealer_id, reference, amount, currency, status, payment_method)
                VALUES (?, ?, ?, ?, 'pending', 'mobile-money')
            ");
            $stmt->execute([$dealerId, $reference, $featureFee, $currency]);

            try {
                $tx = $conn->prepare("
                    INSERT INTO transactions
                        (user_id, reference, amount, currency, status, payment_method, message)
                    VALUES (?, ?, ?, ?, 'pending', 'mobile-money', 'Landlord tenant-payment feature')
                ");
                $tx->execute([$dealerId, $reference, $featureFee, $currency]);
            } catch (Throwable $ignored) {
            }

            echo json_encode([
                'status' => 'success',
                'message' => 'Payment initiated. Please check your phone for the prompt.',
                'reference' => $reference,
                'amount' => $featureFee,
                'currency' => $currency,
                'lenco_response' => $response['data'] ?? [],
            ]);
            exit();
        }

        echo json_encode([
            'status' => 'error',
            'message' => $response['message'] ?? 'Failed to initiate payment',
            'lenco_response' => $response,
        ]);
        exit();
    }

    if ($action === 'verify') {
        $reference = trim((string)($input['reference'] ?? ''));
        if ($reference === '') {
            echo json_encode(['status' => 'error', 'message' => 'Reference is required']);
            exit();
        }

        $lenco = new LencoAPI();
        $result = $lenco->verifyTransaction($reference);

        if (!isset($result['status']) || $result['status'] !== true) {
            echo json_encode([
                'status' => 'error',
                'message' => 'Unable to verify transaction',
                'lenco_response' => $result,
            ]);
            exit();
        }

        $resData = $result['data'] ?? [];
        $paymentStatus = normalizeFeatureStatus((string)($resData['status'] ?? 'pending'));
        $expiresAt = null;
        if ($paymentStatus === 'successful') {
            $expiresAt = date('Y-m-d H:i:s', strtotime('+30 days'));
        }

        $stmt = $conn->prepare("
            UPDATE landlord_payment_features
            SET status = ?, expires_at = COALESCE(?, expires_at), updated_at = NOW()
            WHERE dealer_id = ? AND reference = ?
        ");
        $stmt->execute([$paymentStatus, $expiresAt, $dealerId, $reference]);

        try {
            $tx = $conn->prepare("
                UPDATE transactions
                SET status = ?, message = ?, updated_at = NOW()
                WHERE user_id = ? AND reference = ?
            ");
            $tx->execute([
                $paymentStatus,
                'Landlord tenant-payment feature: ' . $paymentStatus,
                $dealerId,
                $reference,
            ]);
        } catch (Throwable $ignored) {
        }

        echo json_encode([
            'status' => $paymentStatus === 'successful' ? 'success' : 'pending',
            'message' => $paymentStatus === 'successful'
                ? 'Payment feature activated.'
                : 'Payment is still ' . $paymentStatus,
            'payment_status' => $paymentStatus,
            'expires_at' => $expiresAt,
        ]);
        exit();
    }

    if ($action === 'history') {
        $stmt = $conn->prepare("
            SELECT id, reference, amount, currency, status, payment_method, expires_at, created_at, updated_at
            FROM landlord_payment_features
            WHERE dealer_id = ?
            ORDER BY created_at DESC
        ");
        $stmt->execute([$dealerId]);

        echo json_encode([
            'status' => 'success',
            'payments' => $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [],
        ]);
        exit();
    }

    echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
} catch (Throwable $e) {
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage(),
    ]);
}
?>
