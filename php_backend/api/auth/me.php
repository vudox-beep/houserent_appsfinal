<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

$user = verifyToken();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $conn->prepare("SELECT id, name, email, phone, role, identity_verified, verification_document FROM users WHERE id = ?");
        $stmt->execute([$user['id']]);
        
        if ($stmt->rowCount() == 0) {
            http_response_code(404);
            echo json_encode(["message" => "User not found"]);
            exit();
        }

        echo json_encode($stmt->fetch());
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