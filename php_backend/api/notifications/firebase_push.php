<?php

/**
 * Sends a notification to every registered Flutter device for a role.
 *
 * Before using this helper, set FIREBASE_CREDENTIALS on the server to the
 * absolute path of the Firebase service-account JSON file.
 */
if (!function_exists('normalizeFirebaseNotificationRole')) {
    function normalizeFirebaseNotificationRole(string $targetRole): array {
        $role = strtolower(trim($targetRole));
        if ($role === 'all' || $role === '') {
            return [];
        }

        if (in_array($role, ['user', 'tenant'], true)) {
            return ['user', 'tenant'];
        }

        if (in_array($role, ['dealer', 'landlord'], true)) {
            return ['dealer', 'landlord'];
        }

        return [$role];
    }
}

if (!function_exists('stringifyFirebaseData')) {
    function stringifyFirebaseData(array $data): array {
        $stringData = [];
        foreach ($data as $key => $value) {
            if ($value === null) {
                continue;
            }

            if (is_bool($value)) {
                $value = $value ? '1' : '0';
            } elseif (is_array($value) || is_object($value)) {
                $value = json_encode($value);
            }

            $stringData[(string)$key] = (string)$value;
        }

        return $stringData;
    }
}

if (!function_exists('resolveFirebaseCredentialsPath')) {
    function resolveFirebaseCredentialsPath(): string {
        $candidates = [];

        if (defined('FIREBASE_CREDENTIALS') && FIREBASE_CREDENTIALS) {
            $candidates[] = (string) FIREBASE_CREDENTIALS;
        }

        $fromEnv = getenv('FIREBASE_CREDENTIALS') ?: '';
        if ($fromEnv !== '') {
            $candidates[] = $fromEnv;
        }

        $phpBackendRoot = dirname(__DIR__, 2);
        $siteRoot = dirname($phpBackendRoot);
        $docRoot = rtrim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''), '/');

        $candidates = array_merge($candidates, [
            $phpBackendRoot . '/config/firebase-service-account.json',
            $siteRoot . '/config/firebase-service-account.json',
            $siteRoot . '/house/config/firebase-service-account.json',
            $phpBackendRoot . '/firebase-service-account.json',
            __DIR__ . '/firebase-service-account.json',
            '/home/atphieleqa/houseforrent.site/php_backend/config/firebase-service-account.json',
            '/home/atphieleqa/houseforrent.site/config/firebase-service-account.json',
        ]);

        if ($docRoot !== '') {
            $candidates[] = $docRoot . '/php_backend/config/firebase-service-account.json';
            $candidates[] = $docRoot . '/config/firebase-service-account.json';
        }

        foreach ($candidates as $path) {
            $path = trim((string) $path);
            if ($path !== '' && is_file($path) && is_readable($path)) {
                return $path;
            }
        }

        return '';
    }
}

if (!function_exists('loadFirebaseMessaging')) {
    function loadFirebaseMessaging() {
        $autoload = dirname(__DIR__, 2) . '/vendor/autoload.php';
        if (!is_file($autoload)) {
            throw new RuntimeException(
                'Firebase PHP package is not installed. Run composer install in php_backend.'
            );
        }
        require_once $autoload;

        $factoryClass = 'Kreait\\Firebase\\Factory';
        if (!class_exists($factoryClass)) {
            throw new RuntimeException(
                'Firebase PHP classes were not found. Check php_backend/vendor and composer install.'
            );
        }

        $credentials = resolveFirebaseCredentialsPath();
        if ($credentials === '') {
            throw new RuntimeException(
                'FIREBASE_CREDENTIALS is missing. Place firebase-service-account.json in php_backend/config/ or set the env var.'
            );
        }

        return (new $factoryClass())
            ->withServiceAccount($credentials)
            ->createMessaging();
    }
}

