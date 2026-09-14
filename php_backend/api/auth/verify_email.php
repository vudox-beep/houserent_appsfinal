<?php
try {
    require_once __DIR__ . '/../includes/site_bootstrap.php';
    hr_api_bootstrap();
    $site = defined('SITE_URL') ? rtrim(SITE_URL, '/') : 'https://houseforrent.site';
} catch (Throwable $e) {
    $site = 'https://houseforrent.site';
}

$token = trim((string) ($_GET['token'] ?? ''));
if ($token === '') {
    header('Location: ' . $site . '/index.php');
    exit;
}

header('Location: ' . $site . '/verify_email.php?token=' . urlencode($token));
exit;
