<?php
// auth.php - Helper functions for authentication
require_once 'db.php';

function authSecret() {
    $secret = getenv('JWT_SECRET');
    if ($secret === false || trim($secret) === '') {
        $secret = $_SERVER['JWT_SECRET'] ?? $_ENV['JWT_SECRET'] ?? '';
    }

    if (strlen((string)$secret) < 32) {
        throw new RuntimeException('JWT_SECRET must be configured with at least 32 characters');
    }

    return (string)$secret;
}

function base64UrlEncode($value) {
    return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
}

function base64UrlDecode($value) {
    if (!is_string($value) || !preg_match('/^[A-Za-z0-9_-]+$/', $value)) {
        return false;
    }
    $padding = strlen($value) % 4;
    if ($padding > 0) {
        $value .= str_repeat('=', 4 - $padding);
    }
    return base64_decode(strtr($value, '-_', '+/'), true);
}

function generateToken($id, $role) {
    $header = json_encode(['typ' => 'JWT', 'alg' => 'HS256']);
    $now = time();
    $payload = json_encode([
        'id' => (int)$id,
        'role' => (string)$role,
        'iat' => $now,
        'exp' => $now + (24 * 60 * 60),
    ]);
    
    $base64UrlHeader = base64UrlEncode($header);
    $base64UrlPayload = base64UrlEncode($payload);
    
    $signature = hash_hmac('sha256', $base64UrlHeader . "." . $base64UrlPayload, authSecret(), true);
    $base64UrlSignature = base64UrlEncode($signature);
    
    return $base64UrlHeader . "." . $base64UrlPayload . "." . $base64UrlSignature;
}

function verifyToken() {
    global $conn;
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    foreach ($headers as $name => $value) {
        if (strcasecmp((string)$name, 'Authorization') === 0) {
            $authHeader = $value;
            break;
        }
    }

    if (!is_string($authHeader) || !preg_match('/^Bearer\s+([^\s]+)$/i', trim($authHeader), $matches)) {
        return null;
    }
    $token = $matches[1];

    $tokenParts = explode('.', $token);
    if (count($tokenParts) != 3) {
        return null;
    }

    $headerJson = base64UrlDecode($tokenParts[0]);
    $payloadJson = base64UrlDecode($tokenParts[1]);
    $header = $headerJson === false ? null : json_decode($headerJson, true);
    $payload = $payloadJson === false ? null : json_decode($payloadJson, true);
    if (!is_array($header) || ($header['alg'] ?? '') !== 'HS256' || !is_array($payload)) {
        return null;
    }
    if (!isset($payload['id'], $payload['exp']) || !is_numeric($payload['id']) || (int)$payload['exp'] < time()) {
        return null;
    }

    try {
        $expectedSignature = hash_hmac('sha256', $tokenParts[0] . "." . $tokenParts[1], authSecret(), true);
    } catch (RuntimeException $error) {
        error_log($error->getMessage());
        return null;
    }
    $base64UrlExpectedSignature = base64UrlEncode($expectedSignature);

    if (!hash_equals($base64UrlExpectedSignature, $tokenParts[2])) {
        return null;
    }

    // Never trust a role embedded in a long-lived token. Refresh authorization
    // state from the database so bans and role changes take effect immediately.
    if (!($conn instanceof PDO)) {
        return null;
    }
    $stmt = $conn->prepare('SELECT id, role, is_banned FROM users WHERE id = ? LIMIT 1');
    $stmt->execute([(int)$payload['id']]);
    $currentUser = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$currentUser || (int)($currentUser['is_banned'] ?? 0) === 1) {
        return null;
    }

    return ['id' => (int)$currentUser['id'], 'role' => (string)$currentUser['role']];
}

function authorize($allowedRoles) {
    $user = verifyToken();
    if (!$user) {
        http_response_code(401);
        echo json_encode(["message" => "Not authorized, invalid or missing token"]);
        exit();
    }
    $role = strtolower(trim((string) ($user['role'] ?? '')));
    $allowed = array_map(static function ($r) {
        return strtolower(trim((string) $r));
    }, (array) $allowedRoles);
    // Treat tenant the same as user for chat/access checks
    if ($role === 'tenant') {
        $role = 'user';
    }
    if (!in_array($role, $allowed, true)) {
        http_response_code(403);
        echo json_encode(["message" => "User role not authorized"]);
        exit();
    }
    $user['role'] = $role;
    return $user;
}
?>
