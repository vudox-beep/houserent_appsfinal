# Moving Marketplace API (Laravel)

Laravel port of `api/moving-marketplace` (Node). Same REST contract for the Flutter app:

- Base path: `/api/v1/...`
- Auth headers: `x-user-id` (required), `x-api-key` (optional)
- JSON shape: `{ status, message, data }`

Uses the existing HouseRent MySQL tables (`users`, `drivers`, `moving_bookings`, …).  
**Do not run** Laravel’s default migrations on the production HouseRent database.

## Local

```bash
cd api/moving-laravel
cp .env.example .env
php artisan key:generate
# Edit .env → MySQL credentials matching php_backend/config/config.php
php artisan serve
```

Health check: `http://127.0.0.1:8000/api/health`  
Example: `GET /api/v1/drivers/me` with header `x-user-id: <driver_user_id>`

## cPanel deploy

1. Upload the whole `moving-laravel` folder to e.g. `public_html/api/moving-laravel`.
2. On the server: `composer install --no-dev` (or upload `vendor/` from a matching PHP version).
3. Copy `.env.example` → `.env`, set `APP_KEY`, MySQL, `APP_URL`.
4. Point the site (or subdomain) **document root** at `moving-laravel/public`, **or** keep the folder URL and use:

   `https://your-domain/api/moving-laravel/public`

5. Ensure `storage/` and `bootstrap/cache/` are writable.

## Flutter

Set in `lib/services/moving_marketplace_service.dart`:

```dart
static const String baseUrl = 'https://houseforrent.site/api/moving-laravel/public';
```

Calls become `{baseUrl}/api/v1/...`.

Realtime (Socket.IO) from the Node app is not included; polling / refresh works over REST.
