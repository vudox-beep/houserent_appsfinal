<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../../db.php';
require_once '../../auth.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

$user = verifyToken();
if (!$user || !isset($user['id'])) {
    echo json_encode(['status' => 'error', 'message' => 'Unauthorized']);
    exit;
}
$dealer_id = $user['id'];

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) $data = $_POST;

$property_id = $data['property_id'] ?? null;
$status = $data['status'] ?? null; // 'available' or 'taken'

if (!$property_id || !$status) {
    echo json_encode(['status' => 'error', 'message' => 'Property ID and status are required.']);
    exit;
}

if (!in_array(strtolower($status), ['available', 'taken'])) {
    echo json_encode(['status' => 'error', 'message' => 'Invalid status. Must be available or taken.']);
    exit;
}

try {
    // Verify dealer owns this property
    $verifyStmt = $conn->prepare("SELECT id FROM properties WHERE id = ? AND dealer_id = ?");
    $verifyStmt->execute([$property_id, $dealer_id]);
    if (!$verifyStmt->fetch()) {
        echo json_encode(['status' => 'error', 'message' => 'Unauthorized to modify this property.']);
        exit;
    }

    $stmt = $conn->prepare("UPDATE properties SET status = ? WHERE id = ? AND dealer_id = ?");
    $stmt->execute([strtolower($status), $property_id, $dealer_id]);

    echo json_encode(['status' => 'success', 'message' => 'Property status updated successfully.']);
} catch (PDOException $e) {
    echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
}
