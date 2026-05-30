<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

$user = verifyToken();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $conn->prepare("
            SELECT u.id, u.name, u.email, u.phone, u.role, u.identity_verified, u.verification_document,
                   (SELECT COUNT(*) FROM transactions t WHERE t.user_id = u.id AND t.amount >= 5 AND (t.status = 'successful' OR t.status = 'SUCCESSFUL' OR t.status = 'completed' OR t.status = 'COMPLETED')) as pro_count
            FROM users u WHERE u.id = ?
        ");
        $stmt->execute([$user['id']]);
        
        if ($stmt->rowCount() == 0) {
            http_response_code(404);
            echo json_encode(["message" => "User not found"]);
            exit();
        }

        $userData = $stmt->fetch(PDO::FETCH_ASSOC);
        $userData['is_pro'] = ($userData['pro_count'] > 0);
        unset($userData['pro_count']); // Remove the count from response
        
        echo json_encode($userData);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error"]);
    }
} elseif ($_SERVER['REQUEST_METHOD'] === 'PUT') {
    $data = json_decode(file_get_contents("php://input"));
    if (!isset($data->name) || !isset($data->phone)) {
        http_response_code(400);
        echo json_encode(["message" => "Incomplete data"]);
        exit();
    }

    try {
        $stmt = $conn->prepare("UPDATE users SET name = ?, phone = ? WHERE id = ?");
        $stmt->execute([$data->name, $data->phone, $user['id']]);
        echo json_encode(["message" => "Profile updated successfully"]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error updating profile"]);
    }
} else {
    http_response_code(405);
}
?>