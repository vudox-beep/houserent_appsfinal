<?php
/**
 * Listings GET cache. Same JSON payload as a live query.
 * Cache hits skip MySQL. Mutations must call listings_cache_clear().
 */

function listings_cache_ttl() {
    return 120;
}

function listings_cache_dir() {
    $candidates = [
        __DIR__ . '/listing_cache',
        sys_get_temp_dir() . '/hr_listing_cache',
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

function listings_cache_key($queryString) {
    return md5($queryString === '' ? 'all' : $queryString);
}

function listings_cache_file($queryString) {
    return rtrim(listings_cache_dir(), '/\\') . '/listings_' . listings_cache_key($queryString) . '.json';
}

function listings_cache_apcu_key($queryString) {
    return 'hr_listings_' . listings_cache_key($queryString);
}

function listings_cache_get($queryString) {
    if (function_exists('apcu_fetch')) {
        $ok = false;
        $wrap = apcu_fetch(listings_cache_apcu_key($queryString), $ok);
        if ($ok && is_array($wrap) && !empty($wrap['json']) && !empty($wrap['etag'])) {
            $expires = (int) ($wrap['expires'] ?? 0);
            if ($expires <= 0 || $expires >= time()) {
                return $wrap;
            }
        }
    }

    $file = listings_cache_file($queryString);
    if (!is_file($file) || !is_readable($file)) {
        return null;
    }

    $raw = @file_get_contents($file);
    if ($raw === false || $raw === '') {
        return null;
    }

    $wrap = json_decode($raw, true);
    if (is_array($wrap) && !empty($wrap['json']) && !empty($wrap['etag'])) {
        $expires = (int) ($wrap['expires'] ?? 0);
        if ($expires > 0 && $expires < time()) {
            return null;
        }
        return $wrap;
    }

    // Legacy raw JSON file from the previous cache format.
    return [
        'etag' => '"' . md5($raw) . '"',
        'expires' => filemtime($file) + listings_cache_ttl(),
        'json' => $raw,
    ];
}

function listings_cache_put($queryString, $payloadJson) {
    $wrap = [
        'etag' => '"' . md5($payloadJson) . '"',
        'expires' => time() + listings_cache_ttl(),
        'json' => $payloadJson,
    ];

    @file_put_contents(listings_cache_file($queryString), json_encode($wrap), LOCK_EX);

    if (function_exists('apcu_store')) {
        @apcu_store(listings_cache_apcu_key($queryString), $wrap, listings_cache_ttl());
    }

    return $wrap;
}

function listings_cache_clear() {
    $dirs = [
        listings_cache_dir(),
        __DIR__ . '/listing_cache',
        sys_get_temp_dir() . '/hr_listing_cache',
    ];
    $seen = [];
    foreach ($dirs as $dir) {
        $dir = rtrim(str_replace('\\', '/', $dir), '/');
        if ($dir === '' || isset($seen[$dir]) || !is_dir($dir)) {
            continue;
        }
        $seen[$dir] = true;
        foreach (glob($dir . '/listings_*.json') ?: [] as $file) {
            @unlink($file);
        }
    }

    if (function_exists('apcu_cache_info') && function_exists('apcu_delete')) {
        $info = @apcu_cache_info(false);
        if (is_array($info) && !empty($info['cache_list'])) {
            foreach ($info['cache_list'] as $entry) {
                $key = $entry['info'] ?? '';
                if (is_string($key) && strpos($key, 'hr_listings_') === 0) {
                    @apcu_delete($key);
                }
            }
        }
    }
}

function listings_cache_send($wrap, $hit = false) {
    $ttl = (int) ($wrap['expires'] ?? 0) - time();
    if ($ttl < 1) {
        $ttl = listings_cache_ttl();
    }

    header('Content-Type: application/json; charset=UTF-8');
    header('Cache-Control: public, max-age=' . $ttl . ', s-maxage=' . $ttl . ', stale-while-revalidate=60');
    header('ETag: ' . $wrap['etag']);
    header('Vary: Accept-Encoding');
    header('X-Listings-Cache: ' . ($hit ? 'HIT' : 'MISS'));

    $ifNone = trim((string) ($_SERVER['HTTP_IF_NONE_MATCH'] ?? ''));
    if ($ifNone !== '' && $ifNone === $wrap['etag']) {
        http_response_code(304);
        exit;
    }

    echo $wrap['json'];
}

function send_listings_cache_headers($hit = false) {
    $ttl = listings_cache_ttl();
    header('Cache-Control: public, max-age=' . $ttl . ', s-maxage=' . $ttl . ', stale-while-revalidate=60');
    header('Vary: Accept-Encoding');
    header('X-Listings-Cache: ' . ($hit ? 'HIT' : 'MISS'));
}
