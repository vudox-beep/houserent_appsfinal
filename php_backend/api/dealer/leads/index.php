<?php
require_once '../../cors.php';
require_once '../../db.php';
require_once '../../auth.php';

$user = authorize(['dealer', 'admin']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $conn->prepare("
            SELECT l.*, p.title as property_title 
            FROM leads l
            JOIN properties p ON l.property_id = p.id
            WHERE l.dealer_id = ?
            ORDER BY l.created_at DESC
        ");
        $stmt->execute([$user['id']]);
        
        echo json_encode($stmt->fetchAll());
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error fetching leads"]);
    }
} else {
    http_response_code(405);
}
?>