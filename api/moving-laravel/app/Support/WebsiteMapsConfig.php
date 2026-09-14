<?php

namespace App\Support;

/**
 * Reads GOOGLE_MAPS_API_KEY from the same website config files as house/api/maps.php.
 * On cPanel the key lives in house/config/config.php — not in moving-laravel/.env.
 */
class WebsiteMapsConfig
{
    private static ?string $cachedKey = null;

    /** @return list<string> */
    private static function configFileCandidates(): array
    {
        return array_values(array_filter([
            dirname(base_path(), 2).'/config/config.php',
            dirname(base_path(), 3).'/config/config.php',
            dirname(base_path(), 2).'/house/config/config.php',
            dirname(base_path(), 3).'/house/config/config.php',
            dirname(base_path(), 2).'/php_backend/config/config.php',
            dirname(base_path(), 3).'/php_backend/config/config.php',
            base_path('../../config/config.php'),
            base_path('../../house/config/config.php'),
            base_path('../../php_backend/config/config.php'),
        ]));
    }

    public static function apiKey(): string
    {
        if (self::$cachedKey !== null) {
            return self::$cachedKey;
        }

        $fromEnv = trim((string) config('moving.google_maps_api_key'));
        if ($fromEnv !== '') {
            return self::$cachedKey = $fromEnv;
        }

        foreach (self::configFileCandidates() as $path) {
            $real = realpath($path) ?: $path;
            $key = self::readKeyFromFile($real);
            if ($key !== null) {
                return self::$cachedKey = $key;
            }
        }

        return self::$cachedKey = 'AIzaSyDH0JpnMofvCFnx9byn6TUm_GV6YW9onZU';
    }

    private static function readKeyFromFile(string $path): ?string
    {
        if (! is_file($path)) {
            return null;
        }

        $contents = @file_get_contents($path);
        if ($contents === false) {
            return null;
        }

        if (! preg_match(
            "/define\s*\(\s*['\"]GOOGLE_MAPS_API_KEY['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)/",
            $contents,
            $matches
        )) {
            return null;
        }

        $key = trim($matches[1]);
        $placeholders = [
            '',
            'your-google-maps-api-key',
            'YOUR_GOOGLE_MAPS_API_KEY_HERE',
        ];

        if (in_array($key, $placeholders, true)) {
            return null;
        }

        return $key;
    }
}
