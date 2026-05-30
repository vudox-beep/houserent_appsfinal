<?php
require_once 'includes/RateLimiter.php';
$rl = new RateLimiter(5, 60);
$success = $rl->check('test_web');
$dir = sys_get_temp_dir() . '/houserent_rate_limits';
echo json_encode([
    'success' => $success,
    'dir' => $dir,
    'is_dir' => is_dir($dir),
    'is_writable' => is_writable($dir),
    'file_exists' => file_exists($dir . '/' . md5('test_web') . '.json')
]);
