<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Mirrors moving_bookings rows to Firestore for realtime Flutter listeners.
 * Uses Firebase service-account JSON (same file as FCM push).
 * Writes via Firestore REST API so cPanel works without gRPC / cloud-firestore.
 */
class MovingFirestoreSync
{
    private const COLLECTION = 'moving_bookings';

    public static function diagnostics(): array
    {
        $creds = self::credentialsPath();
        $checks = [
            'credentials' => $creds,
            'credentials_found' => $creds !== null,
            'project_id' => null,
            'sdk_available' => false,
            'write_method' => 'rest',
        ];

        if ($creds !== null) {
            $json = json_decode((string) file_get_contents($creds), true);
            $checks['project_id'] = is_array($json) ? ($json['project_id'] ?? null) : null;
        }

        $autoload = self::autoloadPath();
        if ($autoload) {
            require_once $autoload;
            $checks['sdk_available'] = class_exists('Google\\Cloud\\Firestore\\FirestoreClient');
            if ($checks['sdk_available']) {
                $checks['write_method'] = 'sdk';
            }
        }

        return $checks;
    }

    public static function syncBookingId(int $bookingId): void
    {
        if ($bookingId <= 0 || self::credentialsPath() === null) {
            return;
        }

        try {
            $row = DB::selectOne(
                'SELECT b.*,
                        d.current_latitude AS driver_latitude,
                        d.current_longitude AS driver_longitude
                   FROM moving_bookings b
                   LEFT JOIN drivers d ON d.user_id = b.driver_id
                  WHERE b.id = ?',
                [$bookingId],
            );
            if (! $row) {
                return;
            }
            self::syncRow($row);
        } catch (\Throwable $e) {
            Log::warning('Firestore sync failed (booking '.$bookingId.'): '.$e->getMessage());
        }
    }

    public static function syncDriverActiveBookings(int $driverUserId): void
    {
        if ($driverUserId <= 0 || self::credentialsPath() === null) {
            return;
        }

        try {
            $rows = DB::select(
                "SELECT id FROM moving_bookings
                  WHERE driver_id = ?
                    AND status IN ('accepted', 'in_progress', 'arrived')",
                [$driverUserId],
            );
            foreach ($rows as $row) {
                self::syncBookingId((int) $row->id);
            }
        } catch (\Throwable $e) {
            Log::warning('Firestore driver sync failed: '.$e->getMessage());
        }
    }

    /** Test write — used by diagnose.php. */
    public static function testWrite(): array
    {
        $creds = self::credentialsPath();
        if ($creds === null) {
            return ['ok' => false, 'message' => 'firebase-service-account.json not found'];
        }

        $payload = [
            'id' => 0,
            'status' => 'test',
            'tenant_id' => '0',
            'driver_id' => '',
            'pickup_address' => 'Firestore connectivity test',
            'pickup_lat' => 0.0,
            'pickup_lng' => 0.0,
            'dropoff_address' => 'HouseRent Africa',
            'dropoff_lat' => 0.0,
            'dropoff_lng' => 0.0,
            'moving_date' => now()->toDateString(),
            'updated_at' => now()->toIso8601String(),
        ];

        try {
            self::writeDocument($creds, '0', $payload);

            return ['ok' => true, 'message' => 'Wrote moving_bookings/0 — check Firebase Console'];
        } catch (\Throwable $e) {
            return ['ok' => false, 'message' => $e->getMessage()];
        }
    }

    private static function syncRow(object $row): void
    {
        $creds = self::credentialsPath();
        if (! $creds) {
            return;
        }

        $payload = [
            'id' => (int) $row->id,
            'status' => (string) ($row->status ?? 'open'),
            'tenant_id' => (string) $row->tenant_id,
            'driver_id' => $row->driver_id ? (string) $row->driver_id : '',
            'pickup_address' => (string) ($row->pickup_location ?? ''),
            'pickup_lat' => (float) ($row->pickup_latitude ?? 0),
            'pickup_lng' => (float) ($row->pickup_longitude ?? 0),
            'dropoff_address' => (string) ($row->dropoff_location ?? ''),
            'dropoff_lat' => (float) ($row->dropoff_latitude ?? 0),
            'dropoff_lng' => (float) ($row->dropoff_longitude ?? 0),
            'moving_date' => (string) ($row->moving_date ?? ''),
            'updated_at' => now()->toIso8601String(),
        ];

        if ($row->agreed_amount !== null) {
            $payload['agreed_amount'] = (float) $row->agreed_amount;
        }
        if (isset($row->tenant_offer) && $row->tenant_offer !== null) {
            $payload['tenant_offer'] = (float) $row->tenant_offer;
        }
        if ($row->driver_latitude !== null && $row->driver_longitude !== null) {
            $payload['driver_lat'] = (float) $row->driver_latitude;
            $payload['driver_lng'] = (float) $row->driver_longitude;
        }

        self::writeDocument($creds, (string) $row->id, $payload);
    }

    /** @param array<string, mixed> $payload */
    private static function writeDocument(string $credsPath, string $docId, array $payload): void
    {
        if (self::canUseSdk()) {
            self::writeViaSdk($credsPath, $docId, $payload);

            return;
        }

        self::writeViaRest($credsPath, $docId, $payload);
    }

    private static function canUseSdk(): bool
    {
        $autoload = self::autoloadPath();
        if (! $autoload) {
            return false;
        }
        require_once $autoload;

        return class_exists('Google\\Cloud\\Firestore\\FirestoreClient');
    }

