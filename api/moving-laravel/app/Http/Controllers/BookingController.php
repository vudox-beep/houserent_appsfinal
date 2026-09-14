<?php

namespace App\Http\Controllers;

use App\Exceptions\ApiException;
use App\Services\MovingBookingService;
use App\Support\MovingFirestoreSync;
use App\Support\MovingHelpers;
use App\Support\MovingPushNotifier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class BookingController extends Controller
{
    public function __construct(private MovingBookingService $moving) {}

    private function user(Request $request): object
    {
        return $request->attributes->get('moving_user');
    }

    private function syncFirestore(int $bookingId): void
    {
        MovingFirestoreSync::syncBookingId($bookingId);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireCanRequestMove($user);

        $pickup = $request->input('pickup', []);
        $dropoff = $request->input('dropoff', []);
        $movingDate = (string) $request->input('moving_date', '');
        $items = trim((string) $request->input('item_description', ''));
        $phone = trim((string) ($request->input('contact_phone') ?: $user->phone ?: ''));

        if (empty($pickup['address']) || empty($dropoff['address']) || $movingDate === '' || $items === '' || $phone === '') {
            throw new ApiException(
                422,
                'missing_booking_details',
                'Add pickup, destination, moving date, items and a contact number.',
            );
        }

        if (strtotime($movingDate.' 23:59:59') < time()) {
            throw new ApiException(422, 'invalid_moving_date', 'Choose today or a future moving date.');
        }

        $pickupLat = MovingHelpers::requireCoordinate($pickup['latitude'] ?? null, -90, 90, 'Pickup latitude');
        $pickupLng = MovingHelpers::requireCoordinate($pickup['longitude'] ?? null, -180, 180, 'Pickup longitude');
        $dropoffLat = MovingHelpers::requireCoordinate($dropoff['latitude'] ?? null, -90, 90, 'Drop-off latitude');
        $dropoffLng = MovingHelpers::requireCoordinate($dropoff['longitude'] ?? null, -180, 180, 'Drop-off longitude');

        // Tenant's starting price for furniture / rental shifting (min K400).
        $offerRaw = $request->input('tenant_offer');
        $tenantOffer = ($offerRaw !== null && $offerRaw !== '')
            ? MovingHelpers::requireMovingFare($offerRaw)
            : null;

        $insert = [
            'tenant_id' => $user->id,
            'pickup_location' => mb_substr((string) $pickup['address'], 0, 255),
            'pickup_place_id' => mb_substr((string) ($pickup['place_id'] ?? ''), 0, 255) ?: null,
            'pickup_latitude' => $pickupLat,
            'pickup_longitude' => $pickupLng,
            'dropoff_location' => mb_substr((string) $dropoff['address'], 0, 255),
            'dropoff_place_id' => mb_substr((string) ($dropoff['place_id'] ?? ''), 0, 255) ?: null,
            'dropoff_latitude' => $dropoffLat,
            'dropoff_longitude' => $dropoffLng,
            'moving_date' => $movingDate,
            'moving_time' => mb_substr((string) $request->input('moving_time', ''), 0, 50) ?: null,
            'item_description' => mb_substr($items, 0, 5000),
            'contact_phone' => mb_substr($phone, 0, 30),
        ];
        if ($tenantOffer !== null) {
            $insert['tenant_offer'] = $tenantOffer;
        }

        try {
            $id = DB::table('moving_bookings')->insertGetId($insert);
        } catch (\Throwable $e) {
            // Existing installs don't have the column yet — add it once and retry.
            if ($tenantOffer !== null && str_contains($e->getMessage(), 'tenant_offer')) {
                DB::statement(
                    'ALTER TABLE moving_bookings ADD COLUMN tenant_offer DECIMAL(10,2) NULL AFTER contact_phone',
                );
                $id = DB::table('moving_bookings')->insertGetId($insert);
            } else {
                throw $e;
            }
        }

        $booking = $this->moving->getBooking($id);
        $this->syncFirestore($id);
        // No broadcast push to every driver. Drivers see open requests in the
        // live feed; push alerts stay between the booker and that driver only.

        return MovingHelpers::ok(
            'Your moving request is live. Available drivers can now respond.',
            ['booking' => $this->moving->shape($booking, $user, true)],
            201,
        );
    }

    public function index(Request $request): JsonResponse
    {
        $user = $this->user($request);
        $page = max(1, (int) $request->query('page', 1));
        $limit = min(50, max(1, (int) $request->query('limit', 20)));
        $offset = ($page - 1) * $limit;
        // Inline limit/offset — MySQL often rejects bound LIMIT parameters.
        $limitSql = (int) $limit;
        $offsetSql = (int) $offset;

        $ratingSelect = "
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
        ";

        if (in_array($user->role, ['user', 'tenant'], true)) {
            $rows = DB::select(
                "SELECT b.*, tenant.name AS tenant_name, tenant.phone AS tenant_phone,
                        driver.name AS driver_name, driver.phone AS driver_phone,
                        d.vehicle_type, d.vehicle_capacity, d.vehicle_plate,
                        d.current_latitude AS driver_latitude, d.current_longitude AS driver_longitude,
                        d.location_updated_at,
                        {$ratingSelect},
                        1 AS unlock_id
                   FROM moving_bookings b
                   JOIN users tenant ON tenant.id = b.tenant_id
                   LEFT JOIN users driver ON driver.id = b.driver_id
                   LEFT JOIN drivers d ON d.user_id = b.driver_id
                  WHERE b.tenant_id = ?
                  ORDER BY b.created_at DESC
                  LIMIT {$limitSql} OFFSET {$offsetSql}",
                [$user->id],
            );
        } else {
            MovingHelpers::requireRole($user, 'driver');
            $rows = DB::select(
                "SELECT b.*, tenant.name AS tenant_name, tenant.phone AS tenant_phone,
                        driver.name AS driver_name, driver.phone AS driver_phone,
                        d.vehicle_type, d.vehicle_capacity, d.vehicle_plate,
                        d.current_latitude AS driver_latitude, d.current_longitude AS driver_longitude,
                        d.location_updated_at,
                        {$ratingSelect},
                        x.id AS unlock_id
                   FROM moving_bookings b
                   JOIN users tenant ON tenant.id = b.tenant_id
                   LEFT JOIN users driver ON driver.id = b.driver_id
                   LEFT JOIN drivers d ON d.user_id = b.driver_id
                   LEFT JOIN driver_booking_unlocks x ON x.booking_id = b.id AND x.driver_id = ?
                  WHERE b.status = 'open' OR b.driver_id = ?
                  ORDER BY CASE b.status
                             WHEN 'in_progress' THEN 0
                             WHEN 'accepted' THEN 1
                             WHEN 'open' THEN 2
                             ELSE 3
                           END,
                           b.moving_date ASC
                  LIMIT {$limitSql} OFFSET {$offsetSql}",
                [$user->id, $user->id],
            );
        }

        return MovingHelpers::ok('Moving requests loaded.', [
            'bookings' => array_map(
                fn ($row) => $this->moving->shape($row, $user, (bool) ($row->unlock_id ?? false)),
                $rows,
            ),
            'pagination' => ['page' => $page, 'limit' => $limit, 'returned' => count($rows)],
        ]);
    }

    public function show(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        $booking = $this->moving->getBooking($bookingId);
        $unlocked = $user->role === 'driver'
            ? $this->moving->driverUnlocked((int) $booking->id, (int) $user->id)
            : (int) $booking->tenant_id === (int) $user->id;

        if (! $unlocked && (int) ($booking->driver_id ?? 0) !== (int) $user->id) {
            if ($user->role !== 'driver' || $booking->status !== 'open') {
                throw new ApiException(403, 'not_a_participant', 'You cannot view this moving request.');
            }
        }

        // Opening an open request counts as a view for the tenant.
        if ($user->role === 'driver' && ($booking->status ?? '') === 'open') {
            $this->moving->recordView((int) $booking->id, (int) $user->id);
        }

        $shaped = $this->moving->shape($booking, $user, $unlocked);
        if (in_array($user->role, ['user', 'tenant'], true)
            && (int) $booking->tenant_id === (int) $user->id) {
            $shaped['viewers'] = $this->moving->listViews((int) $booking->id);
            $shaped['view_count'] = count($shaped['viewers']);
        }

        return MovingHelpers::ok('Moving request loaded.', [
            'booking' => $shaped,
        ]);
    }

    /** Driver marks that they opened / looked at a shift request. */
    public function markViewed(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');
        $booking = $this->moving->getBooking($bookingId);
        if (($booking->status ?? '') !== 'open') {
            return MovingHelpers::ok('Request is no longer open.', [
                'viewed' => false,
            ]);
        }
        $this->moving->recordView((int) $booking->id, (int) $user->id);

        return MovingHelpers::ok('View recorded.', ['viewed' => true]);
    }

    /** Tenant: which drivers have viewed this open request (live). */
    public function listViews(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'user', 'tenant');
        $booking = $this->moving->getBooking($bookingId);
        if ((int) $booking->tenant_id !== (int) $user->id) {
            throw new ApiException(403, 'not_a_participant', 'You cannot view viewers for this request.');
        }
        // Default: only drivers who saw it but have not sent a price yet.
        $notResponding = filter_var(
            $request->query('not_responding', '1'),
            FILTER_VALIDATE_BOOLEAN,
        );
        $viewers = $this->moving->listViews((int) $booking->id, $notResponding);
        $all = $this->moving->listViews((int) $booking->id, false);

        return MovingHelpers::ok('Viewers loaded.', [
            'viewers' => $viewers,
            'count' => count($viewers),
            'seen_not_responding' => count($viewers),
            'seen_total' => count($all),
            'responded_count' => count(array_filter(
                $all,
                static fn ($v) => ! empty($v['responded']),
            )),
        ]);
    }

    public function unlock(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        $result = DB::transaction(function () use ($user, $bookingId) {
            $identityCols = \App\Support\DriverIdentity::columnsReady()
                ? ', identity_verified, identity_doc_type, licence_photo_url, nrc_front_url, nrc_back_url'
                : '';
            $driver = DB::selectOne(
                "SELECT booking_tokens, availability_status{$identityCols}
                   FROM drivers WHERE user_id = ? FOR UPDATE",
                [$user->id],
            );
            $booking = $this->moving->getBooking($bookingId, true);

            if (! $driver || $driver->availability_status !== 'available') {
                throw new ApiException(
                    409,
                    'driver_unavailable',
                    'Set your status to available before unlocking requests.',
                );
            }
            \App\Support\DriverIdentity::requireVerified($driver);
            if ($booking->status !== 'open') {
                throw new ApiException(409, 'booking_not_open', 'This request is no longer open.');
            }

            $inserted = DB::table('driver_booking_unlocks')->insertOrIgnore([
                'driver_id' => $user->id,
                'booking_id' => $booking->id,
            ]);

            if ($inserted > 0) {
                if ((int) $driver->booking_tokens < 1) {
                    throw new ApiException(
                        402,
                        'token_required',
                        'Buy one booking token to unlock this request.',
                    );
                }
                DB::table('drivers')
                    ->where('user_id', $user->id)
                    ->decrement('booking_tokens');
            }

            $this->moving->recordView((int) $booking->id, (int) $user->id);

            return ['booking' => $booking, 'spent' => $inserted > 0 ? 1 : 0];
        });

        return MovingHelpers::ok(
            $result['spent'] > 0
                ? 'Request unlocked. You can now chat and negotiate the price.'
                : 'This request was already unlocked.',
            [
                'booking' => $this->moving->shape(
                    $this->moving->getBooking($bookingId),
                    $user,
                    true,
                ),
                'token_spent' => $result['spent'],
            ],
        );
    }

    public function cancel(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        $booking = $this->moving->getBooking($bookingId);
        $status = (string) ($booking->status ?? '');
        $cancellable = in_array($status, ['open', 'accepted', 'in_progress'], true);

        if (! $cancellable) {
            throw new ApiException(
                409,
                'cannot_cancel',
                'This trip can no longer be cancelled.',
            );
        }

        $isTenant = in_array($user->role, ['user', 'tenant'], true)
            && (int) $booking->tenant_id === (int) $user->id;
        $isAssignedDriver = $user->role === 'driver'
            && (int) ($booking->driver_id ?? 0) === (int) $user->id
            && in_array($status, ['accepted', 'in_progress'], true);

        // Tenant may cancel open / accepted / in-progress.
        // Assigned driver may cancel accepted / in-progress.
        if (! $isTenant && ! $isAssignedDriver) {
            throw new ApiException(
                403,
                'cannot_cancel',
                'You cannot cancel this trip.',
            );
        }

        $updated = DB::table('moving_bookings')
            ->where('id', $booking->id)
            ->whereIn('status', ['open', 'accepted', 'in_progress'])
            ->update(['status' => 'cancelled']);

        if (! $updated) {
            throw new ApiException(
                409,
                'cannot_cancel',
                'This trip can no longer be cancelled.',
            );
        }

        $fresh = $this->moving->getBooking((int) $booking->id);
        $who = trim((string) ($user->name ?? 'Someone'));
        $notifyIds = [];
        if ($isTenant && ! empty($fresh->driver_id)) {
            $notifyIds[] = (int) $fresh->driver_id;
        } elseif ($isAssignedDriver) {
            $notifyIds[] = (int) $fresh->tenant_id;
        }
        if ($notifyIds !== []) {
            MovingPushNotifier::notifyUsers(
                $notifyIds,
                'Shift cancelled',
                $who.' cancelled the moving shift.',
                [
                    'event' => 'cancelled',
                    'booking_id' => (string) $fresh->id,
                    'route' => '/moving/my-shifts',
                ],
            );
        }

        $this->syncFirestore((int) $fresh->id);

        return MovingHelpers::ok(
            $isAssignedDriver
                ? 'Ride cancelled. The client has been notified.'
                : 'Your moving request has been cancelled.',
        );
    }

    public function storeOffer(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        $offer = $this->moving->createOffer($user, $bookingId, $request->all());

        $booking = $this->moving->getBooking($bookingId);
        $amount = number_format((float) ($offer->amount ?? 0), 0);
        $sender = trim((string) ($offer->sender_name ?? $user->name ?? 'Someone'));
        if ($user->role === 'driver') {
            MovingPushNotifier::notifyUsers(
                [(int) $booking->tenant_id],
                'New price offer',
                "$sender offered K$amount for your shift.",
                [
                    'event' => 'offer',
                    'booking_id' => (string) $bookingId,
                    'route' => '/moving',
                ],
            );
        } else {
            MovingPushNotifier::notifyUsers(
                [(int) ($offer->driver_id ?? 0)],
                'Counter offer',
                "$sender countered with K$amount.",
                [
                    'event' => 'offer',
                    'booking_id' => (string) $bookingId,
                    'route' => '/driver-dashboard',
                ],
            );
        }

        $this->syncFirestore($bookingId);

        return MovingHelpers::ok(
            $user->role === 'driver'
                ? 'Your price offer was sent to the tenant.'
                : 'Your counteroffer was sent to the driver.',
            ['offer' => $offer],
            201,
        );
    }

    public function listOffers(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        $driverIdParam = $request->query('driver_id');

        // Tenant without a specific driver: return every responding driver's
        // offers so the app can pop up "drivers responding with prices".
        if (! $driverIdParam && in_array($user->role, ['user', 'tenant'], true)) {
            $booking = $this->moving->getBooking($bookingId);
            if ((int) $booking->tenant_id === (int) $user->id) {
                $photoSelect = \Illuminate\Support\Facades\Schema::hasColumn('drivers', 'photo_url')
                    ? 'd.photo_url AS driver_photo_url'
                    : 'NULL AS driver_photo_url';

                $offers = DB::select(
                    "SELECT o.*, u.name AS sender_name, u.role AS sender_role,
                            du.name AS driver_name, du.phone AS driver_phone,
                            d.vehicle_type, d.vehicle_plate, {$photoSelect},
                            COALESCE((
                                SELECT ROUND(AVG(r.rating), 1)
                                  FROM moving_driver_ratings r
                                 WHERE r.driver_id = o.driver_id
                            ), 0) AS driver_rating,
                            (
                                SELECT COUNT(*)
                                  FROM moving_driver_ratings r
                                 WHERE r.driver_id = o.driver_id
                            ) AS driver_rating_count
                       FROM moving_booking_offers o
                       JOIN users u ON u.id = o.sender_id
                       JOIN users du ON du.id = o.driver_id
                       LEFT JOIN drivers d ON d.user_id = o.driver_id
                      WHERE o.booking_id = ?
                      ORDER BY o.id ASC",
                    [$booking->id],
                );

                $shaped = array_map(static function ($o) {
                    $row = (array) $o;
                    $name = (string) ($row['driver_name'] ?? $row['sender_name'] ?? 'Driver');
                    $photo = trim((string) ($row['driver_photo_url'] ?? ''));
                    if ($photo !== '' && ! str_starts_with($photo, 'http://') && ! str_starts_with($photo, 'https://')) {
                        $photo = 'https://houseforrent.site/'.ltrim($photo, '/');
                    }
                    $rating = (float) ($row['driver_rating'] ?? 0);
                    $ratingCount = (int) ($row['driver_rating_count'] ?? 0);
                    $row['avatar_url'] = \App\Support\MovingBookingPresenter::avatarUrl(
                        $name,
                        $photo !== '' ? $photo : null,
                    );
                    $row['photo_url'] = $photo !== '' ? $photo : null;
                    $row['premium_rated'] = \App\Support\MovingBookingPresenter::isPremiumRated(
                        $rating,
                        $ratingCount,
                    );
                    $row['rating_label'] = \App\Support\MovingBookingPresenter::ratingLabel(
                        $rating,
                        $ratingCount,
                    );

                    return $row;
                }, $offers);

                return MovingHelpers::ok('Price negotiation loaded.', [
                    'offers' => $shaped,
                    'driver_id' => null,
                ]);
            }
        }

        $access = $this->moving->requireConversationAccess(
            $user,
            $bookingId,
            $driverIdParam,
        );

        $offers = DB::select(
            'SELECT o.*, u.name AS sender_name, u.role AS sender_role
               FROM moving_booking_offers o
               JOIN users u ON u.id = o.sender_id
              WHERE o.booking_id = ? AND o.driver_id = ?
              ORDER BY o.id ASC',
            [$access['booking']->id, $access['driverId']],
        );

        return MovingHelpers::ok('Price negotiation loaded.', [
            'offers' => $offers,
            'driver_id' => $access['driverId'],
        ]);
    }

    public function rejectOffer(Request $request, int $bookingId, int $offerId): JsonResponse
    {
        $user = $this->user($request);
        $booking = $this->moving->getBooking($bookingId);
        $offer = DB::selectOne(
            "SELECT * FROM moving_booking_offers
              WHERE id = ? AND booking_id = ? AND status = 'pending'",
            [$offerId, $booking->id],
        );

        if (! $offer) {
            throw new ApiException(409, 'offer_unavailable', 'This price offer is no longer available.');
        }

        $isTenantOwner = in_array($user->role, ['user', 'tenant'], true)
            && (int) $booking->tenant_id === (int) $user->id;
        $isOfferDriver = $user->role === 'driver'
            && (int) $offer->driver_id === (int) $user->id
            && (int) $offer->sender_id !== (int) $user->id;

        if (! $isTenantOwner && ! $isOfferDriver) {
            throw new ApiException(403, 'not_a_participant', 'You cannot decline this offer.');
        }

        DB::table('moving_booking_offers')
            ->where('id', $offer->id)
            ->update(['status' => 'rejected']);

        return MovingHelpers::ok('Offer declined.');
    }

    public function acceptOffer(Request $request, int $bookingId, int $offerId): JsonResponse
    {
        $user = $this->user($request);

        $updated = DB::transaction(function () use ($user, $bookingId, $offerId) {
            $booking = $this->moving->getBooking($bookingId, true);
            $offer = DB::selectOne(
                "SELECT * FROM moving_booking_offers
                  WHERE id = ? AND booking_id = ? AND status = 'pending'
                  FOR UPDATE",
                [$offerId, $booking->id],
            );

            $live = in_array($booking->status, ['open', 'accepted', 'in_progress'], true);
            if (! $offer || ! $live) {
                throw new ApiException(
                    409,
                    'offer_unavailable',
                    'This price offer is no longer available.',
                );
            }

            // Tenant owns the booking and offer was sent by the driver.
            $isTenant = (int) $booking->tenant_id === (int) $user->id
                && (int) $offer->sender_id === (int) $offer->driver_id
                && (int) $offer->sender_id !== (int) $user->id;
            $isDriver = $user->role === 'driver'
                && (int) $offer->driver_id === (int) $user->id
                && (int) $offer->sender_id === (int) $booking->tenant_id;

            if (! $isTenant && ! $isDriver) {
                throw new ApiException(
                    403,
                    'cannot_accept_own_offer',
                    'Only the other person can accept this price.',
                );
            }

            // Accept first, then close other pending offers (avoid race).
            DB::table('moving_booking_offers')
                ->where('id', $offer->id)
                ->update(['status' => 'accepted']);

            DB::table('moving_booking_offers')
                ->where('booking_id', $booking->id)
                ->where('status', 'pending')
                ->where('id', '!=', $offer->id)
                ->update(['status' => 'rejected']);

            // First accept assigns the driver; later accepts only update fare.
            $update = ['agreed_amount' => $offer->amount];
            if ($booking->status === 'open') {
                $update['driver_id'] = $offer->driver_id;
                $update['status'] = 'accepted';
            }

            DB::table('moving_bookings')
                ->where('id', $booking->id)
                ->update($update);

            return $this->moving->getBooking((int) $booking->id);
        });

        $amount = number_format((float) ($updated->agreed_amount ?? 0), 0);
        $driverName = trim((string) ($updated->driver_name ?? 'Your driver'));
        if ((int) $user->id === (int) $updated->tenant_id) {
            MovingPushNotifier::notifyUsers(
                [(int) ($updated->driver_id ?? 0)],
                'Price agreed',
                "The client accepted K$amount. Open the app to start the shift.",
                [
                    'event' => 'accepted',
                    'booking_id' => (string) $bookingId,
                    'route' => '/driver-dashboard',
                ],
            );
        } else {
            MovingPushNotifier::notifyUsers(
                [(int) $updated->tenant_id],
                'Price agreed',
                "$driverName agreed on K$amount for your shift.",
                [
                    'event' => 'accepted',
                    'booking_id' => (string) $bookingId,
                    'route' => '/moving',
                ],
            );
        }

        $this->syncFirestore($bookingId);

        return MovingHelpers::ok('Price agreed.', [
            'booking' => $this->moving->shape($updated, $user, true),
        ]);
    }

    public function storeMessage(Request $request, int $bookingId): JsonResponse
    {
        $message = $this->moving->createMessage($this->user($request), $bookingId, $request->all());
        $user = $this->user($request);
        $booking = $this->moving->getBooking($bookingId);
        $snippet = MovingPushNotifier::short($message['message'] ?? '', 90);
        $sender = trim((string) ($message['sender_name'] ?? $user->name ?? 'Someone'));
        $recipientId = 0;
        if ($user->role === 'driver') {
            $recipientId = (int) $booking->tenant_id;
        } elseif (in_array($user->role, ['user', 'tenant'], true)) {
            $recipientId = (int) ($message['driver_id'] ?? $booking->driver_id ?? 0);
        }
        if ($recipientId > 0 && $recipientId !== (int) $user->id) {
            MovingPushNotifier::notifyUsers(
                [$recipientId],
                'Shift message',
                "$sender: $snippet",
                [
                    'event' => 'message',
                    'booking_id' => (string) $bookingId,
                    'route' => $user->role === 'driver' ? '/moving' : '/driver-dashboard',
                ],
            );
        }

        return MovingHelpers::ok('Message sent.', ['message' => $message], 201);
    }

    public function listMessages(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        $access = $this->moving->requireConversationAccess(
            $user,
            $bookingId,
            $request->query('driver_id'),
        );
        $afterId = max(0, (int) $request->query('after_id', 0));

        $messages = DB::select(
            'SELECT m.*, u.name AS sender_name, u.role AS sender_role
               FROM moving_booking_messages m
               JOIN users u ON u.id = m.sender_id
              WHERE m.booking_id = ? AND m.driver_id = ? AND m.id > ?
              ORDER BY m.id ASC
              LIMIT 200',
            [$access['booking']->id, $access['driverId'], $afterId],
        );

        DB::update(
            'UPDATE moving_booking_messages
                SET read_at = COALESCE(read_at, NOW())
              WHERE booking_id = ? AND driver_id = ? AND sender_id <> ?',
            [$access['booking']->id, $access['driverId'], $user->id],
        );

        return MovingHelpers::ok('Conversation loaded.', [
            'messages' => $messages,
            'driver_id' => $access['driverId'],
        ]);
    }

    /** Driver starts the accepted move → in_progress (tenant sees it live). */
    public function start(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        $shaped = null;
        try {
            DB::transaction(function () use ($user, $bookingId, &$shaped) {
                $booking = $this->moving->getBooking($bookingId, true);
                if ((int) ($booking->driver_id ?? 0) !== (int) $user->id) {
                    throw new ApiException(
                        403,
                        'not_your_job',
                        'Only the assigned driver can start this ride.',
                    );
                }
                if ($booking->status === 'in_progress') {
                    $shaped = $this->moving->shape($booking, $user, true);

                    return;
                }
                if ($booking->status !== 'accepted') {
                    throw new ApiException(
                        409,
                        'cannot_start',
                        'Start the ride after the client accepts your price. Current status: '.$booking->status,
                    );
                }

                DB::table('moving_bookings')
                    ->where('id', $booking->id)
                    ->update(['status' => 'in_progress']);

                $booking->status = 'in_progress';
                $shaped = $this->moving->shape($booking, $user, true);
            });
        } catch (ApiException $e) {
            throw $e;
        } catch (\Throwable $e) {
            // Common on cPanel: status column is ENUM without `in_progress`.
            $msg = $e->getMessage();
            if (str_contains($msg, 'in_progress') || str_contains($msg, 'Data truncated') || str_contains($msg, '1265')) {
                throw new ApiException(
                    500,
                    'status_not_allowed',
                    'Database status column does not allow in_progress. Run sql/add_in_progress_status.sql on MySQL.',
                );
            }
            throw new ApiException(
                500,
                'start_failed',
                'Could not start ride: '.$msg,
            );
        }

        if ($shaped !== null) {
            $booking = $this->moving->getBooking($bookingId);
            $driverName = trim((string) ($booking->driver_name ?? 'Your driver'));
            MovingPushNotifier::notifyUsers(
                [(int) $booking->tenant_id],
                'Trip started',
                "$driverName is on the way to your pickup.",
                [
                    'event' => 'started',
                    'booking_id' => (string) $bookingId,
                    'route' => '/moving',
                ],
            );
        }

        $this->syncFirestore($bookingId);

        return MovingHelpers::ok('Ride started. Navigate to the client.', [
            'booking' => $shaped,
        ]);
    }

    /** Driver arrived at client destination (in_progress → arrived). */
    public function arrived(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        $shaped = null;
        DB::transaction(function () use ($user, $bookingId, &$shaped) {
            $booking = $this->moving->getBooking($bookingId, true);
            if ((int) ($booking->driver_id ?? 0) !== (int) $user->id) {
                throw new ApiException(
                    403,
                    'not_your_job',
                    'Only the assigned driver can mark arrival.',
                );
            }
            if ($booking->status === 'arrived') {
                $shaped = $this->moving->shape($booking, $user, true);

                return;
            }
            if ($booking->status !== 'in_progress') {
                throw new ApiException(
                    409,
                    'cannot_arrive',
                    'Mark arrival while the trip is in progress. Current status: '.$booking->status,
                );
            }

            DB::table('moving_bookings')
                ->where('id', $booking->id)
                ->update(['status' => 'arrived']);

            $booking->status = 'arrived';
            $shaped = $this->moving->shape($booking, $user, true);
        });

        if ($shaped !== null) {
            $booking = $this->moving->getBooking($bookingId);
            $driverName = trim((string) ($booking->driver_name ?? 'Your driver'));
            $place = MovingPushNotifier::short($booking->dropoff_location ?? 'destination');
            MovingPushNotifier::notifyUsers(
                [(int) $booking->tenant_id],
                'Driver arrived',
                "$driverName arrived at $place.",
                [
                    'event' => 'arrived',
                    'booking_id' => (string) $bookingId,
                    'route' => '/moving',
                ],
            );
        }

        $this->syncFirestore($bookingId);

        return MovingHelpers::ok('Arrived at destination. Client has been notified.', [
            'booking' => $shaped,
        ]);
    }

    public function complete(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'driver');

        DB::transaction(function () use ($user, $bookingId) {
            $booking = $this->moving->getBooking($bookingId, true);
            $okStatus = in_array($booking->status, ['accepted', 'in_progress', 'arrived'], true);
            if (! $okStatus || (int) $booking->driver_id !== (int) $user->id) {
                throw new ApiException(
                    409,
                    'cannot_complete',
                    'Only your active job can be marked complete.',
                );
            }

            DB::table('moving_bookings')
                ->where('id', $booking->id)
                ->update(['status' => 'completed']);

            DB::table('drivers')
                ->where('user_id', $user->id)
                ->increment('total_earnings', (float) ($booking->agreed_amount ?? 0));
        });

        $booking = $this->moving->getBooking($bookingId);

        MovingPushNotifier::notifyUsers(
            [(int) $booking->tenant_id],
            'Shift completed',
            'Your move is complete. Tap to rate your driver.',
            [
                'event' => 'completed',
                'booking_id' => (string) $bookingId,
                'route' => '/moving/my-shifts',
            ],
        );

        $this->syncFirestore($bookingId);

        return MovingHelpers::ok('Move completed. The tenant can now rate your service.', [
            'booking' => $this->moving->shape($booking, $user, true),
        ]);
    }

    public function rate(Request $request, int $bookingId): JsonResponse
    {
        $user = $this->user($request);
        MovingHelpers::requireRole($user, 'user', 'tenant');

        $booking = $this->moving->getBooking($bookingId);
        if ($booking->status !== 'completed'
            || (int) $booking->tenant_id !== (int) $user->id
            || empty($booking->driver_id)) {
            throw new ApiException(
                403,
                'rating_not_allowed',
                'You can rate your driver after a completed move.',
            );
        }

        $rating = (int) $request->input('rating');
        if ($rating < 1 || $rating > 5) {
            throw new ApiException(422, 'invalid_rating', 'Choose a rating from 1 to 5 stars.');
        }

        $comment = trim((string) $request->input('comment', ''));
        $comment = $comment === '' ? null : mb_substr($comment, 0, 500);

        DB::statement(
            'INSERT INTO moving_driver_ratings (booking_id, tenant_id, driver_id, rating, comment)
             VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE rating = VALUES(rating), comment = VALUES(comment)',
            [$booking->id, $user->id, $booking->driver_id, $rating, $comment],
        );

        $summary = DB::selectOne(
            'SELECT ROUND(AVG(rating), 1) AS rating, COUNT(*) AS rating_count
               FROM moving_driver_ratings WHERE driver_id = ?',
            [$booking->driver_id],
        );

        return MovingHelpers::ok('Thank you. Your driver rating has been saved.', [
            'driver_rating' => $summary,
        ]);
    }
}
