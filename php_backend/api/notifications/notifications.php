<?php
require_once '../cors.php';
require_once '../db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

$payload = json_decode(file_get_contents('php://input'), true) ?? [];
$user_id = (int)($payload['user_id'] ?? 0);
$role = (string)($payload['role'] ?? 'user');
$action = (string)($payload['action'] ?? '');

if ($action !== 'get_notifications') {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
    exit;
}

try {
    // If user_id is 0, return public notifications (no login required)
    if ($user_id === 0) {
        $stmt = $conn->prepare("
            SELECT 
                id,
                title,
                message,
                type,
                'info' AS icon,
                is_active,
                created_at,
                0 AS is_read
            FROM notifications
            WHERE is_active = 1
              AND target_role IN ('all', 'user', 'dealer')
            ORDER BY created_at DESC
            LIMIT 200
        ");
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        echo json_encode([
            'status' => 'success',
            'data' => $rows,
        ]);
        exit;
    }

    // For logged-in users, return notifications targeted to their role
    $stmt = $conn->prepare("
        SELECT 
            n.id,
            n.title,
            n.message,
            n.type,
            'info' AS icon,
            n.is_active,
            n.created_at,
            COALESCE(nr.id, 0) AS is_read
        FROM notifications n
        LEFT JOIN notification_reads nr ON n.id = nr.notification_id AND nr.user_id = ?
        WHERE n.is_active = 1
          AND n.target_role IN ('all', ?)
        ORDER BY n.created_at DESC
        LIMIT 200
    ");
    $stmt->execute([$user_id, $role]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'status' => 'success',
        'data' => $rows,
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Failed to load notifications']);
}