if (!function_exists('fetchFirebaseTokensForRole')) {
    function fetchFirebaseTokensForRole(PDO $conn, string $targetRole): array {
        $roles = normalizeFirebaseNotificationRole($targetRole);

        if (empty($roles)) {
            $stmt = $conn->prepare("
                SELECT DISTINCT udt.fcm_token
                FROM user_device_tokens udt
                INNER JOIN users u ON u.id = udt.user_id
                WHERE udt.fcm_token IS NOT NULL
                  AND udt.fcm_token <> ''
            ");
            $stmt->execute();
        } else {
            $placeholders = implode(',', array_fill(0, count($roles), '?'));
            $stmt = $conn->prepare("
                SELECT DISTINCT udt.fcm_token
                FROM user_device_tokens udt
                INNER JOIN users u ON u.id = udt.user_id
                WHERE u.role IN ($placeholders)
                  AND udt.fcm_token IS NOT NULL
                  AND udt.fcm_token <> ''
            ");
            $stmt->execute($roles);
        }

        return array_values(array_filter(
            array_map('strval', $stmt->fetchAll(PDO::FETCH_COLUMN)),
            fn($token) => trim($token) !== ''
        ));
    }
}

if (!function_exists('sendFirebaseNotificationToRole')) {
    function sendFirebaseNotificationToRole(
        PDO $conn,
        string $targetRole,
        string $title,
        string $body,
        array $data = []
    ): array {
        $messaging = loadFirebaseMessaging();
        $cloudMessageClass = 'Kreait\\Firebase\\Messaging\\CloudMessage';
        $notificationClass = 'Kreait\\Firebase\\Messaging\\Notification';

        if (!class_exists($cloudMessageClass) || !class_exists($notificationClass)) {
            throw new RuntimeException('Firebase messaging classes were not found.');
        }

        $tokens = fetchFirebaseTokensForRole($conn, $targetRole);
        $tokenCount = count($tokens);
        if ($tokenCount === 0) {
            return ['sent' => 0, 'failed' => 0, 'tokens' => 0];
        }

        $stringData = stringifyFirebaseData($data);

        $sent = 0;
        $failed = 0;
        foreach ($tokens as $token) {
            try {
                $message = call_user_func([$cloudMessageClass, 'withTarget'], 'token', trim($token))
                    ->withNotification(call_user_func([$notificationClass, 'create'], $title, $body))
                    ->withData($stringData);
                $messaging->send($message);
                $sent++;
            } catch (Throwable $error) {
                $failed++;
                error_log('Firebase push failed: ' . $error->getMessage());
            }
        }

        return ['sent' => $sent, 'failed' => $failed, 'tokens' => $tokenCount];
    }
}

if (!function_exists('fetchFirebaseTokensForUserIds')) {
    function fetchFirebaseTokensForUserIds(PDO $conn, array $userIds): array
    {
        $userIds = array_values(array_unique(array_filter(
            array_map('intval', $userIds),
            static fn(int $id): bool => $id > 0
        )));
        if ($userIds === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($userIds), '?'));
        $stmt = $conn->prepare("
            SELECT DISTINCT udt.fcm_token
            FROM user_device_tokens udt
            WHERE udt.user_id IN ($placeholders)
              AND udt.fcm_token IS NOT NULL
              AND udt.fcm_token <> ''
        ");
        $stmt->execute($userIds);

        return array_values(array_filter(
            array_map('strval', $stmt->fetchAll(PDO::FETCH_COLUMN)),
            static fn($token) => trim($token) !== ''
        ));
    }
}

if (!function_exists('sendFirebaseNotificationEnsuringUsers')) {
    /**
     * Send to a role (e.g. all) and always include specific user IDs too
     * (poster, request owner, etc.) so they receive the push as well.
     */
    function sendFirebaseNotificationEnsuringUsers(
        PDO $conn,
        string $targetRole,
        array $ensureUserIds,
        string $title,
        string $body,
        array $data = []
    ): array {
        $tokens = fetchFirebaseTokensForRole($conn, $targetRole);
        $extraTokens = fetchFirebaseTokensForUserIds($conn, $ensureUserIds);
        if ($extraTokens !== []) {
            $tokens = array_values(array_unique(array_merge($tokens, $extraTokens)));
        }

        $messaging = loadFirebaseMessaging();
        $cloudMessageClass = 'Kreait\\Firebase\\Messaging\\CloudMessage';
        $notificationClass = 'Kreait\\Firebase\\Messaging\\Notification';

        if (!class_exists($cloudMessageClass) || !class_exists($notificationClass)) {
            throw new RuntimeException('Firebase messaging classes were not found.');
        }

        $tokenCount = count($tokens);
        if ($tokenCount === 0) {
            return ['sent' => 0, 'failed' => 0, 'tokens' => 0];
        }

        $stringData = stringifyFirebaseData(array_merge([
            'title' => $title,
            'body' => $body,
            'message' => $body,
            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
        ], $data));

        $sent = 0;
        $failed = 0;
        foreach ($tokens as $token) {
            try {
                $message = call_user_func([$cloudMessageClass, 'withTarget'], 'token', trim($token))
                    ->withNotification(call_user_func([$notificationClass, 'create'], $title, $body))
                    ->withData($stringData);
                $messaging->send($message);
                $sent++;
            } catch (Throwable $error) {
                $failed++;
                error_log('Firebase push failed: ' . $error->getMessage());
            }
        }

        return ['sent' => $sent, 'failed' => $failed, 'tokens' => $tokenCount];
    }
}

if (!function_exists('sendFirebaseNotificationToUserIds')) {
    /**
     * Push ONLY to specific user IDs (no role broadcast).
     * Use for private chats: agent → that tenant only.
     */
    function sendFirebaseNotificationToUserIds(
        PDO $conn,
        array $userIds,
        string $title,
        string $body,
        array $data = []
    ): array {
        $tokens = fetchFirebaseTokensForUserIds($conn, $userIds);
        $tokenCount = count($tokens);
        if ($tokenCount === 0) {
            return ['sent' => 0, 'failed' => 0, 'tokens' => 0];
        }

        $messaging = loadFirebaseMessaging();
        $cloudMessageClass = 'Kreait\\Firebase\\Messaging\\CloudMessage';
        $notificationClass = 'Kreait\\Firebase\\Messaging\\Notification';

        if (!class_exists($cloudMessageClass) || !class_exists($notificationClass)) {
            throw new RuntimeException('Firebase messaging classes were not found.');
        }

        $stringData = stringifyFirebaseData(array_merge([
            'title' => $title,
            'body' => $body,
            'message' => $body,
            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
        ], $data));

        $sent = 0;
        $failed = 0;
        foreach ($tokens as $token) {
            try {
                $message = call_user_func([$cloudMessageClass, 'withTarget'], 'token', trim($token))
                    ->withNotification(call_user_func([$notificationClass, 'create'], $title, $body))
                    ->withData($stringData);
                $messaging->send($message);
                $sent++;
            } catch (Throwable $error) {
                $failed++;
                error_log('Firebase user push failed: ' . $error->getMessage());
            }
        }

        return ['sent' => $sent, 'failed' => $failed, 'tokens' => $tokenCount];
    }
}

