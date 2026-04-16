<?php
// auth.php - Helper functions for authentication
require_once 'db.php';

// Simple token generation (in production, use a proper JWT library for PHP)
function generateToken($id, $role) {
    $header = json_encode(['typ' => 'JWT', 'alg' => 'HS256']);
    $payload = json_encode(['id' => $id, 'role' => $role, 'exp' => time() + (30 * 24 * 60 * 60)]);
    
    $base64UrlHeader = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($header));
    $base64UrlPayload = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($payload));
    
    $signature = hash_hmac('sha256', $base64UrlHeader . "." . $base64UrlPayload, 'supersecretkey_houserentafrica', true);
    $base64UrlSignature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));
    
    return $base64UrlHeader . "." . $base64UrlPayload . "." . $base64UrlSignature;
}

function verifyToken() {
    $headers = apache_request_headers();
    if (!isset($headers['Authorization'])) {
        // Some servers like Nginx or older PHP don't pass Authorization header in apache_request_headers
        if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
            $headers['Authorization'] = $_SERVER['HTTP_AUTHORIZATION'];
        } else {
            return null;
        }
    }

    $authHeader = $headers['Authorization'];
    $token = str_replace('Bearer ', '', $authHeader);

    $tokenParts = explode('.', $token);
    if (count($tokenParts) != 3) {
        return null;
    }

    $payload = json_decode(base64_decode($tokenParts[1]), true);
    if ($payload['exp'] < time()) {
        return null;
    }

    return $payload; // Returns array with 'id' and 'role'
}

function authorize($allowedRoles) {
    $user = verifyToken();
    if (!$user) {
        http_response_code(401);
        echo json_encode(["message" => "Not authorized, invalid or missing token"]);
        exit();
    }
    if (!in_array($user['role'], $allowedRoles)) {
        http_response_code(403);
        echo json_encode(["message" => "User role not authorized"]);
        exit();
    }
    return $user;
}
?>