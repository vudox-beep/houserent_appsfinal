<?php
require_once '../cors.php';
require_once '../db.php';

$bannerCache = __DIR__ . '/../../../api/banner_cache.php';
if (is_file($bannerCache)) {
    require_once $bannerCache;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

function hr_public_banner_base(): string
{
    $host = $_SERVER['HTTP_HOST'] ?? 'houseforrent.site';
    return 'https://' . preg_replace('/:\d+$/', '', $host);
}

function hr_public_banner_url(string $path): string
{
    $path = trim(str_replace('\\', '/', $path));
    if ($path === '') {
        return '';
    }
    if (preg_match('#^https?://#i', $path)) {
        return $path;
    }
    return hr_public_banner_base() . '/' . ltrim($path, '/');
}

try {
    $page = strtolower(trim((string) ($_GET['page'] ?? 'home')));
    if ($page === '') {
        $page = 'home';
    }
    $skipCache = isset($_GET['nocache']) && (string) $_GET['nocache'] === '1';
    $canCache = function_exists('hr_banner_cache_get');

    if ($canCache && !$skipCache) {
        $cached = hr_banner_cache_get($page);
        if (is_array($cached)) {
            hr_banner_cache_send($cached, true);
            exit;
        }
    }

    $stmt = $conn->prepare(
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
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $image = hr_public_banner_url((string) ($row['image_path'] ?? ''));
        if ($image === '') {
            continue;
        }
        $title = trim((string) ($row['title'] ?? ''));
        $subtitle = trim((string) ($row['subtitle'] ?? ''));
        $link = trim((string) ($row['link_url'] ?? ''));
        if ($link !== '' && $link[0] === '/') {
            $link = hr_public_banner_base() . $link;
        }
        $data[] = [
            'id' => (int) ($row['id'] ?? 0),
            'title' => $title,
            'subtitle' => $subtitle,
            'image' => $image,
            'image_url' => $image,
            'link' => $link,
            'text' => $title !== '' ? $title : $subtitle,
        ];
    }

    $payload = ['status' => 'success', 'data' => $data];
    if ($canCache) {
        hr_banner_cache_send(hr_banner_cache_put($page, $payload), false);
        exit;
    }
    echo json_encode($payload);
} catch (Throwable $e) {
    header('Cache-Control: no-store');
    echo json_encode(['status' => 'success', 'data' => []]);
}
