<?php
// notifications.php - Upload to: php_backend/api/notifications/notifications.php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}
require_once '../db.php';

$input = json_decode(file_get_contents('php://input'), true) ?? [];
// Also support form data
if (empty($input)) {
    $input = $_POST;
}
$action = $input['action'] ?? $_GET['action'] ?? '';
$user_id = intval($input['user_id'] ?? 0);
$role    = $input['role'] ?? 'user';

try {
    // Website/admin API: keep database notifications and also send Firebase.
    if (
        in_array($action, ['send_notification', 'create_notification', 'notify'], true) ||
        ($action === '' && (!empty($input['message']) || !empty($input['body'])))
    ) {
        $title = trim((string)($input['title'] ?? 'HouseRent notification'));
        $message = trim((string)($input['message'] ?? $input['body'] ?? ''));
        $type = strtolower(trim((string)($input['type'] ?? 'info')));
        $targetRole = strtolower(trim((string)($input['target_role'] ?? 'all')));
        $createdBy = intval($input['created_by'] ?? $user_id);

        if ($message === '') {
            echo json_encode(['status' => 'error', 'message' => 'message is required']);
            exit();
        }
        if ($title === '') {
            $title = 'HouseRent notification';
        }
        if (!in_array($type, ['info', 'warning', 'danger', 'success'], true)) {
            $type = 'info';
        }
        if (!in_array($targetRole, ['all', 'dealer', 'user'], true)) {
            $targetRole = 'all';
        }

        $stmt = $conn->prepare("
            INSERT INTO notifications (title, message, type, target_role, is_active, created_by)
            VALUES (?, ?, ?, ?, 1, ?)
        ");
        $stmt->execute([
            $title,
            $message,
            $type,
            $targetRole,
            $createdBy > 0 ? $createdBy : null,
        ]);
        $notificationId = intval($conn->lastInsertId());

        $push = ['sent' => 0, 'failed' => 0, 'error' => null];
        try {
            $firebasePushFile = __DIR__ . '/firebase_push.php';
            if (!is_file($firebasePushFile)) {
                throw new RuntimeException('Firebase push helper is missing.');
            }
            require_once $firebasePushFile;

            $push = sendFirebaseNotificationToRole($conn, $targetRole, $title, $message, [
                'id' => (string)$notificationId,
                'notification_id' => (string)$notificationId,
                'title' => $title,
                'body' => $message,
                'message' => $message,
                'type' => $type,
                'target_role' => $targetRole,
            ]);
        } catch (Throwable $pushError) {
            $push['error'] = $pushError->getMessage();
            error_log('Firebase push setup failed: ' . $pushError->getMessage());
        }

        echo json_encode([
            'status' => 'success',
            'message' => 'Notification created',
            'notification_id' => $notificationId,
            'push' => $push,
        ]);
        exit();
    }

    // Flutter mobile app: save/update the Firebase token for this installation.
    if ($action === 'register_device') {
        if (!$user_id || empty($role)) {
            echo json_encode(['status' => 'error', 'message' => 'user_id and role are required']);
            exit();
        }

        $fcm_token = trim((string)($input['fcm_token'] ?? ''));
        $platform = strtolower(trim((string)($input['platform'] ?? 'android')));

        if ($fcm_token === '') {
            echo json_encode(['status' => 'error', 'message' => 'fcm_token required']);
            exit();
        }

        if (!in_array($platform, ['android', 'ios', 'web'], true)) {
            $platform = 'android';
        }

        $stmt = $conn->prepare("
            INSERT INTO user_device_tokens (user_id, fcm_token, platform, updated_at)
            VALUES (?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE
                user_id = VALUES(user_id),
                platform = VALUES(platform),
                updated_at = NOW()
        ");
        $stmt->execute([$user_id, $fcm_token, $platform]);
        echo json_encode(['status' => 'success', 'message' => 'Device registered']);

    // Flutter mobile app: stop pushes to this installation after logout.
    } elseif ($action === 'unregister_device') {
        if (!$user_id || empty($role)) {
            echo json_encode(['status' => 'error', 'message' => 'user_id and role are required']);
            exit();
        }

        $fcm_token = trim((string)($input['fcm_token'] ?? ''));

        if ($fcm_token === '') {
            echo json_encode(['status' => 'error', 'message' => 'fcm_token required']);
            exit();
        }

        $stmt = $conn->prepare("
            DELETE FROM user_device_tokens
            WHERE user_id = ? AND fcm_token = ?
        ");
        $stmt->execute([$user_id, $fcm_token]);
        echo json_encode(['status' => 'success', 'message' => 'Device removed']);

    // Get notifications for this role (all + role-specific), that are active
    } elseif ($action === 'get_notifications') {
        if (empty($role)) {
            echo json_encode(['status' => 'error', 'message' => 'role is required']);
            exit();
        }

        // Private (per-user) notifications support
        try {
            $conn->exec("ALTER TABLE notifications ADD COLUMN target_user_id INT NULL DEFAULT NULL");
        } catch (Throwable $e) {
        }

        $roleNorm = strtolower(trim((string) $role));
        if ($roleNorm === 'tenant') {
            $roleNorm = 'user';
        }

        // target_user_id set → only that user sees it
        // target_user_id NULL → broadcast by role as before
        $stmt = $conn->prepare("
            SELECT
                n.id,
                n.title,
                n.message,
                n.type,
                n.target_role,
                n.created_at,
                CASE WHEN nr.id IS NOT NULL THEN 1 ELSE 0 END AS is_read
            FROM notifications n
            LEFT JOIN notification_reads nr ON nr.notification_id = n.id AND nr.user_id = ?
            WHERE n.is_active = 1
              AND (
                    n.target_user_id = ?
                 OR (
                        n.target_user_id IS NULL
                    AND (n.target_role = 'all' OR n.target_role = ?)
                 )
              )
            ORDER BY n.created_at DESC
        ");
        $stmt->execute([$user_id, $user_id, $roleNorm]);
        $notifications = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode([
            'status' => 'success',
            'data'   => $notifications,
            'unread_count' => count(array_filter($notifications, fn($n) => $n['is_read'] == 0))
        ]);
    } elseif ($action === 'mark_read') {
        if (!$user_id || empty($role)) {
            echo json_encode(['status' => 'error', 'message' => 'user_id and role are required']);
            exit();
        }

        $notification_id = intval($input['notification_id'] ?? 0);
        if (!$notification_id) {
            echo json_encode(['status' => 'error', 'message' => 'notification_id required']);
            exit();
        }
        // Insert ignore to avoid duplicate
        $stmt = $conn->prepare("
            INSERT IGNORE INTO notification_reads (notification_id, user_id)
            VALUES (?, ?)
        ");
        $stmt->execute([$notification_id, $user_id]);
        echo json_encode(['status' => 'success', 'message' => 'Marked as read']);
    } elseif ($action === 'mark_all_read') {
        if (!$user_id || empty($role)) {
            echo json_encode(['status' => 'error', 'message' => 'user_id and role are required']);
            exit();
        }

        // Get all unread notification IDs for this user/role
        try {
            $conn->exec("ALTER TABLE notifications ADD COLUMN target_user_id INT NULL DEFAULT NULL");
        } catch (Throwable $e) {
        }
        $roleNorm = strtolower(trim((string) $role));
        if ($roleNorm === 'tenant') {
            $roleNorm = 'user';
        }
        $stmt = $conn->prepare("
            SELECT n.id FROM notifications n
            LEFT JOIN notification_reads nr ON nr.notification_id = n.id AND nr.user_id = ?
            WHERE n.is_active = 1
              AND (
                    n.target_user_id = ?
                 OR (
                        n.target_user_id IS NULL
                    AND (n.target_role = 'all' OR n.target_role = ?)
                 )
              )
              AND nr.id IS NULL
        ");
        $stmt->execute([$user_id, $user_id, $roleNorm]);
        $unread = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $insertStmt = $conn->prepare("INSERT IGNORE INTO notification_reads (notification_id, user_id) VALUES (?, ?)");
        foreach ($unread as $notif) {
            $insertStmt->execute([$notif['id'], $user_id]);
        }
        echo json_encode(['status' => 'success', 'message' => 'All marked as read']);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
} catch (Throwable $e) {
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
