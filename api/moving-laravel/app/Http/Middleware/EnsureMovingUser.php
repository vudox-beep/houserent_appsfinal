<?php

namespace App\Http\Middleware;

use App\Support\MovingJwtAuth;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class EnsureMovingUser
{
    public function handle(Request $request, Closure $next): Response
    {
        $userId = (int) ($request->header('x-user-id') ?: $request->input('user_id', 0));
        if ($userId < 1) {
            $userId = MovingJwtAuth::userIdFromRequest($request) ?? 0;
        }
        if ($userId < 1) {
            return response()->json([
                'status' => 'error',
                'code' => 'login_required',
                'message' => 'Please log in before using moving bookings.',
            ], 401);
        }

        $baseSelect = [
            'u.id', 'u.name', 'u.email', 'u.phone', 'u.role', 'u.is_banned',
            'd.vehicle_type', 'd.vehicle_capacity', 'd.vehicle_plate',
            'd.service_area', 'd.availability_status', 'd.booking_tokens',
            'd.total_earnings',
        ];
        $identitySelect = [
            'd.identity_verified', 'd.identity_doc_type',
            'd.licence_photo_url', 'd.nrc_front_url', 'd.nrc_back_url',
            'd.photo_url',
        ];

        try {
            $user = DB::table('users as u')
                ->leftJoin('drivers as d', 'd.user_id', '=', 'u.id')
                ->where('u.id', $userId)
                ->select(array_merge($baseSelect, $identitySelect))
                ->first();
        } catch (\Throwable) {
            $user = DB::table('users as u')
                ->leftJoin('drivers as d', 'd.user_id', '=', 'u.id')
                ->where('u.id', $userId)
                ->select($baseSelect)
                ->first();
        }

        if (! $user || (int) ($user->is_banned ?? 0) === 1) {
            return response()->json([
                'status' => 'error',
                'code' => 'invalid_account',
                'message' => 'Your account is unavailable.',
            ], 401);
        }

        $request->attributes->set('moving_user', $user);

        return $next($request);
    }
}
