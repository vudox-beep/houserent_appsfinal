# Moving Marketplace API

Node.js REST + Socket.IO service for the Flutter tenant and driver apps.

## What it handles

- Tenants create Google Maps-ready moving requests.
- Drivers spend one platform token to unlock a request.
- Tenant and driver chat in real time.
- Drivers offer a price; tenants can counteroffer.
- Either party can accept the other party's latest price.
- The accepted driver is shown with name, phone, vehicle, number plate and rating.
- Drivers can send live GPS location during an accepted move.
- Tenants rate drivers after completion.
- Tenant-to-driver payment is **not** processed by the platform.

## cPanel setup

1. Import `database/migrations/20260729_moving_marketplace_api.sql`.
2. Open **Setup Node.js App** in cPanel.
3. Create an app using Node.js 18 or newer.
4. Set the application root to `api/moving-marketplace`.
5. Set the startup file to `server.js`.
6. Add the environment variables shown in `.env.example`.
7. In the cPanel terminal, run `npm install` inside the application root.
8. Restart the Node.js application.

Use a long random `API_SHARED_SECRET`. Send it from Flutter as `x-api-key`.

Database credentials are loaded from cPanel environment variables first. If they
are not set, `database-config.js` reads the existing `DB_HOST`, `DB_USER`,
`DB_PASS`, and `DB_NAME` constants from `config/config.php`, so the Node service
uses the same database as the PHP website.

## Request headers

```text
Content-Type: application/json
x-api-key: YOUR_API_SHARED_SECRET
x-user-id: ID_RETURNED_BY_YOUR_EXISTING_LOGIN
```

## Main REST routes

Base path: `/api/v1`

| Method | Route | Role | Purpose |
|---|---|---|---|
| POST | `/bookings` | Tenant | Create a moving request |
| GET | `/bookings` | Both | List own/open requests |
| GET | `/bookings/:id` | Both | Get one request |
| POST | `/bookings/:id/unlock` | Driver | Spend one token |
| POST | `/bookings/:id/cancel` | Tenant | Cancel an open request |
| POST | `/bookings/:id/offers` | Both | Offer or counteroffer |
| GET | `/bookings/:id/offers?driver_id=7` | Both | Price history |
| POST | `/bookings/:id/offers/:offerId/accept` | Both | Accept other party's price |
| POST | `/bookings/:id/messages` | Both | Send chat message |
| GET | `/bookings/:id/messages?driver_id=7&after_id=0` | Both | Load chat |
| POST | `/bookings/:id/complete` | Driver | Complete accepted move |
| POST | `/bookings/:id/rating` | Tenant | Rate completed driver |
| GET | `/drivers/me` | Driver | Profile, tokens and rating |
| PATCH | `/drivers/me/profile` | Driver | Vehicle and number plate |
| PATCH | `/drivers/me/availability` | Driver | Available/unavailable |
| PATCH | `/drivers/me/location` | Driver | Send live GPS location |

## Create booking with Google Maps data

Use the formatted address, Place ID and coordinates returned by Google Places.

```json
{
  "pickup": {
    "address": "Manda Hill Road, Lusaka, Zambia",
    "place_id": "ChIJ_PICKUP_PLACE_ID",
    "latitude": -15.3971,
    "longitude": 28.3228
  },
  "dropoff": {
    "address": "Makeni, Lusaka, Zambia",
    "place_id": "ChIJ_DROPOFF_PLACE_ID",
    "latitude": -15.4702,
    "longitude": 28.2538
  },
  "moving_date": "2026-08-05",
  "moving_time": "09:30",
  "item_description": "One bed, sofa, fridge and six boxes",
  "contact_phone": "0971234567"
}
```

## Price offer and counteroffer

Driver offer:

```json
{
  "amount": 850,
  "note": "I can arrive at 09:00."
}
```

Tenant counteroffer (tenant supplies the driver conversation):

```json
{
  "driver_id": 920,
  "amount": 700,
  "note": "Can you do it for ZMW 700?"
}
```

The platform records the agreed amount only. The tenant and driver arrange payment themselves.

## Socket.IO

Connect with:

```dart
final socket = IO.io(
  apiUrl,
  IO.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({
        'userId': loggedInUserId,
        'apiKey': apiSharedSecret,
      })
      .enableAutoConnect()
      .build(),
);
```

Join a booking conversation:

```dart
socket.emitWithAck('booking:join', {
  'booking_id': bookingId,
  'driver_id': driverId, // required for tenant before assignment
});
```

Listen for real-time updates:

```dart
socket.on('booking:available', (data) {});
socket.on('booking:unlocked', (data) {});
socket.on('message:new', (data) {});
socket.on('offer:new', (data) {});
socket.on('offer:accepted', (data) {});
socket.on('booking:status', (data) {});
socket.on('driver:location', (data) {});
socket.on('driver:rating', (data) {});
```

Send events:

```dart
socket.emit('message:send', {
  'booking_id': bookingId,
  'driver_id': driverId,
  'message': 'I am ready at the pickup point.',
});

socket.emit('offer:submit', {
  'booking_id': bookingId,
  'driver_id': driverId,
  'amount': 750,
  'note': 'Final price',
});

socket.emit('driver:location', {
  'latitude': currentPosition.latitude,
  'longitude': currentPosition.longitude,
});
```

REST remains available as a fallback when the socket is temporarily disconnected.
