<?php 
header('Content-Type: application/json'); 
header('Access-Control-Allow-Origin: *'); 
header('Access-Control-Allow-Methods: POST'); 
header('Access-Control-Allow-Headers: Content-Type, Authorization'); 

require_once '../db.php'; 
require_once '../auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { 
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method. Must be POST']); 
    exit; 
} 

$user = verifyToken();
if (!$user || !isset($user['id'])) {
    echo json_encode(['status' => 'error', 'message' => 'Unauthorized']);       
    exit;
}
$tenant_id = $user['id'];

$action = $_POST['action'] ?? 'upload_proof'; 

if ($action === 'get_history') { 
    try {
        // Fetch tenant's active rental details 
        $sql_rental = "SELECT r.*, p.title as property_title, p.location, d.company_name as dealer_company, 
                       u.phone as dealer_phone, d.bank_name, d.bank_account 
                       FROM rentals r 
                       JOIN properties p ON r.property_id = p.id 
                       JOIN dealers d ON r.dealer_id = d.user_id 
                       JOIN users u ON d.user_id = u.id
                       WHERE r.tenant_id = :tid AND r.status = 'active' 
                       ORDER BY r.created_at DESC LIMIT 1"; 
        $stmt_rental = $conn->prepare($sql_rental); 
        $stmt_rental->execute([':tid' => $tenant_id]); 
        $rental_info = $stmt_rental->fetch(PDO::FETCH_ASSOC); 
    
        // Fetch payment history for this tenant 
        $sql_history = "SELECT rp.*, p.title as property_title 
                        FROM rent_payments rp 
                        JOIN rentals r ON rp.rental_id = r.id 
                        JOIN properties p ON r.property_id = p.id 
                        WHERE rp.tenant_id = :tid 
                        ORDER BY rp.created_at DESC"; 
        $stmt_history = $conn->prepare($sql_history); 
        $stmt_history->execute([':tid' => $tenant_id]); 
        $history_payments = $stmt_history->fetchAll(PDO::FETCH_ASSOC); 
    
        foreach ($history_payments as &$payment) { 
            if (!empty($payment['proof_file'])) { 
                $payment['proof_file'] = 'https://houseforrent.site/php_backend/api/' . ltrim($payment['proof_file'], '/'); 
            } 
        } 
        unset($payment); 
    
        echo json_encode([ 
            'status' => 'success', 
            'rental_info' => $rental_info, 
            'payment_history' => $history_payments 
        ]); 
    } catch (PDOException $e) {
        echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
    }
    exit; 
} 

// Default action: upload_proof 
$rental_id = $_POST['rental_id'] ?? ''; 
$month_year = $_POST['month_year'] ?? ''; // e.g. "April 2024" 
$amount = $_POST['amount'] ?? ''; 
$payment_method = $_POST['payment_method'] ?? 'bank_transfer'; // Optional: bank_transfer, mobile_money, cash 
$reference_number = $_POST['reference_number'] ?? ('REF-' . substr(time() . rand(100, 999), 0, 16));

if (empty($rental_id) || empty($month_year) || empty($amount)) { 
    echo json_encode(['status' => 'error', 'message' => 'Rental ID, Month/Year, and Amount are required']); 
    exit; 
} 

$dbPath = null;
$fullUrl = null;

if ($payment_method !== 'Cash') {
    if (!isset($_FILES['proof_image']) || $_FILES['proof_image']['error'] !== UPLOAD_ERR_OK) { 
        echo json_encode(['status' => 'error', 'message' => 'Please upload a proof of payment image']); 
        exit; 
    } 

    $uploadDir = '../../../assets/images/proofs/'; 
    if (!is_dir($uploadDir)) { 
        mkdir($uploadDir, 0777, true); 
    } 

    // Generate unique filename 
    $fileExtension = strtolower(pathinfo($_FILES['proof_image']['name'], PATHINFO_EXTENSION)); 
    $allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf']; 

    if (!in_array($fileExtension, $allowedExtensions)) { 
        echo json_encode(['status' => 'error', 'message' => 'Invalid file format. Only JPG, PNG, and PDF are allowed.']); 
        exit; 
    } 

    $fileName = 'proof_' . $tenant_id . '_' . time() . '.' . $fileExtension; 
    $targetPath = $uploadDir . $fileName; 

    if (move_uploaded_file($_FILES['proof_image']['tmp_name'], $targetPath)) { 
        $dbPath = 'assets/images/proofs/' . $fileName; 
        $fullUrl = 'https://houseforrent.site/' . $dbPath; 
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Failed to save uploaded file on server']); 
        exit;
    }
}

try {
    // Insert pending payment record 
    $sql = "INSERT INTO rent_payments (rental_id, tenant_id, month_year, amount, currency, status, payment_method, proof_file, months_paid) 
            VALUES (:rid, :tid, :my, :amt, 'ZMW', 'pending', :method, :proof, 1)"; 
    // If the database has a reference_number column we should insert it here.
    // If not, we will just use the existing query. Assuming rent_payments table might be updated later.
    // I'll leave the query as is since we checked the schema and it didn't have reference_number. 
    // If it does have it or you add it, we can change this to include reference_number.
    
    $stmt = $conn->prepare($sql); 
    if ($stmt->execute([ 
        ':rid' => $rental_id, 
        ':tid' => $tenant_id, 
        ':my' => $month_year, 
        ':amt' => $amount, 
        ':method' => $payment_method, 
        ':proof' => $dbPath 
    ])) { 
        echo json_encode([ 
            'status' => 'success', 
            'message' => 'Payment submitted successfully. Waiting for dealer approval.', 
            'proof_url' => $fullUrl 
        ]); 
    } else { 
        echo json_encode(['status' => 'error', 'message' => 'Database error. Could not save payment.']); 
    }
} catch (PDOException $e) {
    echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
}
