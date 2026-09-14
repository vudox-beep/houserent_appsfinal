<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class CheckMovingApiKey
{
    public function handle(Request $request, Closure $next): Response
    {
        $expected = (string) config('moving.api_shared_secret', '');
        if ($expected === '' || $expected === 'replace-with-a-long-random-secret') {
            return $next($request);
        }

        $actual = (string) $request->header('x-api-key', '');
        if (! hash_equals($expected, $actual)) {
            return response()->json([
                'status' => 'error',
                'code' => 'invalid_api_key',
                'message' => 'The mobile app could not be authenticated.',
            ], 401);
        }

        return $next($request);
    }
}
