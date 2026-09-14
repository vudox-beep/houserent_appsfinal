<?php
/**
 * Private chat between agents and house-hunt request owners.
 * POST /php_backend/api/agent_company/request_chat.php
 * actions: list_requests | get_messages | send_message
 *
 * tenant_requests columns: id, user_id, message, property_type, location, budget, created_at
 * (no title/description — those caused 500s)
 */
ob_start();
ini_set('display_errors', '0');
error_reporting(E_ALL);
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('X-Content-Type-Options: nosniff');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../auth.php';
require_once __DIR__ . '/helpers.php';

$limiterPath = __DIR__ . '/../includes/RateLimiter.php';
if (is_file($limiterPath)) {
    require_once $limiterPath;
}

function hr_chat_json(array $payload, int $code = 200): void
{
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($payload);
    exit;
}

function hr_chat_ip(): string
{
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        return (string) $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
    if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        return trim(explode(',', (string) $_SERVER['HTTP_X_FORWARDED_FOR'])[0]);
    }
    return (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
}

global $conn;
if (!isset($conn) || !($conn instanceof PDO)) {
    if (class_exists('Database')) {
        try {
            $conn = (new Database())->connect();
        } catch (Throwable $e) {
            hr_chat_json(['status' => 'error', 'message' => 'Database connection failed'], 500);
        }
    }
}
if (!($conn instanceof PDO)) {
    hr_chat_json(['status' => 'error', 'message' => 'Database connection failed'], 500);
}

try {
    hr_ac_ensure_tables($conn);
} catch (Throwable $e) {
    hr_chat_json([
        'status' => 'error',
        'message' => 'Could not prepare chat tables. Run agent_company SQL on the server.',
    ], 500);
}

$ip = hr_chat_ip();
if (class_exists('RateLimiter')) {
    $limiter = new RateLimiter(90, 60);
    if (!$limiter->check($ip . '_agent_request_chat')) {
        hr_chat_json(['status' => 'error', 'message' => 'Too many requests. Please slow down.'], 429);
    }
}

$authUser = authorize(['agent', 'user', 'tenant', 'admin']);
$authId = (int) $authUser['id'];
$authRole = strtolower(trim((string) $authUser['role']));
if ($authRole === 'tenant') {
    $authRole = 'user';
}

$data = json_decode(file_get_contents('php://input'), true);
if (!is_array($data)) {
    $data = $_POST;
}
$action = trim((string) ($data['action'] ?? ''));

