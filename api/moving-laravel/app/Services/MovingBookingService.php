<?php

namespace App\Services;

use App\Exceptions\ApiException;
use App\Support\DriverIdentity;
use App\Support\MovingBookingPresenter;
use App\Support\MovingHelpers;
use Illuminate\Support\Facades\DB;

class MovingBookingService
{
    public function getBooking(int $bookingId, bool $lock = false): object
    {
        $sql = "
            SELECT b.*,
                tenant.name AS tenant_name,
                tenant.phone AS tenant_phone,
                driver.name AS driver_name,
                driver.phone AS driver_phone,
                d.vehicle_type,
                d.vehicle_capacity,
                d.vehicle_plate,
                d.current_latitude AS driver_latitude,
                d.current_longitude AS driver_longitude,
                d.location_updated_at,
                ".(DriverIdentity::columnsReady()
                    ? 'd.photo_url AS driver_photo_url, d.identity_verified, d.identity_doc_type, d.licence_photo_url, d.nrc_front_url, d.nrc_back_url,'
                    : 'NULL AS driver_photo_url, 0 AS identity_verified, NULL AS identity_doc_type, NULL AS licence_photo_url, NULL AS nrc_front_url, NULL AS nrc_back_url,')."
                COALESCE((
                    SELECT ROUND(AVG(r.rating), 1)
                      FROM moving_driver_ratings r
                     WHERE r.driver_id = b.driver_id
                ), 0) AS driver_rating,
                (
                    SELECT COUNT(*)
                      FROM moving_driver_ratings r
                     WHERE r.driver_id = b.driver_id
                ) AS driver_rating_count
            FROM moving_bookings b
            JOIN users tenant ON tenant.id = b.tenant_id
            LEFT JOIN users driver ON driver.id = b.driver_id
            LEFT JOIN drivers d ON d.user_id = b.driver_id
            WHERE b.id = ?
        ";

        if ($lock) {
            $sql .= ' FOR UPDATE';
        }

        $row = DB::selectOne($sql, [$bookingId]);
        if (! $row) {
            throw new ApiException(404, 'booking_not_found', 'This moving request was not found.');
        }

