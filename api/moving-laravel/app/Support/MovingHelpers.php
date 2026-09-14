<?php

namespace App\Support;

use App\Exceptions\ApiException;
use Illuminate\Http\JsonResponse;

class MovingHelpers
{
    public static function ok(string $message, array $data = [], int $status = 200): JsonResponse
    {
        return response()->json([
            'status' => 'success',
            'message' => $message,
            'data' => $data,
        ], $status);
    }

    public static function requireRole(object $user, string ...$roles): void
    {
        $role = strtolower(trim((string) ($user->role ?? '')));
        $allowed = array_map(static fn (string $r) => strtolower(trim($r)), $roles);
        if (! in_array($role, $allowed, true)) {
            throw new ApiException(
                403,
                'wrong_account_type',
                'This action is not available for your account type.',
            );
        }
    }

    /** Tenants, dealers, and regular users can post a move request. */
    public static function requireCanRequestMove(object $user): void
    {
        $role = strtolower(trim((string) ($user->role ?? '')));
        if ($role === 'driver') {
            throw new ApiException(
                403,
                'wrong_account_type',
                'Use a tenant account to request a move.',
            );
        }
    }

    public static function requirePositiveAmount(mixed $value): float
    {
        $amount = round((float) $value, 2);
        if (! is_finite($amount) || $amount <= 0) {
            throw new ApiException(422, 'invalid_amount', 'Enter a valid price greater than zero.');
        }

        return $amount;
    }

    /** Furniture-move fare — never below configured minimum (default K400). */
    public static function requireMovingFare(mixed $value): float
    {
        $amount = self::requirePositiveAmount($value);
        $min = (float) config('moving.min_fare', 400);
        if ($amount + 0.001 < $min) {
            throw new ApiException(
                422,
                'fare_too_low',
                'Furniture move fare must be at least K '.number_format($min, 0).'.',
            );
        }

        return $amount;
    }

    public static function requireCoordinate(mixed $value, float $min, float $max, string $label): float
    {
        $coordinate = (float) $value;
        if (! is_finite($coordinate) || $coordinate < $min || $coordinate > $max) {
            throw new ApiException(422, 'invalid_location', "{$label} is invalid.");
        }

        return $coordinate;
    }
}
