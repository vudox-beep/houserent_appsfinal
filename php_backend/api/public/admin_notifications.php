<?php
require_once '../cors.php';
require_once '../db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

try {
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
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Failed to load admin notifications']);
}