        return $row;
    }

    public function driverUnlocked(int $bookingId, int $driverId): bool
    {
        return DB::table('driver_booking_unlocks')
            ->where('booking_id', $bookingId)
            ->where('driver_id', $driverId)
            ->exists();
    }

    /**
     * @return array{booking: object, driverId: int}
     */
    public function requireConversationAccess(object $user, int $bookingId, mixed $requestedDriverId): array
    {
        $booking = $this->getBooking($bookingId);

        if ($user->role === 'driver') {
            $driverId = (int) $user->id;
            $unlocked = $this->driverUnlocked((int) $booking->id, $driverId);
            if (! $unlocked && (int) ($booking->driver_id ?? 0) !== $driverId) {
                throw new ApiException(
                    403,
                    'request_locked',
                    'Unlock this request before contacting the tenant.',
                );
            }

            return ['booking' => $booking, 'driverId' => $driverId];
        }

        if (in_array($user->role, ['user', 'tenant'], true)
            && (int) $booking->tenant_id === (int) $user->id) {
            $driverId = (int) ($requestedDriverId ?: $booking->driver_id);
            if (! $driverId || ! $this->driverUnlocked((int) $booking->id, $driverId)) {
                throw new ApiException(
                    403,
                    'driver_not_available',
                    'This driver has not unlocked your request.',
                );
            }

            return ['booking' => $booking, 'driverId' => $driverId];
        }

        throw new ApiException(403, 'not_a_participant', 'You are not part of this moving request.');
    }

    public function shape(object $row, object $user, bool $unlocked = false): array
    {
        return MovingBookingPresenter::shape($row, $user, $unlocked);
    }

    /** Ensure views table exists (safe to call repeatedly). */
    public function ensureViewsTable(): void
    {
        static $ready = false;
        if ($ready) {
            return;
        }
        try {
            DB::statement(
                'CREATE TABLE IF NOT EXISTS moving_booking_views (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    booking_id BIGINT UNSIGNED NOT NULL,
                    driver_id INT UNSIGNED NOT NULL,
                    viewed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_booking_driver (booking_id, driver_id),
                    KEY idx_booking_viewed (booking_id, viewed_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',
            );
            $ready = true;
        } catch (\Throwable) {
            // Host may already have the table or lack CREATE privilege.
        }
    }

    /** Idempotent: first open by a driver counts as a view. */
    public function recordView(int $bookingId, int $driverId): void
    {
        $this->ensureViewsTable();
        try {
            DB::statement(
                'INSERT INTO moving_booking_views (booking_id, driver_id, viewed_at)
                 VALUES (?, ?, NOW())
                 ON DUPLICATE KEY UPDATE viewed_at = viewed_at',
                [$bookingId, $driverId],
            );
        } catch (\Throwable) {
            // Ignore if table still missing — tenant UI just shows 0 viewers.
        }
    }

    /**
     * Drivers who opened this request (tenant-facing).
     * Includes responded=true when they already sent a price.
     *
     * @return list<array{id:int,name:string,vehicle_type:?string,vehicle_plate:?string,avatar_url:string,viewed_at:?string,latitude:?float,longitude:?float,responded:bool}>
     */
    public function listViews(int $bookingId, bool $notRespondingOnly = false): array
    {
        $this->ensureViewsTable();
        try {
            $rows = DB::select(
                'SELECT v.driver_id, v.viewed_at, u.name,
                        d.vehicle_type, d.vehicle_plate,
                        d.current_latitude, d.current_longitude,
                        (
                            EXISTS (
                                SELECT 1 FROM moving_booking_offers o
                                 WHERE o.booking_id = v.booking_id
                                   AND o.driver_id = v.driver_id
                                   AND o.sender_id = v.driver_id
                                   AND o.status IN (\'pending\', \'accepted\')
                            )
                        ) AS responded
                   FROM moving_booking_views v
                   JOIN users u ON u.id = v.driver_id
                   LEFT JOIN drivers d ON d.user_id = v.driver_id
                  WHERE v.booking_id = ?
                  ORDER BY v.viewed_at DESC
                  LIMIT 40',
                [$bookingId],
            );
        } catch (\Throwable) {
            return [];
        }

        $out = [];
        foreach ($rows as $row) {
            $responded = (int) ($row->responded ?? 0) === 1;
            if ($notRespondingOnly && $responded) {
                continue;
            }
            $name = (string) ($row->name ?? 'Driver');
            $out[] = [
                'id' => (int) $row->driver_id,
                'name' => $name,
                'vehicle_type' => $row->vehicle_type,
                'vehicle_plate' => $row->vehicle_plate,
                'avatar_url' => MovingBookingPresenter::avatarUrl($name),
                'viewed_at' => $row->viewed_at,
                'latitude' => $row->current_latitude === null
                    ? null
                    : (float) $row->current_latitude,
                'longitude' => $row->current_longitude === null
                    ? null
                    : (float) $row->current_longitude,
                'responded' => $responded,
                'status_label' => $responded ? 'Responded' : 'Seen · not responding',
            ];
        }

        return $out;
    }

    public function createOffer(object $user, int $bookingId, array $payload): object
    {
        return DB::transaction(function () use ($user, $bookingId, $payload) {
            $booking = $this->getBooking($bookingId, true);
            // Price negotiation only while the request is still open.
            if ($booking->status !== 'open') {
                throw new ApiException(
                    409,
                    'booking_not_open',
                    'Price negotiation is closed after the ride is accepted.',
                );
            }

            if ($user->role === 'driver') {
                $driverId = (int) $user->id;
                if (! $this->driverUnlocked((int) $booking->id, $driverId)) {
                    throw new ApiException(
                        403,
                        'request_locked',
                        'Unlock this request before making an offer.',
                    );
                }
            } elseif (in_array($user->role, ['user', 'tenant'], true)
                && (int) $booking->tenant_id === (int) $user->id) {
                $driverId = (int) ($payload['driver_id'] ?? 0);
                if (! $driverId || ! $this->driverUnlocked((int) $booking->id, $driverId)) {
                    throw new ApiException(
                        403,
                        'driver_not_available',
                        'Choose a driver who has unlocked your request.',
                    );
                }
            } else {
                throw new ApiException(
                    403,
                    'not_a_participant',
                    'You cannot negotiate on this request.',
                );
            }

            $amount = MovingHelpers::requireMovingFare($payload['amount'] ?? null);
            $note = trim((string) ($payload['note'] ?? ''));
            $note = $note === '' ? null : mb_substr($note, 0, 500);

            DB::table('moving_booking_offers')
                ->where('booking_id', $booking->id)
                ->where('driver_id', $driverId)
                ->where('status', 'pending')
                ->update(['status' => 'rejected']);

            $offerId = DB::table('moving_booking_offers')->insertGetId([
                'booking_id' => $booking->id,
                'driver_id' => $driverId,
                'sender_id' => $user->id,
                'amount' => $amount,
                'currency' => 'ZMW',
                'note' => $note,
                'status' => 'pending',
            ]);

            $offer = DB::selectOne(
                'SELECT o.*, u.name AS sender_name, u.role AS sender_role
                   FROM moving_booking_offers o
                   JOIN users u ON u.id = o.sender_id
                  WHERE o.id = ?',
                [$offerId],
            );

            return $offer ?? (object) [];
        });
    }

    public function createMessage(object $user, int $bookingId, array $payload): array
    {
        $access = $this->requireConversationAccess(
            $user,
            $bookingId,
            $payload['driver_id'] ?? null,
        );
        $booking = $access['booking'];
        $driverId = $access['driverId'];

        $message = trim((string) ($payload['message'] ?? ''));
        if ($message === '' || mb_strlen($message) > 1000) {
            throw new ApiException(
                422,
                'invalid_message',
                'Write a message between 1 and 1000 characters.',
            );
        }

        $id = DB::table('moving_booking_messages')->insertGetId([
            'booking_id' => $booking->id,
            'driver_id' => $driverId,
            'sender_id' => $user->id,
            'message' => $message,
        ]);

        return [
            'id' => (int) $id,
            'booking_id' => (int) $booking->id,
            'driver_id' => $driverId,
            'sender_id' => (int) $user->id,
            'sender_name' => $user->name,
            'sender_role' => $user->role,
            'message' => $message,
            'created_at' => now()->toIso8601String(),
        ];
    }

    public function updateDriverLocation(object $user, array $payload): array
    {
        MovingHelpers::requireRole($user, 'driver');
        $latitude = MovingHelpers::requireCoordinate($payload['latitude'] ?? null, -90, 90, 'Latitude');
        $longitude = MovingHelpers::requireCoordinate($payload['longitude'] ?? null, -180, 180, 'Longitude');

        DB::table('drivers')
            ->where('user_id', $user->id)
            ->update([
                'current_latitude' => $latitude,
                'current_longitude' => $longitude,
                'location_updated_at' => now(),
            ]);

        return [
            'driver_id' => (int) $user->id,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'updated_at' => now()->toIso8601String(),
        ];
    }
}
