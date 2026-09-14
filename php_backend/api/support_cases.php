<?php
/**
 * Rent disputes (tenant/dealer ↔ admin chat) + maintenance tickets (tenant → dealer).
 * Single API for the Flutter app. Admin uses house/admin/support_chat.php (website only).
 *
 * POST JSON or multipart only. Header: Authorization: Bearer <token>
 * Body: { "action": "...", ... }
 */
require_once __DIR__ . '/cors.php';
require_once __DIR__ . '/includes/RateLimiter.php';
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/auth.php';

const SUPPORT_MAX_BODY_BYTES = 65536; // 64 KB
const SUPPORT_MAX_MESSAGE_LEN = 4000;
const SUPPORT_MAX_TITLE_LEN = 200;
const SUPPORT_MAX_DESC_LEN = 5000;
const SUPPORT_MAX_NOTE_LEN = 2000;
const SUPPORT_LIST_LIMIT = 100;
const SUPPORT_MAX_OPEN_DISPUTES_PER_RENTAL = 3;
const SUPPORT_MAX_OPEN_TICKETS_PER_RENTAL = 10;
const SUPPORT_MAX_UPLOAD_BYTES = 5242880; // 5 MB

const SUPPORT_ALLOWED_ACTIONS = [
    'create_dispute',
    'list_disputes',
    'get_dispute',
    'send_dispute_message',
    'create_maintenance',
    'list_maintenance',
    'update_maintenance',
];

/** Per-action limits: [max_requests, window_seconds] keyed by action suffix. */
const SUPPORT_ACTION_RATE_LIMITS = [
    'create_dispute' => [5, 3600],
    'send_dispute_message' => [30, 600],
    'create_maintenance' => [8, 3600],
    'update_maintenance' => [40, 600],
    'read' => [120, 60],
];

function supportJson(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

function supportOk(string $message, array $data = []): void
{
    supportJson(200, array_merge(['status' => 'success', 'message' => $message], $data));
}

function supportErr(string $message, int $code = 400): void
{
    supportJson($code, ['status' => 'error', 'message' => $message]);
}

function supportClientIp(): string
{
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    if (! empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        $ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
    } elseif (! empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ips = explode(',', $_SERVER['HTTP_X_FORWARDING_FOR']);
        $ip = trim($ips[0]);
    }

    return preg_match('/^[a-fA-F0-9:.]{3,45}$/', $ip) ? $ip : 'unknown';
}

function supportRateLimitOrAbort(string $bucket, int $limit, int $windowSeconds): void
{
    static $limiters = [];
    $key = $limit.'_'.$windowSeconds;
    if (! isset($limiters[$key])) {
        $limiters[$key] = new RateLimiter($limit, $windowSeconds);
    }
    if (! $limiters[$key]->check($bucket)) {
        supportErr('Too many requests. Please wait and try again.', 429);
    }
}

function supportEnforceHttpMethod(): void
{
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        http_response_code(200);
        exit;
    }
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        supportErr('Method not allowed. Use POST.', 405);
    }
}

function supportEnforceBodySize(): void
{
    $len = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($len > SUPPORT_MAX_BODY_BYTES && empty($_FILES)) {
        supportErr('Request body too large.', 413);
    }
}

function supportSanitizeText(string $text, int $maxLen): string
{
    $text = str_replace("\0", '', $text);
    $text = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $text) ?? '';
    $text = trim($text);
    if (mb_strlen($text) > $maxLen) {
        $text = mb_substr($text, 0, $maxLen);
    }

    return $text;
}

function supportPositiveInt(mixed $value, int $max = 2147483647): int
{
    if (! is_numeric($value)) {
        return 0;
    }
    $n = (int) $value;

    return ($n > 0 && $n <= $max) ? $n : 0;
}

