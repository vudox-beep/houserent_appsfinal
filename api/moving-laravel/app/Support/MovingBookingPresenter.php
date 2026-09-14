<?php

namespace App\Support;

class MovingBookingPresenter
{
    public static function shape(object $row, object $user, bool $unlocked = false): array
    {
        $assigned = $user->role === 'driver' && (int) ($row->driver_id ?? 0) === (int) $user->id;
        $tenantOwner = in_array($user->role, ['user', 'tenant'], true)
            && (int) $row->tenant_id === (int) $user->id;
        $canPrivate = $tenantOwner || $unlocked || $assigned;
        $showMap = $canPrivate || ($user->role === 'driver' && ($row->status ?? '') === 'open');

        $booking = [
            'id' => (int) $row->id,
            'status' => $row->status,
            'moving_date' => $row->moving_date,
            'moving_time' => $row->moving_time,
            'currency' => $row->currency ?? 'ZMW',
            'agreed_amount' => $row->agreed_amount,
            'created_at' => $row->created_at,
            'unlocked' => (bool) ($unlocked || $assigned),
        ];

        // System fare estimate from the trip distance (both sides see it).
        $km = self::distanceKm(
            (float) $row->pickup_latitude,
            (float) $row->pickup_longitude,
            (float) $row->dropoff_latitude,
            (float) $row->dropoff_longitude,
        );
        if ($km !== null) {
            $booking['distance_km'] = round($km, 1);
            $fare = self::estimateFare($km);
            $booking['estimated_price'] = $fare['amount'];
            $booking['fare_period'] = $fare['period'];
            $booking['fare_label'] = $fare['label'];
            $booking['min_fare'] = $fare['min'];
        }

        // Tenant's own starting price, when the column/value exists.
        if (isset($row->tenant_offer) && $row->tenant_offer !== null) {
            $booking['tenant_offer'] = (float) $row->tenant_offer;
        }

        if ($showMap) {
            // Drivers seeing open jobs get real addresses so the map card can show destination.
            $booking['pickup'] = [
                'address' => ($canPrivate || $user->role === 'driver')
                    ? $row->pickup_location
                    : 'Pickup nearby',
                'place_id' => $canPrivate ? $row->pickup_place_id : null,
                'latitude' => (float) $row->pickup_latitude,
                'longitude' => (float) $row->pickup_longitude,
            ];
            $booking['dropoff'] = [
                'address' => ($canPrivate || $user->role === 'driver')
                    ? $row->dropoff_location
                    : 'Drop-off nearby',
                'place_id' => $canPrivate ? $row->dropoff_place_id : null,
                'latitude' => (float) $row->dropoff_latitude,
                'longitude' => (float) $row->dropoff_longitude,
            ];
        }

        if ($canPrivate) {
            $booking['items'] = $row->item_description;
            $booking['contact_phone'] = $row->contact_phone;
            $booking['tenant'] = [
                'id' => (int) $row->tenant_id,
                'name' => $row->tenant_name,
                'phone' => $row->tenant_phone ?: $row->contact_phone,
            ];
        } elseif ($user->role === 'driver' && ($row->status ?? '') === 'open') {
            // Uber-style preview: name + phone + destination; full item list after unlock.
            $booking['tenant'] = [
                'id' => (int) $row->tenant_id,
                'name' => $row->tenant_name ?: 'Client',
                'phone' => $row->contact_phone ?: $row->tenant_phone,
            ];
            $booking['contact_phone'] = $row->contact_phone ?: $row->tenant_phone;
            $booking['items'] = 'Unlock to see full item list';
        }

        if (! empty($row->driver_id)) {
            $name = (string) ($row->driver_name ?? 'Driver');
            // Profile photo only — never licence/NRC document paths.
            $photo = trim((string) ($row->driver_photo_url ?? $row->photo_url ?? ''));
            if ($photo !== '' && ! str_starts_with($photo, 'http://') && ! str_starts_with($photo, 'https://')) {
                $photo = 'https://houseforrent.site/'.ltrim($photo, '/');
            }
            $identity = DriverIdentity::publicPayload($row);
            $rating = (float) ($row->driver_rating ?? 0);
            $ratingCount = (int) ($row->driver_rating_count ?? 0);
            $premium = self::isPremiumRated($rating, $ratingCount);
            $booking['driver'] = [
                'id' => (int) $row->driver_id,
                'name' => $name,
                'phone' => $row->driver_phone,
                'vehicle_type' => $row->vehicle_type,
                'vehicle_capacity' => $row->vehicle_capacity,
                'vehicle_plate' => $row->vehicle_plate,
                'photo_url' => $photo !== '' ? $photo : null,
                'avatar_url' => self::avatarUrl($name, $photo !== '' ? $photo : null),
                'rating' => $rating,
                'rating_count' => $ratingCount,
                'premium_rated' => $premium,
                'rating_label' => self::ratingLabel($rating, $ratingCount),
                'identity' => $identity,
                'identity_verified' => $identity !== null,
                'location' => $row->driver_latitude === null ? null : [
                    'latitude' => (float) $row->driver_latitude,
                    'longitude' => (float) $row->driver_longitude,
                    'updated_at' => $row->location_updated_at,
                ],
            ];
        }

        // Let the tenant rate once the driver marks the destination complete.
        if ($tenantOwner && ($row->status ?? '') === 'completed' && ! empty($row->driver_id)) {
            $already = \Illuminate\Support\Facades\DB::table('moving_driver_ratings')
                ->where('booking_id', $row->id)
                ->where('tenant_id', $user->id)
                ->exists();
            $booking['can_rate'] = ! $already;
            $booking['has_rated'] = $already;
        }

        return $booking;
    }