    /** @param array<string, mixed> $payload */
    private static function writeViaSdk(string $credsPath, string $docId, array $payload): void
    {
        $factoryClass = 'Kreait\\Firebase\\Factory';
        $firestore = (new $factoryClass())
            ->withServiceAccount($credsPath)
            ->createFirestore();

        $firestore->database()
            ->collection(self::COLLECTION)
            ->document($docId)
            ->set($payload, ['merge' => true]);
    }

    /** @param array<string, mixed> $payload */
    private static function writeViaRest(string $credsPath, string $docId, array $payload): void
    {
        $serviceAccount = json_decode((string) file_get_contents($credsPath), true);
        if (! is_array($serviceAccount) || empty($serviceAccount['project_id'])) {
            throw new \RuntimeException('Invalid firebase service-account JSON');
        }

        $projectId = (string) $serviceAccount['project_id'];
        $token = self::fetchAccessToken($serviceAccount);
        $fields = self::toFirestoreFields($payload);

        $mask = [];
        foreach (array_keys($fields) as $key) {
            $mask[] = 'updateMask.fieldPaths='.rawurlencode($key);
        }

        $url = 'https://firestore.googleapis.com/v1/projects/'
            .rawurlencode($projectId)
            .'/databases/(default)/documents/'
            .self::COLLECTION.'/'.rawurlencode($docId);
        if ($mask !== []) {
            $url .= '?'.implode('&', $mask);
        }

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => 'PATCH',
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 20,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer '.$token,
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => json_encode(['fields' => $fields]),
        ]);
        $response = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);

        if ($response === false) {
            throw new \RuntimeException('Firestore REST cURL error: '.$error);
        }

        if ($status < 200 || $status >= 300) {
            throw new \RuntimeException(
                'Firestore REST HTTP '.$status.': '.substr((string) $response, 0, 400)
            );
        }
    }

    /** @param array<string, mixed> $serviceAccount */
    private static function fetchAccessToken(array $serviceAccount): string
    {
        $email = (string) ($serviceAccount['client_email'] ?? '');
        $privateKey = (string) ($serviceAccount['private_key'] ?? '');
        if ($email === '' || $privateKey === '') {
            throw new \RuntimeException('Service account missing client_email or private_key');
        }

        $now = time();
        $header = self::base64UrlEncode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
        $claim = self::base64UrlEncode(json_encode([
            'iss' => $email,
            'sub' => $email,
            'aud' => 'https://oauth2.googleapis.com/token',
            'iat' => $now,
            'exp' => $now + 3600,
            'scope' => 'https://www.googleapis.com/auth/datastore',
        ]));
        $unsigned = $header.'.'.$claim;

        $signature = '';
        $ok = openssl_sign($unsigned, $signature, $privateKey, OPENSSL_ALGORITHM_SHA256);
        if (! $ok) {
            throw new \RuntimeException('Could not sign Firestore JWT');
        }

        $jwt = $unsigned.'.'.self::base64UrlEncode($signature);

        $ch = curl_init('https://oauth2.googleapis.com/token');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 15,
            CURLOPT_POSTFIELDS => http_build_query([
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ]),
        ]);
        $response = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $decoded = json_decode((string) $response, true);
        if ($status < 200 || $status >= 300 || empty($decoded['access_token'])) {
            throw new \RuntimeException(
                'OAuth token failed (HTTP '.$status.'): '.substr((string) $response, 0, 300)
            );
        }

        return (string) $decoded['access_token'];
    }

    /** @param array<string, mixed> $payload */
    private static function toFirestoreFields(array $payload): array
    {
        $fields = [];
        foreach ($payload as $key => $value) {
            $fields[$key] = self::toFirestoreValue($value);
        }

        return $fields;
    }

    private static function toFirestoreValue(mixed $value): array
    {
        if (is_bool($value)) {
            return ['booleanValue' => $value];
        }
        if (is_int($value)) {
            return ['integerValue' => (string) $value];
        }
        if (is_float($value)) {
            return ['doubleValue' => $value];
        }

        return ['stringValue' => (string) $value];
    }

    private static function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    private static function credentialsPath(): ?string
    {
        $configured = config('moving.firebase_credentials');
        if (is_string($configured) && $configured !== '' && is_file($configured)) {
            return $configured;
        }

        $fromEnv = getenv('FIREBASE_CREDENTIALS') ?: '';
        if ($fromEnv !== '' && is_file($fromEnv)) {
            return $fromEnv;
        }

        $candidates = array_filter([
            dirname(base_path(), 2).'/config/firebase-service-account.json',
            dirname(base_path(), 3).'/config/firebase-service-account.json',
            dirname(base_path(), 2).'/php_backend/config/firebase-service-account.json',
            dirname(base_path(), 3).'/php_backend/config/firebase-service-account.json',
            dirname(base_path(), 2).'/house/config/firebase-service-account.json',
            dirname(base_path(), 3).'/house/config/firebase-service-account.json',
            dirname(base_path(), 2).'/php_backend/firebase-service-account.json',
            dirname(base_path(), 3).'/php_backend/firebase-service-account.json',
            base_path('../../config/firebase-service-account.json'),
            base_path('../../php_backend/config/firebase-service-account.json'),
            base_path('../../house/config/firebase-service-account.json'),
        ]);

        foreach ($candidates as $path) {
            $real = realpath($path) ?: $path;
            if (is_file($real)) {
                return $real;
            }
        }

        return null;
    }

    private static function autoloadPath(): ?string
    {
        foreach ([
            dirname(base_path(), 2).'/php_backend/vendor/autoload.php',
            dirname(base_path(), 3).'/php_backend/vendor/autoload.php',
            base_path('../../php_backend/vendor/autoload.php'),
        ] as $path) {
            $real = realpath($path) ?: $path;
            if (is_file($real)) {
                return $real;
            }
        }

        return null;
    }
}