function supportInput(): array
{
    $raw = file_get_contents('php://input');
    if ($raw !== false && strlen($raw) > SUPPORT_MAX_BODY_BYTES && empty($_FILES)) {
        supportErr('Request body too large.', 413);
    }

    $json = json_decode($raw ?: '{}', true);
    if (! is_array($json)) {
        $json = [];
    }

    // Never trust query-string parameters for mutations / auth bypass.
    return array_merge($_POST, $json);
}

function supportValidateAction(string $action): void
{
    if ($action === '' || ! preg_match('/^[a-z_]{3,40}$/', $action)) {
        supportErr('Invalid action.', 400);
    }
    if (! in_array($action, SUPPORT_ALLOWED_ACTIONS, true)) {
        supportErr('Unknown or disallowed action.', 400);
    }
}

function supportApplyActionRateLimit(int $userId, string $action): void
{
    $readActions = ['list_disputes', 'get_dispute', 'list_maintenance'];
    $bucketAction = in_array($action, $readActions, true) ? 'read' : $action;
    [$limit, $window] = SUPPORT_ACTION_RATE_LIMITS[$bucketAction]
        ?? SUPPORT_ACTION_RATE_LIMITS['read'];

    supportRateLimitOrAbort('support_u'.$userId.'_'.$bucketAction, $limit, $window);
}

