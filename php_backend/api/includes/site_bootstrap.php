<?php

function hr_json_error(string $message, int $code = 500, ?string $detail = null): void
{
    if (ob_get_length()) {
        @ob_clean();
    }
    http_response_code($code);
    $payload = ['status' => 'error', 'message' => $message];
    if ($detail !== null && $detail !== '') {
        $payload['error'] = $detail;
    }
    echo json_encode($payload);
    exit;
}

function hr_json_success(string $message, array $extra = []): void
{
    if (ob_get_length()) {
        @ob_clean();
    }
    http_response_code(200);
    echo json_encode(array_merge(['status' => 'success', 'message' => $message], $extra));
    exit;
}

function hr_normalize_path(string $path): string
{
    return rtrim(str_replace('\\', '/', $path), '/');
}

/**
 * Collect every likely website config/config.php location.
 */
function hr_website_config_candidates(): array
{
    $candidates = [];

    // Optional manual override (create this file on the server if auto-detect fails)
    $overrideFile = __DIR__ . '/website_config_path.php';
    if (is_file($overrideFile)) {
        $override = include $overrideFile;
        if (is_string($override) && $override !== '') {
            $candidates[] = $override;
        }
    }

    $starts = [];

    if (!empty($_SERVER['SCRIPT_FILENAME'])) {
        $starts[] = dirname(hr_normalize_path($_SERVER['SCRIPT_FILENAME']));
    }
    $starts[] = hr_normalize_path(__DIR__); // .../php_backend/api/includes
    if (!empty($_SERVER['DOCUMENT_ROOT'])) {
        $starts[] = hr_normalize_path($_SERVER['DOCUMENT_ROOT']);
    }

    foreach ($starts as $start) {
        $dir = $start;
        for ($i = 0; $i < 8; $i++) {
            $candidates[] = $dir . '/config/config.php';
            $candidates[] = $dir . '/house/config/config.php';
            $parent = dirname($dir);
            if ($parent === $dir) {
                break;
            }
            $dir = $parent;
        }
    }

    // Explicit relatives from this file
    $includes = hr_normalize_path(__DIR__);
    $api = dirname($includes);
    $phpBackend = dirname($api);
    $webRoot = dirname($phpBackend);

    $candidates[] = $webRoot . '/config/config.php';
    $candidates[] = $webRoot . '/house/config/config.php';
    $candidates[] = $phpBackend . '/../config/config.php';
    $candidates[] = $phpBackend . '/../house/config/config.php';

    // Unique keep order
    $unique = [];
    foreach ($candidates as $path) {
        $path = hr_normalize_path($path);
        if ($path === '' || isset($unique[$path])) {
            continue;
        }
        $unique[$path] = true;
    }

    return array_keys($unique);
}

/**
 * Find website config/config.php (same file website register.php uses).
 */
function hr_find_website_config(): string
{
    $tried = [];
    foreach (hr_website_config_candidates() as $path) {
        $tried[] = $path;
        if (is_file($path) && is_readable($path)) {
            return $path;
        }
        $real = @realpath($path);
        if ($real && is_file($real) && is_readable($real)) {
            return $real;
        }
    }

    throw new RuntimeException(
        'Website config/config.php not found. Tried: ' . implode(' | ', array_slice($tried, 0, 12))
    );
}

/**
 * Load website config/config.php and open DB with its DB_* constants.
 */
function hr_api_bootstrap(): void
{
    static $loaded = false;
    if ($loaded) {
        return;
    }

    $configPath = hr_find_website_config();

    // Prevent website config from printing HTML / dying on display errors during API calls
    $prevDisplay = ini_get('display_errors');
    ini_set('display_errors', '0');

    require_once $configPath;

    ini_set('display_errors', (string) $prevDisplay);

    if (!defined('DB_HOST') || !defined('DB_USER') || !defined('DB_NAME')) {
        throw new RuntimeException(
            'Loaded config but DB constants missing: ' . $configPath
        );
    }

    if (!defined('SMTP_HOST') || !defined('SMTP_USER') || !defined('SMTP_PASS')) {
        throw new RuntimeException(
            'Loaded config but SMTP constants missing: ' . $configPath
        );
    }

    if (!defined('SITE_URL')) {
        define('SITE_URL', 'https://houseforrent.site');
    }
    if (!defined('SITE_NAME')) {
        define('SITE_NAME', 'HouseRent Africa');
    }
    if (!defined('SMTP_PORT')) {
        define('SMTP_PORT', 465);
    }

    global $conn;
    $pass = defined('DB_PASS') ? DB_PASS : '';
    $conn = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        $pass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
    $conn->exec('SET NAMES utf8mb4');

    $loaded = true;
}
