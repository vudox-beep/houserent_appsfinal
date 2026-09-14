<?php

return [
    /*
    | Optional shared secret. When empty or the placeholder, x-api-key is not required.
    | Must match MovingMarketplaceService.apiSharedSecret in the Flutter app.
    */
    'api_shared_secret' => env('API_SHARED_SECRET', ''),

    /*
    | Furniture / rental shifting fare (not taxi).
    | Day 06:00–19:59 · Night 20:00–05:59. Minimum always K400.
    | Must match MovingMarketplaceService in the Flutter app.
    */
    'min_fare' => (float) env('MOVING_MIN_FARE', 400),
    'day_base_fare' => (float) env('MOVING_DAY_BASE_FARE', 400),
    'day_per_km' => (float) env('MOVING_DAY_PER_KM', 25),
    'night_base_fare' => (float) env('MOVING_NIGHT_BASE_FARE', 500),
    'night_per_km' => (float) env('MOVING_NIGHT_PER_KM', 35),
    // Legacy keys (day defaults) — kept for older env files.
    'base_fare' => (float) env('MOVING_BASE_FARE', 400),
    'per_km' => (float) env('MOVING_PER_KM', 25),

    /*
    | Google Maps key for the /v1/maps proxy (autocomplete, place details,
    | reverse geocoding). When empty, WebsiteMapsConfig reads house/config/config.php
    | (same file as the website maps API), then falls back to the app key.
    */
    // env('KEY', default) still returns '' when KEY is set but empty in .env.
    'google_maps_api_key' => env('GOOGLE_MAPS_API_KEY') ?: '',

    /*
    | Absolute path to php_backend firebase_push.php (optional).
    | When empty, common repo paths are tried automatically.
    */
    'firebase_push_path' => env('FIREBASE_PUSH_PATH', ''),

    /*
    | Firebase service-account JSON (same file used for FCM push).
    | Example on cPanel: /home/youruser/firebase/service-account.json
    */
    'firebase_credentials' => env('FIREBASE_CREDENTIALS', ''),
];
