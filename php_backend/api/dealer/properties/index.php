<?php
// --- Rate Limiting Start ---
$limiterPath = __DIR__ . '/../../includes/RateLimiter.php';
if (file_exists($limiterPath)) {
    require_once $limiterPath;
    $limiter = new RateLimiter(30, 60); // 30 requests per 60 seconds
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    if (!$limiter->check($ip . '_dealer_properties')) {
        http_response_code(429);
        echo json_encode([
            'status' => 'error', 
            'message' => 'Too many requests. Please try again later.'
        ]);
        exit();
    }
}
// --- Rate Limiting End ---
?>