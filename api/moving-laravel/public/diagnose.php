<?php
/**
 * Temporary deploy check. Open in browser, then DELETE this file.
 * https://houseforrent.site/api/moving-laravel/public/diagnose.php
 */
header('Content-Type: text/plain; charset=utf-8');
header('X-Robots-Tag: noindex');

echo "HouseRent Moving Laravel diagnose\n";
echo str_repeat('=', 40)."\n";
echo 'PHP: '.PHP_VERSION."\n";
echo 'SAPI: '.PHP_SAPI."\n\n";

$root = dirname(__DIR__);

try {
    require $root.'/vendor/autoload.php';
    $app = require $root.'/bootstrap/app.php';
    $kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
    $kernel->bootstrap();

    $driver = Illuminate\Support\Facades\DB::connection()->getDriverName();
    echo "[OK] Laravel booted (DB driver: $driver)\n";

    Illuminate\Support\Facades\DB::select('SELECT 1 FROM users LIMIT 1');
    Illuminate\Support\Facades\DB::select('SELECT 1 FROM moving_bookings LIMIT 1');
    echo "[OK] users + moving_bookings tables found\n";

    echo "\n--- Firestore ---\n";
    $fs = App\Support\MovingFirestoreSync::diagnostics();
    echo ($fs['credentials_found'] ? '[OK] ' : '[FAIL] ').'firebase JSON: '.($fs['credentials'] ?? 'not found')."\n";
    if (! empty($fs['project_id'])) {
        echo '[OK] project_id: '.$fs['project_id']."\n";
    }
    echo '[INFO] write method: '.$fs['write_method']."\n";

    $test = App\Support\MovingFirestoreSync::testWrite();
    echo ($test['ok'] ? '[OK] ' : '[FAIL] ').$test['message']."\n";
    if ($test['ok']) {
        echo "Check Firebase Console → Firestore → moving_bookings → document 0\n";
    }

    echo "\nHealth: https://houseforrent.site/api/moving-laravel/public/api/health\n";
} catch (Throwable $e) {
    echo '[FAIL] '.$e->getMessage()."\n";
}

echo "\nDone. DELETE public/diagnose.php when finished.\n";