    /** High tenant ratings → Premium badge for other bookers. */
    public static function isPremiumRated(float $rating, int $count): bool
    {
        return $rating >= 4.5 && $count >= 3;
    }

    public static function ratingLabel(float $rating, int $count): ?string
    {
        if ($rating <= 0 || $count < 1) {
            return null;
        }
        $stars = rtrim(rtrim(number_format($rating, 1, '.', ''), '0'), '.');

        return self::isPremiumRated($rating, $count)
            ? "Premium · ★ {$stars} ({$count})"
            : "★ {$stars} ({$count})";
    }

    /** Profile photo when set, otherwise a neat generated avatar. */
    public static function avatarUrl(string $name, ?string $photoUrl = null): string
    {
        $photo = trim((string) $photoUrl);
        if ($photo !== '') {
            if (str_starts_with($photo, 'http://') || str_starts_with($photo, 'https://')) {
                return $photo;
            }

            return 'https://houseforrent.site/'.ltrim($photo, '/');
        }
        $label = trim($name) !== '' ? $name : 'Driver';

        return 'https://ui-avatars.com/api/?name='.rawurlencode($label)
            .'&background=FFC107&color=111111&size=256&bold=true';
    }

    /** Haversine distance; null when either point is missing/zero. */
    public static function distanceKm(float $lat1, float $lng1, float $lat2, float $lng2): ?float
    {
        foreach ([[$lat1, $lng1], [$lat2, $lng2]] as [$lat, $lng]) {
            if ((abs($lat) < 0.0001 && abs($lng) < 0.0001) || abs($lat) > 90 || abs($lng) > 180) {
                return null;
            }
        }

        $earth = 6371.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return $earth * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }

    /**
     * Furniture / rental shifting fare (not taxi).
     * Day 06:00–19:59 · Night 20:00–05:59. Floor K400.
     *
     * @return array{amount: float, period: string, label: string, min: float, base: float, per_km: float}
     */
    public static function estimateFare(float $km, $at = null): array
    {
        $at = $at instanceof \DateTimeInterface ? $at : now();
        $hour = (int) $at->format('G');
        $isNight = $hour >= 20 || $hour < 6;

        $min = (float) config('moving.min_fare', 400);
        $base = $isNight
            ? (float) config('moving.night_base_fare', 500)
            : (float) config('moving.day_base_fare', 400);
        $perKm = $isNight
            ? (float) config('moving.night_per_km', 35)
            : (float) config('moving.day_per_km', 25);

        $amount = max($min, round(($base + $perKm * max(0, $km)) / 5) * 5);

        return [
            'amount' => (float) $amount,
            'period' => $isNight ? 'night' : 'day',
            'label' => $isNight
                ? 'Night rate · furniture move'
                : 'Day rate · furniture move',
            'min' => $min,
            'base' => $base,
            'per_km' => $perKm,
        ];
    }
}
