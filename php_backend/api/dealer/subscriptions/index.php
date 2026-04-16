<?php
require_once '../../cors.php';
require_once '../../db.php';
require_once '../../auth.php';

$user = authorize(['dealer', 'admin']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $conn->prepare("SELECT * FROM dealers WHERE user_id = ?");
        $stmt->execute([$user['id']]);
        
        $dealerInfo = $stmt->fetch();
        if (!$dealerInfo) {
            http_response_code(404);
            echo json_encode(["message" => "Dealer info not found"]);
            exit();
        }
        
        echo json_encode($dealerInfo);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error fetching subscription info"]);
    }
} else {
    http_response_code(405);
}
?>