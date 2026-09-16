<?php
/**
 * File cache for homepage banner API responses.
 */

function hr_banner_cache_ttl(): int
{
    return 180;
}

function hr_banner_cache_dir(): string
{
    $candidates = [
        __DIR__ . '/cache',
        sys_get_temp_dir() . '/hr_banner_cache',
    ];
    foreach ($candidates as $dir) {
        if (is_dir($dir) || @mkdir($dir, 0775, true)) {
            if (is_dir($dir) && is_writable($dir)) {
                return $dir;
            }
        }
    }
    return sys_get_temp_dir();
}

function hr_banner_cache_page_key(string $page): string
{
    $page = strtolower(trim($page));
    $page = preg_replace('/[^a-z0-9_-]/', '', $page);
    return $page !== '' ? $page : 'home';
}

function hr_banner_cache_file(string $page): string
{
    return rtrim(hr_banner_cache_dir(), '/\\') . '/banners_' . hr_banner_cache_page_key($page) . '.json';
}

function hr_banner_cache_get(string $page): ?array
{
    $file = hr_banner_cache_file($page);
    if (!is_file($file) || !is_readable($file)) {
        return null;
    }
    $raw = @file_get_contents($file);
    if ($raw === false || $raw === '') {
        return null;
    }
    $wrap = json_decode($raw, true);
    if (!is_array($wrap) || empty($wrap['json']) || empty($wrap['etag'])) {
        return null;
    }
    $expires = (int) ($wrap['expires'] ?? 0);
    if ($expires > 0 && $expires < time()) {
        return null;
    }
    return $wrap;
}

function hr_banner_cache_put(string $page, array $payload): array
{
    $json = json_encode($payload);
    if ($json === false) {
        $json = '{"status":"success","data":[]}';
    }
    $wrap = [
        'etag' => '"' . md5($json) . '"',
        'expires' => time() + hr_banner_cache_ttl(),
        'json' => $json,
    ];
    @file_put_contents(hr_banner_cache_file($page), json_encode($wrap), LOCK_EX);
    return $wrap;
}

function hr_banner_cache_clear(): void
{
    $dirs = [
        hr_banner_cache_dir(),
        __DIR__ . '/cache',
        sys_get_temp_dir() . '/hr_banner_cache',
    ];
    $seen = [];
    foreach ($dirs as $dir) {
        $dir = rtrim(str_replace('\\', '/', $dir), '/');
        if ($dir === '' || isset($seen[$dir]) || !is_dir($dir)) {
            continue;
        }
        $seen[$dir] = true;
        foreach (glob($dir . '/banners_*.json') ?: [] as $file) {
            @unlink($file);
        }
    }
}

function hr_banner_cache_send(array $wrap, bool $hit): void
{
    $ttl = (int) ($wrap['expires'] ?? 0) - time();
    if ($ttl < 1) {
        $ttl = hr_banner_cache_ttl();
    }
    header('Content-Type: application/json; charset=UTF-8');
    header('Cache-Control: public, max-age=' . $ttl . ', s-maxage=' . $ttl . ', stale-while-revalidate=60');
    header('ETag: ' . $wrap['etag']);
    header('Vary: Accept-Encoding');
    header('X-Banner-Cache: ' . ($hit ? 'HIT' : 'MISS'));

    $ifNone = trim((string) ($_SERVER['HTTP_IF_NONE_MATCH'] ?? ''));
    if ($ifNone !== '' && $ifNone === $wrap['etag']) {
        http_response_code(304);
        exit;
    }

    echo $wrap['json'];
}
