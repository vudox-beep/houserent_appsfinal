<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

$user = authorize(['user', 'tenant']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $conn->prepare("
            SELECT rp.*, p.title as property_title, p.location
            FROM rent_payments rp
            JOIN rentals r ON rp.rental_id = r.id
            JOIN properties p ON r.property_id = p.id
            WHERE rp.tenant_id = ?
            ORDER BY rp.created_at DESC
        ");
        $stmt->execute([$user['id']]);
        
        echo json_encode($stmt->fetchAll());
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error fetching payment history"]);
    }
} else {
    http_response_code(405);
}
?>