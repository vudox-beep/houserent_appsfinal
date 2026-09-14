<?php

use App\Http\Controllers\BookingController;
use App\Http\Controllers\DriverController;
use App\Http\Controllers\MapsController;
use App\Http\Middleware\CheckMovingApiKey;
use App\Http\Middleware\EnsureMovingUser;
use App\Support\MovingHelpers;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    $dbOk = false;
    $dbError = null;
    $driver = null;
    $tablesOk = false;
    try {
        $driver = DB::connection()->getDriverName();
        DB::select('SELECT 1');
        DB::select('SELECT 1 FROM users LIMIT 1');
        DB::select('SELECT 1 FROM moving_bookings LIMIT 1');
        $dbOk = true;
        $tablesOk = true;
    } catch (\Throwable $e) {
        $dbError = $e->getMessage();
        if ($driver === null) {
            try {
                $driver = DB::connection()->getDriverName();
            } catch (\Throwable) {
                $driver = 'unknown';
            }
        }
    }

    $healthy = $dbOk && $tablesOk && $driver !== 'sqlite';

    return MovingHelpers::ok('Moving marketplace API is online.', [
        'realtime' => false,
        'engine' => 'laravel',
        'database' => $healthy ? 'ok' : 'error',
        'database_driver' => $driver,
        'tables' => $tablesOk ? 'ok' : 'missing',
        'database_error' => $healthy ? null : ($dbError ?? 'Check DB_CONNECTION=mysql in .env'),
        'firestore' => \App\Support\MovingFirestoreSync::diagnostics(),
    ], $healthy ? 200 : 503);
});

// Google Maps proxy — open like the old maps.php (no user session required).
Route::match(['GET', 'POST'], '/v1/maps', [MapsController::class, 'handle']);

Route::prefix('v1')
    ->middleware([CheckMovingApiKey::class, EnsureMovingUser::class])
    ->group(function () {
        Route::post('/bookings', [BookingController::class, 'store']);
        Route::get('/bookings', [BookingController::class, 'index']);
        Route::get('/bookings/{bookingId}', [BookingController::class, 'show'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/view', [BookingController::class, 'markViewed'])
            ->whereNumber('bookingId');
        Route::get('/bookings/{bookingId}/views', [BookingController::class, 'listViews'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/unlock', [BookingController::class, 'unlock'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/cancel', [BookingController::class, 'cancel'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/offers', [BookingController::class, 'storeOffer'])
            ->whereNumber('bookingId');
        Route::get('/bookings/{bookingId}/offers', [BookingController::class, 'listOffers'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/offers/{offerId}/accept', [BookingController::class, 'acceptOffer'])
            ->whereNumber('bookingId')
            ->whereNumber('offerId');
        Route::post('/bookings/{bookingId}/offers/{offerId}/reject', [BookingController::class, 'rejectOffer'])
            ->whereNumber('bookingId')
            ->whereNumber('offerId');
        Route::post('/bookings/{bookingId}/messages', [BookingController::class, 'storeMessage'])
            ->whereNumber('bookingId');
        Route::get('/bookings/{bookingId}/messages', [BookingController::class, 'listMessages'])
            ->whereNumber('bookingId');
        // Start ride (accepted → in_progress). Alias kept for hosts that
        // filter the bare path segment "start".
        Route::post('/bookings/{bookingId}/start', [BookingController::class, 'start'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/start-ride', [BookingController::class, 'start'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/arrived', [BookingController::class, 'arrived'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/complete', [BookingController::class, 'complete'])
            ->whereNumber('bookingId');
        Route::post('/bookings/{bookingId}/rating', [BookingController::class, 'rate'])
            ->whereNumber('bookingId');

        Route::get('/drivers/nearby', [DriverController::class, 'nearby']);
        Route::get('/drivers/me', [DriverController::class, 'me']);
        Route::post('/drivers/me/identity', [DriverController::class, 'uploadIdentity']);
        // Alias in case "identity" path is missing/cached on the host.
        Route::post('/drivers/me/upload-docs', [DriverController::class, 'uploadIdentity']);
        Route::post('/drivers/me/photo', [DriverController::class, 'uploadProfilePhoto']);
        Route::patch('/drivers/me/location', [DriverController::class, 'updateLocation']);
        Route::patch('/drivers/me/availability', [DriverController::class, 'updateAvailability']);
        Route::match(['PATCH', 'POST'], '/drivers/me/profile', [DriverController::class, 'updateProfile']);
    });
