<?php

namespace App\Http\Controllers;

use App\Support\WebsiteMapsConfig;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Google Maps proxy (autocomplete, place details, reverse geocode, API key).
 * Uses GOOGLE_MAPS_API_KEY from house/config/config.php — same as the website.
 */
class MapsController extends Controller
{
    public function handle(Request $request): JsonResponse
    {
        $action = (string) $request->input('action', '');

        return match ($action) {
            'get_api_key' => response()->json([
                'status' => 'success',
                'api_key' => $this->key(),
            ]),
            'autocomplete' => $this->autocomplete($request),
            'place_details' => $this->placeDetails($request),
            'geocode' => $this->geocode($request),
            default => response()->json([
                'status' => 'error',
                'message' => $action === '' ? 'Action is required' : 'Invalid action',
            ]),
        };
    }

    private function key(): string
    {
        return WebsiteMapsConfig::apiKey();
    }

    private function autocomplete(Request $request): JsonResponse
    {
        $input = trim((string) $request->input('input', ''));
        // '' or 'all' means worldwide; otherwise ISO country filter (e.g. zm).
        $country = strtolower(trim((string) $request->input('country', '')));
        $lat = $request->input('lat');
        $lng = $request->input('lng');

        if ($input === '') {
            return response()->json(['status' => 'error', 'message' => 'Search input is required']);
        }

        $url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
            .'?input='.urlencode($input)
            .'&key='.$this->key();
        if ($country !== '' && $country !== 'all') {
            $url .= '&components=country:'.urlencode($country);
        }
        if ($lat !== null && $lat !== '' && $lng !== null && $lng !== '') {
            // Bias results towards the user's GPS spot (80 km radius).
            $url .= '&location='.urlencode($lat.','.$lng).'&radius=80000';
        }

        $json = $this->google($url);
        if (($json['status'] ?? '') !== 'OK' && ($json['status'] ?? '') !== 'ZERO_RESULTS') {
            return response()->json([
                'status' => 'error',
                'message' => 'Failed to fetch predictions',
                'google_status' => $json['status'] ?? 'UNKNOWN',
            ]);
        }

        $places = [];
        foreach (($json['predictions'] ?? []) as $pred) {
            $places[] = [
                'place_id' => $pred['place_id'] ?? '',
                'description' => $pred['description'] ?? '',
            ];
        }

        return response()->json(['status' => 'success', 'predictions' => $places]);
    }

    private function placeDetails(Request $request): JsonResponse
    {
        $placeId = trim((string) $request->input('place_id', ''));
        if ($placeId === '') {
            return response()->json(['status' => 'error', 'message' => 'Place ID is required']);
        }

        $url = 'https://maps.googleapis.com/maps/api/place/details/json'
            .'?place_id='.urlencode($placeId)
            .'&fields=geometry,formatted_address'
            .'&key='.$this->key();

        $json = $this->google($url);
        if (($json['status'] ?? '') !== 'OK') {
            return response()->json([
                'status' => 'error',
                'message' => 'Failed to fetch place details',
                'google_status' => $json['status'] ?? 'UNKNOWN',
            ]);
        }

        $location = $json['result']['geometry']['location'] ?? null;

        return response()->json([
            'status' => 'success',
            'address' => $json['result']['formatted_address'] ?? '',
            'lat' => $location['lat'] ?? null,
            'lng' => $location['lng'] ?? null,
        ]);
    }

    private function geocode(Request $request): JsonResponse
    {
        $lat = $request->input('lat');
        $lng = $request->input('lng');
        if ($lat === null || $lat === '' || $lng === null || $lng === '') {
            return response()->json(['status' => 'error', 'message' => 'Latitude and Longitude are required']);
        }

        $url = 'https://maps.googleapis.com/maps/api/geocode/json'
            .'?latlng='.urlencode($lat.','.$lng)
            .'&key='.$this->key()
            .'&result_type=street_address|premise|route|intersection|political|neighborhood';

        $json = $this->google($url);
        if (($json['status'] ?? '') !== 'OK' || empty($json['results'])) {
            return response()->json([
                'status' => 'error',
                'message' => 'Failed to geocode location',
                'google_status' => $json['status'] ?? 'UNKNOWN',
            ]);
        }

        return response()->json([
            'status' => 'success',
            'address' => $json['results'][0]['formatted_address'] ?? '',
        ]);
    }

    /** Plain curl so no extra composer packages are needed on the server. */
    private function google(string $url): array
    {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 12);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        $response = curl_exec($ch);
        curl_close($ch);

        if ($response === false) {
            return ['status' => 'CURL_ERROR'];
        }

        $json = json_decode((string) $response, true);

        return is_array($json) ? $json : ['status' => 'BAD_JSON'];
    }
}
