<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../../db.php';
require_once '../../auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method']);
    exit;
}

$user = verifyToken();
if (!$user || !isset($user['id'])) {
    echo json_encode(['status' => 'error', 'message' => 'Unauthorized']);
    exit;
}
$dealer_id = $user['id'];

try {
    // Fetch Active Tenants for this Dealer
    // We join rentals with properties to get property details
    // We join rentals with users to get tenant details
    $stmt_tenants = $conn->prepare("
        SELECT 
            r.id as rental_id,
            r.status,
            r.start_date,
            r.end_date,
            r.rent_amount,
            r.payment_reference,
            r.room_number,
            p.title as property_name,
            u.name as tenant_name,
            u.email as tenant_email
        FROM rentals r
        JOIN properties p ON r.property_id = p.id
        JOIN users u ON r.tenant_id = u.id
        WHERE r.dealer_id = :dealer_id AND r.status = 'active'
        ORDER BY r.created_at DESC
    ");
    $stmt_tenants->execute([':dealer_id' => $dealer_id]);
    $active_tenants = $stmt_tenants->fetchAll(PDO::FETCH_ASSOC);

    // Fetch Recent Activity (Rent payments)
    // We join rent_payments with rentals to verify it belongs to the dealer
    // We join with users to get tenant name
    // We join with properties to get property name
    $stmt_activity = $conn->prepare("
        SELECT 
            rp.id as payment_id,
            rp.amount,
            rp.status as payment_status,
            rp.created_at as date,
            rp.payment_method,
            rp.month_year,
            u.name as tenant_name,
            p.title as property_name
        FROM rent_payments rp
        JOIN rentals r ON rp.rental_id = r.id
        JOIN users u ON rp.tenant_id = u.id
        JOIN properties p ON r.property_id = p.id
        WHERE r.dealer_id = :dealer_id
        ORDER BY rp.created_at DESC
        LIMIT 10
    ");
    $stmt_activity->execute([':dealer_id' => $dealer_id]);
    $recent_activity = $stmt_activity->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'status' => 'success',
        'data' => [
            'active_tenants' => $active_tenants,
            'recent_activity' => $recent_activity
        ]
    ]);

} catch (PDOException $e) {
    echo json_encode(['status' => 'error', 'message' => 'Database Error: ' . $e->getMessage()]);
}
