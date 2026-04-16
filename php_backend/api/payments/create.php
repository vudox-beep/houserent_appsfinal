<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

$user = authorize(['user', 'tenant']);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode(file_get_contents("php://input"), true);
    
    $rental_id = $data['rental_id'] ?? null;
    $amount = $data['amount'] ?? null;
    $month_year = $data['month_year'] ?? date('F Y');
    $payment_method = $data['payment_method'] ?? 'bank_transfer';
    $months_paid = $data['months_paid'] ?? 1;
    $currency = $data['currency'] ?? 'ZMW';

    if (!$rental_id || !$amount) {
        http_response_code(400);
        echo json_encode(["message" => "Rental ID and amount are required"]);
        exit;
    }

    try {
        $stmt = $conn->prepare("
            INSERT INTO rent_payments 
            (rental_id, tenant_id, month_year, amount, currency, payment_method, months_paid, status) 
            VALUES (?, ?, ?, ?, ?, ?, ?, 'pending')
        ");
        $stmt->execute([
            $rental_id, 
            $user['id'], 
            $month_year, 
            $amount, 
            $currency, 
            $payment_method, 
            $months_paid
        ]);
        
        echo json_encode(["message" => "Payment submitted successfully", "payment_id" => $conn->lastInsertId()]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error submitting payment"]);
    }
} else {
    http_response_code(405);
}
?>