function ensureSupportTables(PDO $conn): void
{
    static $ready = false;
    if ($ready) {
        return;
    }

    $conn->exec(
        "CREATE TABLE IF NOT EXISTS rent_dispute_cases (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            rental_id INT UNSIGNED NOT NULL,
            payment_id INT UNSIGNED NULL,
            tenant_id INT UNSIGNED NOT NULL,
            dealer_id INT UNSIGNED NOT NULL,
            dispute_type ENUM('tenant_claims_paid','dealer_not_received','payment_rejected') NOT NULL DEFAULT 'tenant_claims_paid',
            summary VARCHAR(255) NOT NULL,
            status ENUM('open','resolved','closed') NOT NULL DEFAULT 'open',
            resolution_notes TEXT NULL,
            resolved_by INT UNSIGNED NULL,
            resolved_at DATETIME NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            KEY idx_dispute_tenant_status (tenant_id, status, updated_at),
            KEY idx_dispute_dealer_status (dealer_id, status, updated_at),
            KEY idx_dispute_rental_status (rental_id, status),
            KEY idx_dispute_payment (payment_id),
            KEY idx_dispute_status_updated (status, updated_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
    );

    $conn->exec(
        "CREATE TABLE IF NOT EXISTS rent_dispute_messages (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            case_id INT UNSIGNED NOT NULL,
            sender_id INT UNSIGNED NOT NULL,
            sender_role ENUM('tenant','dealer','admin') NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            KEY idx_dispute_msg_case_time (case_id, created_at),
            KEY idx_dispute_msg_sender_time (sender_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
    );

    $conn->exec(
        "CREATE TABLE IF NOT EXISTS maintenance_tickets (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            rental_id INT UNSIGNED NOT NULL,
            property_id INT UNSIGNED NOT NULL,
            tenant_id INT UNSIGNED NOT NULL,
            dealer_id INT UNSIGNED NOT NULL,
            title VARCHAR(200) NOT NULL,
            description TEXT NOT NULL,
            category VARCHAR(50) NOT NULL DEFAULT 'general',
            priority ENUM('low','normal','urgent') NOT NULL DEFAULT 'normal',
            status ENUM('open','in_progress','resolved','closed') NOT NULL DEFAULT 'open',
            dealer_note TEXT NULL,
            photo_url VARCHAR(500) NULL,
            resolved_at DATETIME NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            KEY idx_maint_tenant_status (tenant_id, status, updated_at),
            KEY idx_maint_dealer_status (dealer_id, status, updated_at),
            KEY idx_maint_rental_status (rental_id, status),
            KEY idx_maint_property (property_id),
            KEY idx_maint_status_updated (status, updated_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
    );

    ensureSupportIndexes($conn);

    $ready = true;
}

function ensureSupportIndexes(PDO $conn): void
{
    static $indexed = false;
    if ($indexed) {
        return;
    }

    $statements = [
        'ALTER TABLE rent_dispute_cases ADD INDEX idx_dispute_tenant_status (tenant_id, status, updated_at)',
        'ALTER TABLE rent_dispute_cases ADD INDEX idx_dispute_dealer_status (dealer_id, status, updated_at)',
        'ALTER TABLE rent_dispute_cases ADD INDEX idx_dispute_rental_status (rental_id, status)',
        'ALTER TABLE rent_dispute_cases ADD INDEX idx_dispute_status_updated (status, updated_at)',
        'ALTER TABLE rent_dispute_messages ADD INDEX idx_dispute_msg_case_time (case_id, created_at)',
        'ALTER TABLE rent_dispute_messages ADD INDEX idx_dispute_msg_sender_time (sender_id, created_at)',
        'ALTER TABLE maintenance_tickets ADD INDEX idx_maint_tenant_status (tenant_id, status, updated_at)',
        'ALTER TABLE maintenance_tickets ADD INDEX idx_maint_dealer_status (dealer_id, status, updated_at)',
        'ALTER TABLE maintenance_tickets ADD INDEX idx_maint_rental_status (rental_id, status)',
        'ALTER TABLE maintenance_tickets ADD INDEX idx_maint_property (property_id)',
        'ALTER TABLE maintenance_tickets ADD INDEX idx_maint_status_updated (status, updated_at)',
    ];

    foreach ($statements as $sql) {
        try {
            $conn->exec($sql);
        } catch (Throwable) {
            // Index may already exist on upgraded databases.
        }
    }

    $indexed = true;
}

function fetchRental(PDO $conn, int $rentalId): ?array
{
    $stmt = $conn->prepare(
        "SELECT r.*, p.title AS property_title, p.id AS property_id
           FROM rentals r
           JOIN properties p ON p.id = r.property_id
          WHERE r.id = ?
            AND r.status = 'active'
          LIMIT 1"
    );
    $stmt->execute([$rentalId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    return $row ?: null;
}

function assertRentalParticipant(array $rental, array $user): void
{
    $uid = (int) $user['id'];
    $role = (string) $user['role'];
    if ($role === 'dealer' && (int) $rental['dealer_id'] === $uid) {
        return;
    }
    if (in_array($role, ['user', 'tenant'], true) && (int) $rental['tenant_id'] === $uid) {
        return;
    }
    supportErr('You are not linked to this rental.', 403);
}

function shapeDisputeCase(array $row): array
{
    return [
        'id' => (int) $row['id'],
        'rental_id' => (int) $row['rental_id'],
        'payment_id' => isset($row['payment_id']) ? (int) $row['payment_id'] : null,
        'tenant_id' => (int) $row['tenant_id'],
        'dealer_id' => (int) $row['dealer_id'],
        'dispute_type' => $row['dispute_type'],
        'summary' => $row['summary'],
        'status' => $row['status'],
        'property_title' => $row['property_title'] ?? null,
        'tenant_name' => $row['tenant_name'] ?? null,
        'dealer_name' => $row['dealer_name'] ?? null,
        'month_year' => $row['month_year'] ?? null,
        'payment_status' => $row['payment_status'] ?? null,
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
        'resolved_at' => $row['resolved_at'] ?? null,
    ];
}

function shapeMaintenanceTicket(array $row): array
{
    $photo = trim((string) ($row['photo_url'] ?? ''));
    if ($photo !== '' && ! str_starts_with($photo, 'http')) {
        $photo = 'https://houseforrent.site/'.ltrim($photo, '/');
    }

    return [
        'id' => (int) $row['id'],
        'rental_id' => (int) $row['rental_id'],
        'property_id' => (int) $row['property_id'],
        'tenant_id' => (int) $row['tenant_id'],
        'dealer_id' => (int) $row['dealer_id'],
        'title' => $row['title'],
        'description' => $row['description'],
        'category' => $row['category'],
        'priority' => $row['priority'],
        'status' => $row['status'],
        'dealer_note' => $row['dealer_note'],
        'photo_url' => $photo !== '' ? $photo : null,
        'property_title' => $row['property_title'] ?? null,
        'tenant_name' => $row['tenant_name'] ?? null,
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
        'resolved_at' => $row['resolved_at'] ?? null,
    ];
}

function storeMaintenancePhoto(int $ticketId, array $file): ?string
{
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        return null;
    }

    if (($file['size'] ?? 0) > SUPPORT_MAX_UPLOAD_BYTES) {
        supportErr('Photo must be 5 MB or smaller.');
    }

    $tmp = $file['tmp_name'] ?? '';
    if ($tmp === '' || ! is_uploaded_file($tmp)) {
        supportErr('Invalid upload.');
    }

    $imageInfo = @getimagesize($tmp);
    if ($imageInfo === false) {
        supportErr('Photo must be a valid image file.');
    }

    $mime = $imageInfo['mime'] ?? '';
    $allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (! in_array($mime, $allowed, true)) {
        supportErr('Photo must be JPG, PNG, or WEBP.');
    }

    $ext = match ($mime) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        default => 'jpg',
    };

    $dir = dirname(__DIR__).'/uploads/maintenance';
    if (! is_dir($dir)) {
        mkdir($dir, 0755, true);
    }

    $name = 'ticket_'.$ticketId.'_'.bin2hex(random_bytes(8)).'.'.$ext;
    $dest = $dir.'/'.$name;
    if (! move_uploaded_file($tmp, $dest)) {
        return null;
    }
    @chmod($dest, 0644);

    return 'uploads/maintenance/'.$name;
}

function countOpenDisputesForRental(PDO $conn, int $rentalId, ?int $paymentId): int
{
    if ($paymentId !== null && $paymentId > 0) {
        $stmt = $conn->prepare(
            "SELECT COUNT(*) FROM rent_dispute_cases
              WHERE rental_id = ? AND payment_id = ? AND status = 'open'"
        );
        $stmt->execute([$rentalId, $paymentId]);
    } else {
        $stmt = $conn->prepare(
            "SELECT COUNT(*) FROM rent_dispute_cases
              WHERE rental_id = ? AND status = 'open'"
        );
        $stmt->execute([$rentalId]);
    }

    return (int) $stmt->fetchColumn();
}

function countOpenMaintenanceForRental(PDO $conn, int $rentalId): int
{
    $stmt = $conn->prepare(
        "SELECT COUNT(*) FROM maintenance_tickets
          WHERE rental_id = ? AND status IN ('open','in_progress')"
    );
    $stmt->execute([$rentalId]);

    return (int) $stmt->fetchColumn();
}

function recentDisputeMessageCount(PDO $conn, int $caseId, int $senderId, int $seconds): int
{
    $stmt = $conn->prepare(
        "SELECT COUNT(*) FROM rent_dispute_messages
          WHERE case_id = ? AND sender_id = ? AND created_at >= (NOW() - INTERVAL ? SECOND)"
    );
    $stmt->execute([$caseId, $senderId, $seconds]);

    return (int) $stmt->fetchColumn();
}

// ── Request guards (before auth) ────────────────────────────────────────────
supportEnforceHttpMethod();
supportEnforceBodySize();

$clientIp = supportClientIp();
supportRateLimitOrAbort('support_ip_'.$clientIp, 90, 60);

$user = verifyToken();
if (! $user) {
    supportErr('Unauthorized', 401);
}

if (($user['role'] ?? '') === 'admin') {
    supportErr('Admins must use the website dashboard for support cases.', 403);
}

global $conn;
if (! ($conn instanceof PDO)) {
    supportErr('Database unavailable', 500);
}

ensureSupportTables($conn);

$input = supportInput();
$action = trim((string) ($input['action'] ?? ''));
supportValidateAction($action);
supportApplyActionRateLimit((int) $user['id'], $action);

try {
    switch ($action) {
        // ── Disputes ────────────────────────────────────────────────────────
        case 'create_dispute':
            if (! in_array($user['role'], ['user', 'tenant', 'dealer'], true)) {
                supportErr('Only tenants or dealers can open a dispute.', 403);
            }

            $rentalId = supportPositiveInt($input['rental_id'] ?? 0);
            $paymentId = supportPositiveInt($input['payment_id'] ?? 0);
            $disputeType = trim((string) ($input['dispute_type'] ?? 'tenant_claims_paid'));
            $message = supportSanitizeText((string) ($input['message'] ?? ''), SUPPORT_MAX_MESSAGE_LEN);

            if ($rentalId < 1 || $message === '') {
                supportErr('Rental and message are required.');
            }

            $allowedTypes = ['tenant_claims_paid', 'dealer_not_received', 'payment_rejected'];
            if (! in_array($disputeType, $allowedTypes, true)) {
                supportErr('Invalid dispute type.');
            }

            if ($user['role'] === 'dealer' && $disputeType === 'tenant_claims_paid') {
                supportErr('Dealers should use dealer_not_received or payment_rejected.');
            }
            if (in_array($user['role'], ['user', 'tenant'], true) && $disputeType === 'dealer_not_received') {
                supportErr('Tenants should use tenant_claims_paid or payment_rejected.');
            }

            $rental = fetchRental($conn, $rentalId);
            if (! $rental) {
                supportErr('Rental not found.', 404);
            }
            assertRentalParticipant($rental, $user);

            $openCount = countOpenDisputesForRental(
                $conn,
                $rentalId,
                $paymentId > 0 ? $paymentId : null
            );
            if ($openCount >= SUPPORT_MAX_OPEN_DISPUTES_PER_RENTAL) {
                supportErr('There is already an open dispute for this rental. Please use the existing case.', 409);
            }

            if ($paymentId > 0) {
                $payStmt = $conn->prepare(
                    'SELECT id FROM rent_payments WHERE id = ? AND rental_id = ? LIMIT 1'
                );
                $payStmt->execute([$paymentId, $rentalId]);
                if (! $payStmt->fetchColumn()) {
                    supportErr('Payment not found for this rental.', 404);
                }
            } else {
                $paymentId = null;
            }

            $summary = match ($disputeType) {
                'dealer_not_received' => 'Dealer did not receive rent payment',
                'payment_rejected' => 'Tenant disputes rejected payment',
                default => 'Tenant says rent was paid',
            };

            $conn->beginTransaction();
            $ins = $conn->prepare(
                'INSERT INTO rent_dispute_cases
                    (rental_id, payment_id, tenant_id, dealer_id, dispute_type, summary, status)
                 VALUES (?, ?, ?, ?, ?, ?, ?)'
            );
            $ins->execute([
                $rentalId,
                $paymentId,
                (int) $rental['tenant_id'],
                (int) $rental['dealer_id'],
                $disputeType,
                $summary,
                'open',
            ]);
            $caseId = (int) $conn->lastInsertId();

            $senderRole = $user['role'] === 'dealer' ? 'dealer' : 'tenant';
            $msg = $conn->prepare(
                'INSERT INTO rent_dispute_messages (case_id, sender_id, sender_role, message)
                 VALUES (?, ?, ?, ?)'
            );
            $msg->execute([$caseId, (int) $user['id'], $senderRole, $message]);
            $conn->commit();

            supportOk('Dispute opened. Admin will review the chat.', ['case_id' => $caseId]);
            break;

        case 'list_disputes':
            if ($user['role'] === 'dealer') {
                $stmt = $conn->prepare(
                    "SELECT c.*, p.title AS property_title,
                            tu.name AS tenant_name, du.name AS dealer_name,
                            rp.month_year, rp.status AS payment_status
                       FROM rent_dispute_cases c
                       JOIN properties p ON p.id = (
                           SELECT property_id FROM rentals WHERE id = c.rental_id LIMIT 1
                       )
                       JOIN users tu ON tu.id = c.tenant_id
                       JOIN users du ON du.id = c.dealer_id
                       LEFT JOIN rent_payments rp ON rp.id = c.payment_id
                      WHERE c.dealer_id = ?
                      ORDER BY FIELD(c.status,'open','resolved','closed'), c.updated_at DESC
                      LIMIT ".SUPPORT_LIST_LIMIT
                );
                $stmt->execute([(int) $user['id']]);
            } elseif (in_array($user['role'], ['user', 'tenant'], true)) {
                $stmt = $conn->prepare(
                    "SELECT c.*, p.title AS property_title,
                            tu.name AS tenant_name, du.name AS dealer_name,
                            rp.month_year, rp.status AS payment_status
                       FROM rent_dispute_cases c
                       JOIN properties p ON p.id = (
                           SELECT property_id FROM rentals WHERE id = c.rental_id LIMIT 1
                       )
                       JOIN users tu ON tu.id = c.tenant_id
                       JOIN users du ON du.id = c.dealer_id
                       LEFT JOIN rent_payments rp ON rp.id = c.payment_id
                      WHERE c.tenant_id = ?
                      ORDER BY FIELD(c.status,'open','resolved','closed'), c.updated_at DESC
                      LIMIT ".SUPPORT_LIST_LIMIT
                );
                $stmt->execute([(int) $user['id']]);
            } else {
                supportErr('Not allowed.', 403);
            }

            $cases = [];
            foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
                $cases[] = shapeDisputeCase($row);
            }
            supportOk('Disputes loaded.', ['cases' => $cases]);
            break;

        case 'get_dispute':
            $caseId = supportPositiveInt($input['case_id'] ?? 0);
            if ($caseId < 1) {
                supportErr('case_id is required.');
            }

            $stmt = $conn->prepare(
                "SELECT c.*, p.title AS property_title,
                        tu.name AS tenant_name, du.name AS dealer_name,
                        rp.month_year, rp.status AS payment_status
                   FROM rent_dispute_cases c
                   JOIN rentals r ON r.id = c.rental_id
                   JOIN properties p ON p.id = r.property_id
                   JOIN users tu ON tu.id = c.tenant_id
                   JOIN users du ON du.id = c.dealer_id
                   LEFT JOIN rent_payments rp ON rp.id = c.payment_id
                  WHERE c.id = ?
                  LIMIT 1"
            );
            $stmt->execute([$caseId]);
            $case = $stmt->fetch(PDO::FETCH_ASSOC);
            if (! $case) {
                supportErr('Dispute not found.', 404);
            }

            $uid = (int) $user['id'];
            if ($user['role'] === 'dealer' && (int) $case['dealer_id'] !== $uid) {
                supportErr('Not allowed.', 403);
            }
            if (in_array($user['role'], ['user', 'tenant'], true) && (int) $case['tenant_id'] !== $uid) {
                supportErr('Not allowed.', 403);
            }

            $msgs = $conn->prepare(
                "SELECT m.*, u.name AS sender_name
                   FROM rent_dispute_messages m
                   JOIN users u ON u.id = m.sender_id
                  WHERE m.case_id = ?
                  ORDER BY m.id ASC
                  LIMIT 500"
            );
            $msgs->execute([$caseId]);
            $messages = [];
            foreach ($msgs->fetchAll(PDO::FETCH_ASSOC) as $m) {
                $messages[] = [
                    'id' => (int) $m['id'],
                    'sender_id' => (int) $m['sender_id'],
                    'sender_role' => $m['sender_role'],
                    'sender_name' => $m['sender_name'],
                    'message' => $m['message'],
                    'created_at' => $m['created_at'],
                ];
            }

            supportOk('Dispute loaded.', [
                'case' => shapeDisputeCase($case),
                'messages' => $messages,
            ]);
            break;

        case 'send_dispute_message':
            $caseId = supportPositiveInt($input['case_id'] ?? 0);
            $message = supportSanitizeText((string) ($input['message'] ?? ''), SUPPORT_MAX_MESSAGE_LEN);
            if ($caseId < 1 || $message === '') {
                supportErr('case_id and message are required.');
            }

            $stmt = $conn->prepare('SELECT * FROM rent_dispute_cases WHERE id = ? LIMIT 1');
            $stmt->execute([$caseId]);
            $case = $stmt->fetch(PDO::FETCH_ASSOC);
            if (! $case) {
                supportErr('Dispute not found.', 404);
            }
            if ($case['status'] !== 'open') {
                supportErr('This dispute is closed.');
            }

            $uid = (int) $user['id'];
            $senderRole = null;
            if ($user['role'] === 'dealer' && (int) $case['dealer_id'] === $uid) {
                $senderRole = 'dealer';
            } elseif (in_array($user['role'], ['user', 'tenant'], true) && (int) $case['tenant_id'] === $uid) {
                $senderRole = 'tenant';
            }
            if ($senderRole === null) {
                supportErr('Not allowed.', 403);
            }

            if (recentDisputeMessageCount($conn, $caseId, $uid, 15) >= 5) {
                supportErr('You are sending messages too quickly. Please wait a moment.', 429);
            }

            $ins = $conn->prepare(
                'INSERT INTO rent_dispute_messages (case_id, sender_id, sender_role, message)
                 VALUES (?, ?, ?, ?)'
            );
            $ins->execute([$caseId, $uid, $senderRole, $message]);
            $conn->prepare('UPDATE rent_dispute_cases SET updated_at = NOW() WHERE id = ?')
                ->execute([$caseId]);

            supportOk('Message sent.', ['message_id' => (int) $conn->lastInsertId()]);
            break;

        // ── Maintenance ───────────────────────────────────────────────────────
        case 'create_maintenance':
            if (! in_array($user['role'], ['user', 'tenant'], true)) {
                supportErr('Only tenants can report maintenance issues.', 403);
            }

            $rentalId = supportPositiveInt($input['rental_id'] ?? 0);
            $title = supportSanitizeText((string) ($input['title'] ?? ''), SUPPORT_MAX_TITLE_LEN);
            $description = supportSanitizeText((string) ($input['description'] ?? ''), SUPPORT_MAX_DESC_LEN);
            $category = supportSanitizeText((string) ($input['category'] ?? 'general'), 50) ?: 'general';
            $priority = trim((string) ($input['priority'] ?? 'normal')) ?: 'normal';

            if ($rentalId < 1 || $title === '' || $description === '') {
                supportErr('Rental, title, and description are required.');
            }
            if (! in_array($priority, ['low', 'normal', 'urgent'], true)) {
                $priority = 'normal';
            }
            $allowedCategories = ['plumbing', 'electrical', 'structural', 'general', 'appliance', 'security'];
            if (! in_array($category, $allowedCategories, true)) {
                $category = 'general';
            }

            $rental = fetchRental($conn, $rentalId);
            if (! $rental) {
                supportErr('Rental not found.', 404);
            }
            if ((int) $rental['tenant_id'] !== (int) $user['id']) {
                supportErr('Not your rental.', 403);
            }

            if (countOpenMaintenanceForRental($conn, $rentalId) >= SUPPORT_MAX_OPEN_TICKETS_PER_RENTAL) {
                supportErr('Too many open maintenance requests for this rental. Wait for existing tickets to be resolved.', 409);
            }

            $ins = $conn->prepare(
                'INSERT INTO maintenance_tickets
                    (rental_id, property_id, tenant_id, dealer_id, title, description, category, priority, status)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
            );
            $ins->execute([
                $rentalId,
                (int) $rental['property_id'],
                (int) $rental['tenant_id'],
                (int) $rental['dealer_id'],
                mb_substr($title, 0, SUPPORT_MAX_TITLE_LEN),
                $description,
                mb_substr($category, 0, 50),
                $priority,
                'open',
            ]);
            $ticketId = (int) $conn->lastInsertId();

            $photoPath = null;
            if (! empty($_FILES['photo'])) {
                $photoPath = storeMaintenancePhoto($ticketId, $_FILES['photo']);
                if ($photoPath) {
                    $conn->prepare('UPDATE maintenance_tickets SET photo_url = ? WHERE id = ?')
                        ->execute([$photoPath, $ticketId]);
                }
            }

            supportOk('Maintenance request submitted.', ['ticket_id' => $ticketId]);
            break;

        case 'list_maintenance':
            if ($user['role'] === 'dealer') {
                $stmt = $conn->prepare(
                    "SELECT t.*, p.title AS property_title, u.name AS tenant_name
                       FROM maintenance_tickets t
                       JOIN properties p ON p.id = t.property_id
                       JOIN users u ON u.id = t.tenant_id
                      WHERE t.dealer_id = ?
                      ORDER BY FIELD(t.status,'open','in_progress','resolved','closed'), t.updated_at DESC
                      LIMIT ".SUPPORT_LIST_LIMIT
                );
                $stmt->execute([(int) $user['id']]);
            } elseif (in_array($user['role'], ['user', 'tenant'], true)) {
                $stmt = $conn->prepare(
                    "SELECT t.*, p.title AS property_title, u.name AS tenant_name
                       FROM maintenance_tickets t
                       JOIN properties p ON p.id = t.property_id
                       JOIN users u ON u.id = t.tenant_id
                      WHERE t.tenant_id = ?
                      ORDER BY t.updated_at DESC
                      LIMIT ".SUPPORT_LIST_LIMIT
                );
                $stmt->execute([(int) $user['id']]);
            } else {
                supportErr('Not allowed.', 403);
            }

            $tickets = [];
            foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
                $tickets[] = shapeMaintenanceTicket($row);
            }
            supportOk('Maintenance tickets loaded.', ['tickets' => $tickets]);
            break;

        case 'update_maintenance':
            if ($user['role'] !== 'dealer') {
                supportErr('Only dealers can update maintenance tickets.', 403);
            }

            $ticketId = supportPositiveInt($input['ticket_id'] ?? 0);
            $status = trim((string) ($input['status'] ?? ''));
            $note = supportSanitizeText((string) ($input['dealer_note'] ?? ''), SUPPORT_MAX_NOTE_LEN);

            if ($ticketId < 1) {
                supportErr('ticket_id is required.');
            }
            if (! in_array($status, ['open', 'in_progress', 'resolved', 'closed'], true)) {
                supportErr('Invalid status.');
            }

            $stmt = $conn->prepare(
                'SELECT * FROM maintenance_tickets WHERE id = ? AND dealer_id = ? LIMIT 1'
            );
            $stmt->execute([$ticketId, (int) $user['id']]);
            $ticket = $stmt->fetch(PDO::FETCH_ASSOC);
            if (! $ticket) {
                supportErr('Ticket not found.', 404);
            }

            $resolvedAt = in_array($status, ['resolved', 'closed'], true) ? date('Y-m-d H:i:s') : null;
            $upd = $conn->prepare(
                'UPDATE maintenance_tickets
                    SET status = ?, dealer_note = ?, resolved_at = ?, updated_at = NOW()
                  WHERE id = ?'
            );
            $upd->execute([
                $status,
                $note !== '' ? $note : $ticket['dealer_note'],
                $resolvedAt,
                $ticketId,
            ]);

            supportOk('Ticket updated.');
            break;

        default:
            supportErr('Unknown or disallowed action.', 400);
    }
} catch (Throwable $e) {
    if ($conn instanceof PDO && $conn->inTransaction()) {
        $conn->rollBack();
    }
    error_log('support_cases ['.$action.'] uid='.(int) ($user['id'] ?? 0).': '.$e->getMessage());
    supportErr('Server error. Please try again.', 500);
}
