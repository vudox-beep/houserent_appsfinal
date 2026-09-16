<?php
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

require_once __DIR__ . '/banner_cache.php';

$configCandidates = [
    __DIR__ . '/../config/config.php',
    __DIR__ . '/../house/config/config.php',
    '/home/atphieleqa/houseforrent.site/config/config.php',
];
foreach ($configCandidates as $cfg) {
    if (is_file($cfg)) {
        require_once $cfg;
        break;
    }
}

function hr_banner_site_base(): string
{
    if (defined('SITE_URL') && SITE_URL) {
        return rtrim((string) SITE_URL, '/');
    }
    $host = $_SERVER['HTTP_HOST'] ?? 'houseforrent.site';
    return 'https://' . $host;
}

function hr_banner_public_url(string $path): string
{
    $path = trim(str_replace('\\', '/', $path));
    if ($path === '') {
        return '';
    }
    if (preg_match('#^https?://#i', $path)) {
        return $path;
    }
    return hr_banner_site_base() . '/' . ltrim($path, '/');
}

function hr_banner_link_url(string $link): string
{
    $link = trim($link);
    if ($link === '') {
        return '';
    }
    if (preg_match('#^https?://#i', $link)) {
        return $link;
    }
    if (isset($link[0]) && $link[0] === '/') {
        return hr_banner_site_base() . $link;
    }
    return $link;
}

$emptyPayload = ['status' => 'success', 'data' => []];
$skipCache = isset($_GET['nocache']) && (string) $_GET['nocache'] === '1';
$page = strtolower(trim((string) ($_GET['page'] ?? 'home')));
if ($page === '') {
    $page = 'home';
}

if (!$skipCache) {
    $cached = hr_banner_cache_get($page);
    if (is_array($cached)) {
        hr_banner_cache_send($cached, true);
        exit;
    }
}

if (!defined('DB_HOST') || !defined('DB_NAME') || !defined('DB_USER')) {
    hr_banner_cache_send(hr_banner_cache_put($page, $emptyPayload), false);
    exit;
}

try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        defined('DB_PASS') ? DB_PASS : '',
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );

    $stmt = $pdo->prepare(
        "SELECT id, title, subtitle, image_path, link_url
         FROM banner_adverts
         WHERE LOWER(TRIM(page)) = :page
           AND is_active = 1
           AND (starts_at IS NULL OR starts_at <= NOW())
           AND (ends_at IS NULL OR ends_at >= NOW())
         ORDER BY sort_order ASC, id DESC
         LIMIT 10"
    );
    $stmt->execute([':page' => $page]);

    $data = [];
    foreach ($stmt->fetchAll() as $row) {
        $image = hr_banner_public_url((string) ($row['image_path'] ?? ''));
        if ($image === '') {
            continue;
        }
        $title = trim((string) ($row['title'] ?? ''));
        $subtitle = trim((string) ($row['subtitle'] ?? ''));
        $text = $title !== '' ? $title : $subtitle;
        $data[] = [
            'id' => (int) ($row['id'] ?? 0),
            'title' => $title,
            'subtitle' => $subtitle,
            'image' => $image,
            'image_url' => $image,
            'link' => hr_banner_link_url((string) ($row['link_url'] ?? '')),
            'text' => $text,
        ];
    }

    hr_banner_cache_send(hr_banner_cache_put($page, ['status' => 'success', 'data' => $data]), false);
} catch (Throwable $e) {
    header('Cache-Control: no-store');
    echo json_encode($emptyPayload);
}
