<?php

namespace App\Support;

use Illuminate\Http\Request;

/**
 * Validates the same Bearer JWT issued by php_backend/api/auth/login.php.
 */
class MovingJwtAuth
{
    private static ?string $cachedSecret = null;

    public static function userIdFromRequest(Request $request): ?int
    {
        $auth = (string) $request->header('Authorization', '');
        if ($auth === '' || ! preg_match('/^Bearer\s+(\S+)$/i', $auth, $matches)) {
            return null;
        }

        return self::userIdFromToken($matches[1]);
    }

    public static function userIdFromToken(string $token): ?int
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            return null;
        }

        $header = self::decodeJson($parts[0]);
        $payload = self::decodeJson($parts[1]);
        if (! is_array($header) || ($header['alg'] ?? '') !== 'HS256' || ! is_array($payload)) {
            return null;
        }

        if (! isset($payload['id'], $payload['exp']) || ! is_numeric($payload['id'])) {
            return null;
        }
        if ((int) $payload['exp'] < time()) {
            return null;
        }

        $secret = self::secret();
        if ($secret === '') {
            return null;
        }

        $expected = self::base64UrlEncode(
            hash_hmac('sha256', $parts[0].'.'.$parts[1], $secret, true)
        );
        if (! hash_equals($expected, $parts[2])) {
            return null;
        }

        return (int) $payload['id'];
    }

    private static function secret(): string
    {
        if (self::$cachedSecret !== null) {
            return self::$cachedSecret;
        }

        $fromEnv = trim((string) (env('JWT_SECRET') ?: getenv('JWT_SECRET') ?: ''));
        if (strlen($fromEnv) >= 32) {
            return self::$cachedSecret = $fromEnv;
        }

        foreach (self::secretFileCandidates() as $path) {
            $real = realpath($path) ?: $path;
            if (! is_file($real)) {
                continue;
            }
            $contents = @file_get_contents($real);
            if ($contents === false) {
                continue;
            }
            if (preg_match('/^JWT_SECRET=(.+)$/m', $contents, $matches)) {
                $value = trim($matches[1], " \t\n\r\0\x0B\"'");
                if (strlen($value) >= 32) {
                    return self::$cachedSecret = $value;
                }
            }
        }

        return self::$cachedSecret = '';
    }

    /** @return list<string> */
    private static function secretFileCandidates(): array
    {
        return array_values(array_filter([
            dirname(base_path(), 2).'/.env',
            dirname(base_path(), 3).'/.env',
            dirname(base_path(), 2).'/../backend/.env',
            dirname(base_path(), 3).'/../backend/.env',
        ]));
    }

    private static function decodeJson(string $part): ?array
    {
        $json = self::base64UrlDecode($part);
        if ($json === false) {
            return null;
        }
        $decoded = json_decode($json, true);

        return is_array($decoded) ? $decoded : null;
    }

    private static function base64UrlDecode(string $value): string|false
    {
        if (! preg_match('/^[A-Za-z0-9_-]+$/', $value)) {
            return false;
        }
        $padding = strlen($value) % 4;
        if ($padding > 0) {
            $value .= str_repeat('=', 4 - $padding);
        }
        $decoded = base64_decode(strtr($value, '-_', '+/'), true);

        return $decoded === false ? false : $decoded;
    }

    private static function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
