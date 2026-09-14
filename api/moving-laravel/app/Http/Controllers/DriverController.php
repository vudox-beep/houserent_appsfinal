<?php

namespace App\Http\Controllers;

use App\Exceptions\ApiException;
use App\Services\MovingBookingService;
use App\Support\DriverIdentity;
use App\Support\MovingFirestoreSync;
use App\Support\MovingHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class DriverController extends Controller
{
    public function __construct(private MovingBookingService $moving) {}

    private function user(Request $request): object
    {
        return $request->attributes->get('moving_user');
    }

    public function me(Request $request): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        $ratings = DB::selectOne(
            'SELECT COALESCE(ROUND(AVG(rating), 1), 0) AS rating, COUNT(*) AS rating_count
               FROM moving_driver_ratings WHERE driver_id = ?',
            [$user->id],
        );

        $jobs = DB::selectOne(
            "SELECT
                SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
                SUM(CASE WHEN status IN ('accepted', 'in_progress') THEN 1 ELSE 0 END) AS active,
                COALESCE(SUM(CASE WHEN status = 'completed' THEN agreed_amount ELSE 0 END), 0) AS completed_earnings
               FROM moving_bookings WHERE driver_id = ?",
            [$user->id],
        );

        $identity = DriverIdentity::statusFor($user);
        $photo = trim((string) ($user->photo_url ?? ''));
        if ($photo !== '' && ! str_starts_with($photo, 'http://') && ! str_starts_with($photo, 'https://')) {
            $photo = 'https://houseforrent.site/'.ltrim($photo, '/');
        }

        return MovingHelpers::ok('Driver profile loaded.', [
            'driver' => [
                'id' => (int) $user->id,
                'name' => $user->name,
                'phone' => $user->phone,
                'vehicle_type' => $user->vehicle_type,
                'vehicle_capacity' => $user->vehicle_capacity,
                'vehicle_plate' => $user->vehicle_plate,
                'service_area' => $user->service_area,
                'availability_status' => $user->availability_status,
                'photo_url' => $photo !== '' ? $photo : null,
                'avatar_url' => \App\Support\MovingBookingPresenter::avatarUrl(
                    (string) $user->name,
                    $photo !== '' ? $photo : null,
                ),
                'booking_tokens' => (int) ($user->booking_tokens ?? 0),
                'total_earnings' => (float) ($user->total_earnings ?? $jobs->completed_earnings ?? 0),
                'jobs_completed' => (int) ($jobs->completed ?? 0),
                'jobs_active' => (int) ($jobs->active ?? 0),
                'rating' => (float) ($ratings->rating ?? 0),
                'rating_count' => (int) ($ratings->rating_count ?? 0),
                'identity_verified' => $identity['code'],
                'identity_status' => $identity['status'],
                'identity_message' => $identity['message'],
                'identity_doc_type' => $identity['doc_type'],
                'identity_photos' => $identity['photos'],
                'can_work' => $identity['status'] === 'verified',
            ],
        ]);
    }

    /** Upload the driver’s face/profile photo shown to tenants (not ID documents). */
    public function uploadProfilePhoto(Request $request): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        $file = $request->file('photo')
            ?? $request->file('profile')
            ?? $request->file('image');
        if (! $file) {
            throw new ApiException(422, 'missing_photo', 'Choose a clear photo of your face for your profile.');
        }

        if (! Schema::hasColumn('drivers', 'photo_url')) {
            throw new ApiException(
                503,
                'photo_not_ready',
                'Profile photos are not set up yet. Ask support to run add_driver_photo_url.sql.',
            );
        }

        $path = DriverIdentity::storeImage($file, (int) $user->id, 'profile');
        // Store under a clearer public folder name in the relative path if possible.
        DB::table('drivers')->where('user_id', $user->id)->update([
            'photo_url' => $path,
        ]);

        $absolute = 'https://houseforrent.site/'.ltrim($path, '/');

        return MovingHelpers::ok('Profile photo updated. Tenants will see this photo.', [
            'photo_url' => $absolute,
            'avatar_url' => $absolute,
        ]);
    }

    /** Upload driver’s licence OR NRC front + back for admin verification. */
    public function uploadIdentity(Request $request): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        if (! DriverIdentity::columnsReady()) {
            throw new ApiException(
                503,
                'identity_not_ready',
                'Identity verification is not set up yet. Please ask support to run the driver identity SQL.',
            );
        }

        $current = DriverIdentity::statusFor($user);
        if ($current['status'] === 'pending') {
            throw new ApiException(
                409,
                'identity_pending',
                'Your documents are already pending approval. You can upload again only if they are rejected.',
            );
        }
        if ($current['status'] === 'verified') {
            throw new ApiException(
                409,
                'identity_verified',
                'Your identity is already verified.',
            );
        }

        $docType = DriverIdentity::normalizeDocType($request->input('doc_type'));
        if ($docType === null) {
            throw new ApiException(
                422,
                'invalid_doc_type',
                'Choose driver’s licence or NRC.',
            );
        }

        $paths = [];
        if ($docType === 'licence') {
            $file = $request->file('licence') ?? $request->file('document');
            if (! $file) {
                throw new ApiException(422, 'missing_photo', 'Upload a clear photo of your driver’s licence.');
            }
            $paths['licence_photo_url'] = DriverIdentity::storeImage($file, (int) $user->id, 'licence');
        } else {
            $front = $request->file('nrc_front');
            $back = $request->file('nrc_back');
            if (! $front || ! $back) {
                throw new ApiException(
                    422,
                    'missing_photo',
                    'Upload both the NRC front page and the back page.',
                );
            }
            $paths['nrc_front_url'] = DriverIdentity::storeImage($front, (int) $user->id, 'nrc_front');
            $paths['nrc_back_url'] = DriverIdentity::storeImage($back, (int) $user->id, 'nrc_back');
        }

        DriverIdentity::markSubmitted((int) $user->id, $docType, $paths);

        $fresh = DB::table('drivers')->where('user_id', $user->id)->first();
        $identity = DriverIdentity::statusFor((object) array_merge((array) $user, (array) $fresh));

        return MovingHelpers::ok('Documents submitted. Waiting for admin approval.', [
            'identity_verified' => $identity['code'],
            'identity_status' => $identity['status'],
            'identity_message' => $identity['message'],
            'identity_doc_type' => $identity['doc_type'],
            'identity_photos' => $identity['photos'],
            'can_work' => false,
        ]);
    }

    public function updateLocation(Request $request): JsonResponse
    {
        $user = $this->user($request);
        $location = $this->moving->updateDriverLocation($user, $request->all());
        MovingFirestoreSync::syncDriverActiveBookings((int) $user->id);

        return MovingHelpers::ok('Driver location updated.', ['location' => $location]);
    }

    /**
     * Nearby available drivers for the tenant's "searching" map (Uber-style cars).
     */
    public function nearby(Request $request): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'user', 'tenant');

        $lat = MovingHelpers::requireCoordinate($request->query('lat'), -90, 90, 'Latitude');
        $lng = MovingHelpers::requireCoordinate($request->query('lng'), -180, 180, 'Longitude');
        $radiusKm = min(50, max(1, (float) $request->query('radius_km', 15)));

        $verifiedOnly = DriverIdentity::columnsReady()
            ? 'AND d.identity_verified = 1'
            : '';

        // Haversine in SQL — only online (and verified) drivers with a recent GPS fix.
        $rows = DB::select(
            "SELECT u.id, u.name, d.vehicle_type, d.vehicle_plate, d.vehicle_capacity,
                    d.current_latitude, d.current_longitude, d.location_updated_at,
                    COALESCE((
                        SELECT ROUND(AVG(r.rating), 1)
                          FROM moving_driver_ratings r
                         WHERE r.driver_id = u.id
                    ), 0) AS rating,
                    (
                        SELECT COUNT(*)
                          FROM moving_driver_ratings r
                         WHERE r.driver_id = u.id
                    ) AS rating_count,
                    (
                        6371 * ACOS(
                            LEAST(1, GREATEST(-1,
                                COS(RADIANS(?)) * COS(RADIANS(d.current_latitude))
                              * COS(RADIANS(d.current_longitude) - RADIANS(?))
                              + SIN(RADIANS(?)) * SIN(RADIANS(d.current_latitude))
                            ))
                        )
                    ) AS distance_km
               FROM drivers d
               JOIN users u ON u.id = d.user_id
              WHERE d.availability_status = 'available'
                {$verifiedOnly}
                AND d.current_latitude IS NOT NULL
                AND d.current_longitude IS NOT NULL
                AND ABS(d.current_latitude) > 0.0001
                AND ABS(d.current_longitude) > 0.0001
                AND (u.is_banned IS NULL OR u.is_banned = 0)
             HAVING distance_km <= ?
              ORDER BY distance_km ASC
              LIMIT 20",
            [$lat, $lng, $lat, $radiusKm],
        );

        $drivers = array_map(static function ($row) {
            $rating = (float) ($row->rating ?? 0);
            $ratingCount = (int) ($row->rating_count ?? 0);

            return [
                'id' => (int) $row->id,
                'name' => $row->name,
                'vehicle_type' => $row->vehicle_type,
                'vehicle_plate' => $row->vehicle_plate,
                'vehicle_capacity' => $row->vehicle_capacity,
                'rating' => $rating,
                'rating_count' => $ratingCount,
                'premium_rated' => \App\Support\MovingBookingPresenter::isPremiumRated(
                    $rating,
                    $ratingCount,
                ),
                'rating_label' => \App\Support\MovingBookingPresenter::ratingLabel(
                    $rating,
                    $ratingCount,
                ),
                'distance_km' => round((float) $row->distance_km, 2),
                'latitude' => (float) $row->current_latitude,
                'longitude' => (float) $row->current_longitude,
                'location_updated_at' => $row->location_updated_at,
            ];
        }, $rows);

        return MovingHelpers::ok('Nearby drivers loaded.', [
            'drivers' => $drivers,
            'count' => count($drivers),
        ]);
    }

    public function updateAvailability(Request $request): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        $availability = $request->input('availability_status') === 'available'
            ? 'available'
            : 'unavailable';

        if ($availability === 'available') {
            DriverIdentity::requireVerified($user);
        }

        DB::table('drivers')
            ->where('user_id', $user->id)
            ->update(['availability_status' => $availability]);

        return MovingHelpers::ok("You are now {$availability}.", [
            'availability_status' => $availability,
        ]);
    }

    public function updateProfile(Request $request): JsonResponse
    {
        // Live hosts may not have dedicated upload routes registered yet.
        if ($request->hasFile('photo') || $request->hasFile('profile') || $request->hasFile('image')) {
            return $this->uploadProfilePhoto($request);
        }
        if (
            $request->filled('doc_type')
            || $request->hasFile('licence')
            || $request->hasFile('document')
            || $request->hasFile('nrc_front')
            || $request->hasFile('nrc_back')
        ) {
            return $this->uploadIdentity($request);
        }

        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        $vehicleType = trim((string) ($request->input('vehicle_type') ?: $user->vehicle_type ?: ''));
        $vehicleCapacity = trim((string) ($request->input('vehicle_capacity') ?: $user->vehicle_capacity ?: ''));
        $vehiclePlate = strtoupper(trim((string) $request->input('vehicle_plate', '')));
        $serviceArea = trim((string) ($request->input('service_area') ?: $user->service_area ?: ''));

        if ($vehicleType === '' || $vehicleCapacity === '' || $vehiclePlate === '' || $serviceArea === '') {
            throw new ApiException(
                422,
                'missing_driver_details',
                'Vehicle type, capacity, number plate and service area are required.',
            );
        }

        DB::table('drivers')
            ->where('user_id', $user->id)
            ->update([
                'vehicle_type' => mb_substr($vehicleType, 0, 50),
                'vehicle_capacity' => mb_substr($vehicleCapacity, 0, 100),
                'vehicle_plate' => mb_substr($vehiclePlate, 0, 30),
                'service_area' => mb_substr($serviceArea, 0, 255),
            ]);

        return MovingHelpers::ok('Your driver and vehicle details have been updated.', [
            'driver' => [
                'id' => (int) $user->id,
                'name' => $user->name,
                'vehicle_type' => $vehicleType,
                'vehicle_capacity' => $vehicleCapacity,
                'vehicle_plate' => $vehiclePlate,
                'service_area' => $serviceArea,
            ],
        ]);
    }
}
