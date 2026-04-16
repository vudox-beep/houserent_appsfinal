<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

$user = verifyToken();
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    try {
        $stmt = $conn->prepare("
            SELECT sp.id as saved_id, p.*, u.name as dealer_name, u.phone as dealer_phone 
            FROM saved_properties sp
            JOIN properties p ON sp.property_id = p.id
            JOIN users u ON p.dealer_id = u.id
            WHERE sp.user_id = ?
        ");
        $stmt->execute([$user['id']]);
        $favorites = $stmt->fetchAll();

        foreach ($favorites as &$prop) {
            $imgStmt = $conn->prepare("SELECT image_path FROM property_images WHERE property_id = ?");
            $imgStmt->execute([$prop['id']]);
            $prop['images'] = $imgStmt->fetchAll(PDO::FETCH_COLUMN);
        }

        echo json_encode($favorites);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error fetching favorites"]);
    }
} elseif ($method === 'POST') {
    $data = json_decode(file_get_contents("php://input"));
    $property_id = $data->property_id ?? null;

    if (!$property_id) {
        http_response_code(400);
        echo json_encode(["message" => "Property ID required"]);
        exit();
    }

    try {
        $stmt = $conn->prepare("SELECT * FROM saved_properties WHERE user_id = ? AND property_id = ?");
        $stmt->execute([$user['id'], $property_id]);
        
        if ($stmt->rowCount() > 0) {
            http_response_code(400);
            echo json_encode(["message" => "Property already saved"]);
            exit();
        }

        $stmt = $conn->prepare("INSERT INTO saved_properties (user_id, property_id) VALUES (?, ?)");
        $stmt->execute([$user['id'], $property_id]);
        
        http_response_code(201);
        echo json_encode(["message" => "Property saved successfully"]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error saving property"]);
    }
} elseif ($method === 'DELETE') {
    $property_id = $_GET['property_id'] ?? null;

    if (!$property_id) {
        http_response_code(400);
        echo json_encode(["message" => "Property ID required"]);
        exit();
    }

    try {
        $stmt = $conn->prepare("DELETE FROM saved_properties WHERE user_id = ? AND property_id = ?");
        $stmt->execute([$user['id'], $property_id]);
        echo json_encode(["message" => "Property removed from saved list"]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error removing favorite"]);
    }
} else {
    http_response_code(405);
}
?>