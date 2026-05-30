<?php
ob_start();
ini_set('display_errors', 0);
error_reporting(E_ALL);

function json_response(array $payload, int $code = 200): void {
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../db.php';
require_once '../auth.php';

$method = $_SERVER['REQUEST_METHOD'];
$action = $_POST['action'] ?? ($_GET['action'] ?? '');

// If receiving raw JSON
$rawInput = file_get_contents("php://input");
if (!empty($rawInput)) {
    $decoded = json_decode($rawInput, true);
    if (is_array($decoded)) {
        if (isset($decoded['action'])) {
            $action = $decoded['action'];
        }
        $_POST = array_merge($_POST, $decoded);
    }
}

if ($action === 'get_requests') {
    try {
        // Fetch all requests, joining with the users table to get the name, and subquery for comment count
        $stmt = $conn->prepare("
            SELECT tr.*, u.name, u.role,
            (SELECT COUNT(*) FROM tenant_request_comments WHERE request_id = tr.id) as comment_count
            FROM tenant_requests tr
            JOIN users u ON tr.user_id = u.id
            ORDER BY tr.created_at ASC
            LIMIT 100
        ");
        $stmt->execute();
        $requests = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Fetch all comments for these requests
        if (!empty($requests)) {
            $request_ids = array_column($requests, 'id');
            $in_clause = implode(',', array_fill(0, count($request_ids), '?'));
            $comment_stmt = $conn->prepare("
                SELECT c.*, u.name, u.role 
                FROM tenant_request_comments c
                JOIN users u ON c.user_id = u.id
                WHERE c.request_id IN ($in_clause)
                ORDER BY c.created_at ASC
            ");
            $comment_stmt->execute($request_ids);
            $all_comments = $comment_stmt->fetchAll(PDO::FETCH_ASSOC);

            $comments_by_request = [];
            foreach ($all_comments as $comment) {
                $comments_by_request[$comment['request_id']][] = $comment;
            }

            foreach ($requests as &$req) {
                $req['comments'] = $comments_by_request[$req['id']] ?? [];
            }
        }

        json_response(['status' => 'success', 'data' => $requests]);
    } catch (Exception $e) {
        // Fallback if comment table doesn't exist yet
        if (strpos($e->getMessage(), 'Base table or view not found') !== false) {
            $stmt = $conn->prepare("
                SELECT tr.*, u.name, u.role, 0 as comment_count
                FROM tenant_requests tr
                JOIN users u ON tr.user_id = u.id
                ORDER BY tr.created_at ASC
                LIMIT 100
            ");
            $stmt->execute();
            $requests = $stmt->fetchAll(PDO::FETCH_ASSOC);
            json_response(['status' => 'success', 'data' => $requests]);
        }
        json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
    }
} elseif ($action === 'get_requests_count') {
    try {
        $stmt = $conn->prepare("SELECT COUNT(*) as total FROM tenant_requests");
        $stmt->execute();
        $result = $stmt->fetch(PDO::FETCH_ASSOC);
        json_response(['status' => 'success', 'data' => ['total' => (int)$result['total']]]);
    } catch (Exception $e) {
        json_response(['status' => 'success', 'data' => ['total' => 0]]); // Fallback
    }
} elseif ($action === 'add_request') {
    $user = verifyToken();
    if (!$user || !isset($user['id'])) {
        json_response(['status' => 'error', 'message' => 'Unauthorized'], 401);
    }

    $user_id = $user['id'];
    $message = $_POST['message'] ?? '';
    $property_type = $_POST['property_type'] ?? 'Any';
    $location = $_POST['location'] ?? 'Any';
    $budget = !empty($_POST['budget']) ? floatval($_POST['budget']) : null;

    if (empty(trim($message))) {
        json_response(['status' => 'error', 'message' => 'Message is required.']);
    }

    try {
        $stmt = $conn->prepare("
            INSERT INTO tenant_requests (user_id, message, property_type, location, budget) 
            VALUES (?, ?, ?, ?, ?)
        ");
        $stmt->execute([$user_id, $message, $property_type, $location, $budget]);
        $new_id = $conn->lastInsertId();

        // Fetch the newly created record to send back to Flutter/Supabase Broadcast
        $fetchStmt = $conn->prepare("
            SELECT tr.*, u.name, u.role 
            FROM tenant_requests tr 
            JOIN users u ON tr.user_id = u.id 
            WHERE tr.id = ?
        ");
        $fetchStmt->execute([$new_id]);
        $new_request = $fetchStmt->fetch(PDO::FETCH_ASSOC);
        $new_request['comments'] = [];
        $new_request['comment_count'] = 0;

        json_response(['status' => 'success', 'data' => $new_request]);
    } catch (Exception $e) {
        json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
    }
} elseif ($action === 'get_comments') {
    $request_id = $_POST['request_id'] ?? ($_GET['request_id'] ?? null);
    if (!$request_id) {
        json_response(['status' => 'error', 'message' => 'Request ID required']);
    }

    try {
        $stmt = $conn->prepare("
            SELECT c.*, u.name, u.role 
            FROM tenant_request_comments c
            JOIN users u ON c.user_id = u.id
            WHERE c.request_id = ?
            ORDER BY c.created_at ASC
        ");
        $stmt->execute([$request_id]);
        $comments = $stmt->fetchAll(PDO::FETCH_ASSOC);

        json_response(['status' => 'success', 'data' => $comments]);
    } catch (Exception $e) {
        // Fallback if table doesn't exist yet so it doesn't crash
        if (strpos($e->getMessage(), 'Base table or view not found') !== false) {
            json_response(['status' => 'success', 'data' => []]);
        }
        json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
    }
} elseif ($action === 'add_comment') {
    $user = verifyToken();
    if (!$user || !isset($user['id'])) {
        json_response(['status' => 'error', 'message' => 'Unauthorized'], 401);
    }

    $request_id = $_POST['request_id'] ?? null;
    $comment = $_POST['comment'] ?? '';

    if (!$request_id || empty(trim($comment))) {
        json_response(['status' => 'error', 'message' => 'Request ID and comment are required']);
    }

    try {
        $stmt = $conn->prepare("INSERT INTO tenant_request_comments (request_id, user_id, comment) VALUES (?, ?, ?)");
        $stmt->execute([$request_id, $user['id'], $comment]);
        $new_id = $conn->lastInsertId();

        $fetchStmt = $conn->prepare("
            SELECT c.*, u.name, u.role 
            FROM tenant_request_comments c 
            JOIN users u ON c.user_id = u.id 
            WHERE c.id = ?
        ");
        $fetchStmt->execute([$new_id]);
        $new_comment = $fetchStmt->fetch(PDO::FETCH_ASSOC);

        json_response(['status' => 'success', 'data' => $new_comment]);
    } catch (Exception $e) {
        json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
    }
} else {
    json_response(['status' => 'error', 'message' => 'Invalid action']);
}