try {
    if ($action === 'list_requests') {
        if ($authRole !== 'agent' && $authRole !== 'admin') {
            hr_chat_json(['status' => 'error', 'message' => 'Agents only'], 403);
        }

        // Match real tenant_requests schema (message + property_type, not title/description)
        $stmt = $conn->prepare(
            "SELECT tr.id,
                    tr.user_id,
                    tr.message,
                    tr.message AS title,
                    tr.message AS description,
                    tr.property_type,
                    tr.location,
                    tr.budget,
                    tr.created_at,
                    u.name AS seeker_name,
                    (SELECT COUNT(*) FROM request_agent_messages m
                     WHERE m.request_id = tr.id AND m.receiver_id = ? AND m.is_read = 0) AS unread
             FROM tenant_requests tr
             JOIN users u ON u.id = tr.user_id
             ORDER BY tr.created_at DESC
             LIMIT 50"
        );
        $stmt->execute([$authId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];

        // Friendly title for the app list
        foreach ($rows as &$row) {
            $msg = trim((string) ($row['message'] ?? ''));
            $ptype = trim((string) ($row['property_type'] ?? ''));
            $loc = trim((string) ($row['location'] ?? ''));
            $snippet = $msg !== '' ? mb_substr($msg, 0, 80) : 'House-hunt request';
            if ($ptype !== '' && strtolower($ptype) !== 'any') {
                $snippet = $ptype . ': ' . $snippet;
            }
            $row['title'] = $snippet;
            if ($loc !== '') {
                $row['location'] = $loc;
            }
        }
        unset($row);

        hr_chat_json(['status' => 'success', 'data' => $rows]);
    }

    if ($action === 'get_messages') {
        $requestId = (int) ($data['request_id'] ?? 0);
        if ($requestId < 1) {
            hr_chat_json(['status' => 'error', 'message' => 'request_id required']);
        }

        $req = $conn->prepare('SELECT id, user_id, message, location FROM tenant_requests WHERE id = ? LIMIT 1');
        $req->execute([$requestId]);
        $request = $req->fetch(PDO::FETCH_ASSOC);
        if (!$request) {
            hr_chat_json(['status' => 'error', 'message' => 'Request not found']);
        }
        $ownerId = (int) $request['user_id'];
        if ($authRole === 'agent' || $authRole === 'admin') {
            // ok
        } elseif ($authId !== $ownerId) {
            hr_chat_json(['status' => 'error', 'message' => 'Not allowed'], 403);
        }

        $stmt = $conn->prepare(
            "SELECT m.id, m.request_id, m.sender_id, m.receiver_id, m.message, m.is_read, m.created_at, u.name AS sender_name
             FROM request_agent_messages m
             JOIN users u ON u.id = m.sender_id
             WHERE m.request_id = ?
               AND (m.sender_id = ? OR m.receiver_id = ?)
             ORDER BY m.created_at ASC
             LIMIT 200"
        );
        $stmt->execute([$requestId, $authId, $authId]);
        $messages = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];

        $conn->prepare(
            'UPDATE request_agent_messages SET is_read = 1
             WHERE request_id = ? AND receiver_id = ? AND is_read = 0'
        )->execute([$requestId, $authId]);

        hr_chat_json([
            'status' => 'success',
            'request_id' => $requestId,
            'peer_user_id' => $authId === $ownerId ? null : $ownerId,
            'request_preview' => mb_substr(trim((string) ($request['message'] ?? '')), 0, 120),
            'data' => $messages,
        ]);
    }

    if ($action === 'send_message') {
        if (class_exists('RateLimiter')) {
            $sendLimiter = new RateLimiter(40, 60);
            if (!$sendLimiter->check('chat_send_' . $authId)) {
                hr_chat_json(['status' => 'error', 'message' => 'Sending too fast. Please wait.'], 429);
            }
        }

        $requestId = (int) ($data['request_id'] ?? 0);
        $message = trim((string) ($data['message'] ?? ''));
        if ($requestId < 1 || $message === '') {
            hr_chat_json(['status' => 'error', 'message' => 'request_id and message are required']);
        }
        if (strlen($message) > 2000) {
            hr_chat_json(['status' => 'error', 'message' => 'Message is too long']);
        }

        $req = $conn->prepare('SELECT id, user_id FROM tenant_requests WHERE id = ? LIMIT 1');
        $req->execute([$requestId]);
        $request = $req->fetch(PDO::FETCH_ASSOC);
        if (!$request) {
            hr_chat_json(['status' => 'error', 'message' => 'Request not found']);
        }
        $ownerId = (int) $request['user_id'];

        if ($authRole === 'agent' || $authRole === 'admin') {
            $receiverId = $ownerId;
        } elseif ($authId === $ownerId) {
            $agentId = (int) ($data['agent_id'] ?? 0);
            if ($agentId < 1) {
                $last = $conn->prepare(
                    "SELECT sender_id FROM request_agent_messages
                     WHERE request_id = ? AND sender_id <> ?
                     ORDER BY created_at DESC LIMIT 1"
                );
                $last->execute([$requestId, $authId]);
                $agentId = (int) ($last->fetchColumn() ?: 0);
            }
            if ($agentId < 1) {
                hr_chat_json(['status' => 'error', 'message' => 'No agent to reply to yet']);
            }
            $receiverId = $agentId;
        } else {
            hr_chat_json(['status' => 'error', 'message' => 'Not allowed'], 403);
        }

        $ins = $conn->prepare(
            'INSERT INTO request_agent_messages (request_id, sender_id, receiver_id, message)
             VALUES (?, ?, ?, ?)'
        );
        $ins->execute([$requestId, $authId, $receiverId, $message]);
        $newMsgId = (int) $conn->lastInsertId();

        // Notify ONLY the other party (agent → that tenant, or tenant → that agent).
        try {
            $senderName = 'Agent';
            $nameStmt = $conn->prepare('SELECT name, role FROM users WHERE id = ? LIMIT 1');
            $nameStmt->execute([$authId]);
            $senderRow = $nameStmt->fetch(PDO::FETCH_ASSOC) ?: [];
            $senderName = trim((string) ($senderRow['name'] ?? 'Someone'));
            $senderRole = strtolower(trim((string) ($senderRow['role'] ?? $authRole)));
            if ($senderRole === 'agent') {
                $senderName .= ' (Agent)';
            }

            $snippet = $message;
            if (strlen($snippet) > 100) {
                $snippet = substr($snippet, 0, 97) . '...';
            }

            $pushTitle = $senderRole === 'agent'
                ? 'New message from an agent'
                : 'New reply on your house hunt';
            $pushBody = $senderName . ': ' . $snippet;

            // Optional in-app row visible only to the receiver
            try {
                $conn->exec("ALTER TABLE notifications ADD COLUMN target_user_id INT NULL DEFAULT NULL");
            } catch (Throwable $e) {
                // column may already exist
            }
            try {
                $conn->exec("ALTER TABLE notifications MODIFY COLUMN target_role ENUM('all','dealer','user','agent','company') DEFAULT 'all'");
            } catch (Throwable $e) {
            }

            $notifTargetRole = ($senderRole === 'agent') ? 'user' : 'agent';
            $notificationId = 0;
            try {
                $notifStmt = $conn->prepare(
                    "INSERT INTO notifications (title, message, type, target_role, is_active, created_by, target_user_id)
                     VALUES (?, ?, 'info', ?, 1, ?, ?)"
                );
                $notifStmt->execute([$pushTitle, $pushBody, $notifTargetRole, $authId, $receiverId]);
                $notificationId = (int) $conn->lastInsertId();
            } catch (Throwable $e) {
                // If target_user_id column missing, skip DB row — push still goes to one user.
                error_log('private notif insert skipped: ' . $e->getMessage());
            }

            $firebasePushFile = dirname(__DIR__) . '/notifications/firebase_push.php';
            if (is_file($firebasePushFile)) {
                require_once $firebasePushFile;
                if (function_exists('sendFirebaseNotificationToUserIds')) {
                    sendFirebaseNotificationToUserIds(
                        $conn,
                        [$receiverId],
                        $pushTitle,
                        $pushBody,
                        [
                            'id' => (string) $notificationId,
                            'notification_id' => (string) $notificationId,
                            'type' => 'agent_request_chat',
                            'request_id' => (string) $requestId,
                            'message_id' => (string) $newMsgId,
                            'sender_id' => (string) $authId,
                            'receiver_id' => (string) $receiverId,
                            'target_user_id' => (string) $receiverId,
                            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                            'route' => $senderRole === 'agent'
                                ? '/tenant-requests'
                                : '/dealer-dashboard',
                        ]
                    );
                }
            }
        } catch (Throwable $notifyErr) {
            error_log('agent chat notify failed: ' . $notifyErr->getMessage());
        }

        hr_chat_json([
            'status' => 'success',
            'message' => 'Sent',
            'id' => $newMsgId,
        ]);
    }

    hr_chat_json(['status' => 'error', 'message' => 'Invalid action']);
} catch (Throwable $e) {
    error_log('agent request_chat: ' . $e->getMessage());
    hr_chat_json([
        'status' => 'error',
        'message' => 'Server error loading house-hunt chat. Please try again.',
        'error' => $e->getMessage(),
    ], 500);
}
