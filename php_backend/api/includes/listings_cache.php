<?php
/**
 * Short-lived listings GET response cache (high-traffic protection).
 * Used only by properties/index.php fetch — does not change uploads.
 */

function listings_cache_dir() {
    $dir = __DIR__ . '/listing_cache';
    if (!is_dir($dir)) {
        @mkdir($dir, 0777, true);
    }
    return $dir;
}

function listings_cache_file($queryString) {
    return listings_cache_dir() . '/listings_' . md5($queryString === '' ? 'all' : $queryString) . '.json';
}

function send_listings_cache_headers($hit = false) {
    header('Cache-Control: public, max-age=60, s-maxage=60, stale-while-revalidate=30');
    header('Vary: Accept-Encoding');
    header('X-Listings-Cache: ' . ($hit ? 'HIT' : 'MISS'));
}
