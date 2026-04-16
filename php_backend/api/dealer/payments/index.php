<?php
require_once '../../cors.php';
require_once '../../db.php';
require_once '../../auth.php';

$user = authorize(['dealer', 'admin']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $conn->prepare("
            SELECT rp.*, p.title as property_title, u.name as tenant_name, r.payment_reference       
            FROM rent_payments rp
            JOIN rentals r ON rp.rental_id = r.id
            JOIN properties p ON r.property_id = p.id
            JOIN users u ON rp.tenant_id = u.id
            WHERE r.dealer_id = ?
            ORDER BY rp.created_at DESC
        ");
        $stmt->execute([$user['id']]);
        
        echo json_encode($stmt->fetchAll());
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error fetching payments"]);
    }
} else {
    http_response_code(405);
}
?>