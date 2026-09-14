<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Firebase push for HouseRent Shifts (moving bookings).
 * Uses the same firebase_push.php helper as php_backend House Hunt.
 */
class MovingPushNotifier
{
    private static ?bool $ready = null;

    private static function ensureLoaded(): bool
    {
        if (self::$ready !== null) {
            return self::$ready;
        }

        $configured = config('moving.firebase_push_path');
        $candidates = array_filter([
            is_string($configured) && $configured !== '' ? $configured : null,
            dirname(base_path(), 2).'/php_backend/api/notifications/firebase_push.php',
            dirname(base_path(), 3).'/php_backend/api/notifications/firebase_push.php',
            base_path('../../php_backend/api/notifications/firebase_push.php'),
        ]);

        foreach ($candidates as $path) {
            $real = realpath($path) ?: $path;
            if (is_file($real)) {
                require_once $real;
                self::$ready = function_exists('fetchFirebaseTokensForUserIds')
                    || function_exists('sendFirebaseNotificationEnsuringUsers')
                    || function_exists('sendFirebaseNotificationToRole');

                return self::$ready;
            }
        }

        self::$ready = false;

        return false;
    }

    private static function pdo(): \PDO
    {
        return DB::connection()->getPdo();
    }

    public static function short(?string $text, int $max = 42): string
    {
        $value = trim((string) $text);
        if ($value === '') {
            return 'location';
        }
        if (mb_strlen($value) <= $max) {
            return $value;
        }

        return mb_substr($value, 0, $max - 3).'...';
    }

    /**
     * Push only to specific user IDs (booker and/or that driver).
     * Never broadcasts to a whole role.
     *
     * @param  list<int>  $userIds
     * @param  array<string, scalar|null>  $data
     */
    public static function notifyUsers(array $userIds, string $title, string $body, array $data = []): void
    {
        $userIds = array_values(array_unique(array_filter(
            array_map('intval', $userIds),
            static fn (int $id): bool => $id > 0
        )));
        if ($userIds === []) {
            return;
        }

        if (! self::ensureLoaded()) {
            return;
        }

        try {
            $payload = self::payload($data);
            if (function_exists('fetchFirebaseTokensForUserIds')) {
                self::sendToTokens(
                    fetchFirebaseTokensForUserIds(self::pdo(), $userIds),
                    $title,
                    $body,
                    $payload,
                );

                return;
            }

            // Older helper only — still avoid role broadcast by using a non-role.
            if (function_exists('sendFirebaseNotificationEnsuringUsers')) {
                sendFirebaseNotificationEnsuringUsers(
                    self::pdo(),
                    '__moving_only__',
                    $userIds,
                    $title,
                    $body,
                    $payload,
                );
            }
        } catch (\Throwable $e) {
            Log::warning('Moving shift FCM (users) failed: '.$e->getMessage());
        }
    }

    /**
     * @param  list<string>  $tokens
     * @param  array<string, scalar|null>  $data
     */
    private static function sendToTokens(array $tokens, string $title, string $body, array $data): void
    {
        if ($tokens === []) {
            return;
        }

        $messaging = loadFirebaseMessaging();
        $cloudMessageClass = 'Kreait\\Firebase\\Messaging\\CloudMessage';
        $notificationClass = 'Kreait\\Firebase\\Messaging\\Notification';
        if (! class_exists($cloudMessageClass) || ! class_exists($notificationClass)) {
            return;
        }

        $stringData = function_exists('stringifyFirebaseData')
            ? stringifyFirebaseData($data)
            : array_map('strval', $data);

        foreach ($tokens as $token) {
            $token = trim((string) $token);
            if ($token === '') {
                continue;
            }
            try {
                $message = call_user_func([$cloudMessageClass, 'withTarget'], 'token', $token)
                    ->withNotification(call_user_func([$notificationClass, 'create'], $title, $body))
                    ->withData($stringData);
                $messaging->send($message);
            } catch (\Throwable $e) {
                Log::warning('Moving shift FCM token failed: '.$e->getMessage());
            }
        }
    }

    /**
     * @param  array<string, scalar|null>  $data
     * @return array<string, string>
     */
    private static function payload(array $data): array
    {
        $base = [
            'type' => 'moving',
            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
        ];

        $merged = array_merge($base, $data);
        $out = [];
        foreach ($merged as $key => $value) {
            if ($value === null) {
                continue;
            }
            $out[(string) $key] = (string) $value;
        }

        return $out;
    }
}
