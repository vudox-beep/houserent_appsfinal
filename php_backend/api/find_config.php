<?php
/**
 * Temporary path checker — open in browser, then DELETE after fixing.
 * https://houseforrent.site/php_backend/api/find_config.php
 */
header('Content-Type: application/json; charset=UTF-8');

require_once __DIR__ . '/includes/site_bootstrap.php';

$out = [
    'document_root' => $_SERVER['DOCUMENT_ROOT'] ?? null,
    'script_filename' => $_SERVER['SCRIPT_FILENAME'] ?? null,
    'includes_dir' => __DIR__ . '/includes',
    'candidates' => [],
    'found' => null,
];

foreach (hr_website_config_candidates() as $path) {
    $exists = is_file($path);
    $out['candidates'][] = [
        'path' => $path,
        'exists' => $exists,
        'readable' => $exists ? is_readable($path) : false,
    ];
}

try {
    $found = hr_find_website_config();
    $out['found'] = $found;
    $out['status'] = 'ok';
    $out['message'] = 'Website config found. You can delete this file (find_config.php).';
} catch (Throwable $e) {
    $out['status'] = 'error';
    $out['message'] = $e->getMessage();
}

echo json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
