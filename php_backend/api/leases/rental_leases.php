<?php
/**
 * Digital rental leases API
 * Upload to: php_backend/api/leases/rental_leases.php
 *
 * Actions:
 *  GET  ?action=list
 *  GET  ?action=get&lease_id=
 *  POST action=create  { rental_id, deposit_amount?, send? }
 *  POST action=sign    { lease_id, signed_name, signature_data }
 *  POST action=cancel  { lease_id } (dealer only)
 */
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../auth.php';
require_once __DIR__ . '/../includes/rental_lease_helpers.php';

function lease_json($payload, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function lease_public_row(?array $lease): ?array
{
    if (!$lease) {
        return null;
    }
    // Keep signatures available to parties (needed to display signed docs).
    return $lease;
}

try {
    $user = authorize(['dealer', 'user', 'tenant']);
} catch (Throwable $e) {
    // authorize already exits on failure
    exit;
}

$userId = (int) $user['id'];
$role = strtolower((string) $user['role']);
if ($role === 'tenant') {
    $role = 'user';
}

$input = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $raw = file_get_contents('php://input');
    $decoded = json_decode((string) $raw, true);
    $input = is_array($decoded) ? $decoded : $_POST;
}

$action = trim((string) ($input['action'] ?? $_GET['action'] ?? 'list'));

try {
    // Ensure table exists (idempotent soft check).
    $conn->query('SELECT 1 FROM rental_leases LIMIT 1');
} catch (Throwable $e) {
    lease_json([
        'status' => 'error',
        'message' => 'Lease table missing. Run migration 20260831_digital_rental_leases.sql',
    ], 500);
}

if ($action === 'list') {
    if ($role === 'dealer') {
        $stmt = $conn->prepare(
            "SELECT id, rental_id, property_title, property_location, tenant_name, rent_amount, currency,
                    start_date, end_date, status, dealer_signed_at, tenant_signed_at, created_at, updated_at
             FROM rental_leases
             WHERE dealer_id = :uid
             ORDER BY updated_at DESC
             LIMIT 100"
        );
        $stmt->execute([':uid' => $userId]);
    } else {
        $stmt = $conn->prepare(
            "SELECT id, rental_id, property_title, property_location, dealer_name, rent_amount, currency,
                    start_date, end_date, status, dealer_signed_at, tenant_signed_at, created_at, updated_at
             FROM rental_leases
             WHERE tenant_id = :uid
             ORDER BY updated_at DESC
             LIMIT 100"
        );
        $stmt->execute([':uid' => $userId]);
    }
    lease_json(['status' => 'success', 'data' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($action === 'get') {
    $leaseId = (int) ($input['lease_id'] ?? $_GET['lease_id'] ?? 0);
    $lease = hr_lease_get($conn, $leaseId);
    if (!$lease) {
        lease_json(['status' => 'error', 'message' => 'Lease not found'], 404);
    }
    $allowed = ($role === 'dealer' && (int) $lease['dealer_id'] === $userId)
        || ($role === 'user' && (int) $lease['tenant_id'] === $userId);
    if (!$allowed) {
        lease_json(['status' => 'error', 'message' => 'Not authorized'], 403);
    }
    lease_json(['status' => 'success', 'data' => lease_public_row($lease)]);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    lease_json(['status' => 'error', 'message' => 'Invalid action'], 422);
}

if ($action === 'create') {
    if ($role !== 'dealer') {
        lease_json(['status' => 'error', 'message' => 'Only dealers can create leases'], 403);
    }
    $rentalId = (int) ($input['rental_id'] ?? 0);
    $deposit = (float) ($input['deposit_amount'] ?? 0);
    $send = !isset($input['send']) || (bool) $input['send'];
    $terms = isset($input['terms_body']) ? (string) $input['terms_body'] : null;

    $check = $conn->prepare('SELECT id FROM rentals WHERE id = :id AND dealer_id = :did LIMIT 1');
    $check->execute([':id' => $rentalId, ':did' => $userId]);
    if (!$check->fetchColumn()) {
        lease_json(['status' => 'error', 'message' => 'Rental not found for this dealer'], 404);
    }

    $result = hr_lease_create_from_rental($conn, $rentalId, $userId, $deposit, $terms, $send);
    if (!$result['ok']) {
        lease_json(['status' => 'error', 'message' => $result['message'] ?? 'Could not create lease'], 422);
    }

    $lease = $result['lease'];
    if ($send && $lease) {
        hr_lease_notify_party(
            $conn,
            $lease,
            'Rental lease ready to sign',
            'Your landlord sent a digital lease for ' . ($lease['property_title'] ?? 'your rental') . '. Open the app to review and sign.',
            'user'
        );
    }

    lease_json([
        'status' => 'success',
        'message' => $send ? 'Lease created and sent to tenant' : 'Lease draft created',
        'lease_id' => $result['lease_id'],
        'data' => lease_public_row($lease),
    ], 201);
}

if ($action === 'sign') {
    $leaseId = (int) ($input['lease_id'] ?? 0);
    $signedName = (string) ($input['signed_name'] ?? '');
    $signatureData = (string) ($input['signature_data'] ?? '');
    $result = hr_lease_sign($conn, $leaseId, $userId, $role, $signedName, $signatureData);
    if (!$result['ok']) {
        lease_json(['status' => 'error', 'message' => $result['message'] ?? 'Sign failed'], 422);
    }
    $lease = $result['lease'];
    if ($lease && ($lease['status'] ?? '') === 'signed') {
        $other = $role === 'dealer' ? 'user' : 'dealer';
        hr_lease_notify_party(
            $conn,
            $lease,
            'Lease fully signed',
            'The rental lease for ' . ($lease['property_title'] ?? 'your property') . ' is now fully signed.',
            $other
        );
    } elseif ($lease && $role === 'dealer') {
        hr_lease_notify_party(
            $conn,
            $lease,
            'Landlord signed your lease',
            'Please open HouseRent Africa and sign your rental lease.',
            'user'
        );
    } elseif ($lease && $role === 'user') {
        hr_lease_notify_party(
            $conn,
            $lease,
            'Tenant signed the lease',
            ($lease['tenant_name'] ?? 'Tenant') . ' signed the lease for ' . ($lease['property_title'] ?? 'your property') . '.',
            'dealer'
        );
    }
    lease_json([
        'status' => 'success',
        'message' => 'Signature saved',
        'data' => lease_public_row($lease),
    ]);
}

if ($action === 'cancel') {
    if ($role !== 'dealer') {
        lease_json(['status' => 'error', 'message' => 'Only dealers can cancel'], 403);
    }
    $leaseId = (int) ($input['lease_id'] ?? 0);
    $lease = hr_lease_get($conn, $leaseId);
    if (!$lease || (int) $lease['dealer_id'] !== $userId) {
        lease_json(['status' => 'error', 'message' => 'Lease not found'], 404);
    }
    if (($lease['status'] ?? '') === 'signed') {
        lease_json(['status' => 'error', 'message' => 'Signed leases cannot be cancelled'], 422);
    }
    $upd = $conn->prepare("UPDATE rental_leases SET status = 'cancelled' WHERE id = :id");
    $upd->execute([':id' => $leaseId]);
    lease_json(['status' => 'success', 'message' => 'Lease cancelled']);
}

lease_json(['status' => 'error', 'message' => 'Invalid action'], 422);
