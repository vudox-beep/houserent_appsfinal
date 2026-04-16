<?php
class LencoAPI {
    private $apiKey;
    private $baseUrl = "https://api.lenco.co/v1"; // Example baseUrl for Lenco, update if necessary

    public function __construct() {
        // You should store this securely, e.g., in a config file or environment variables
        $this->apiKey = defined('LENCO_API_KEY') ? LENCO_API_KEY : 'YOUR_DEFAULT_LENCO_API_KEY'; 
    }

    public function initiateMobileMoney($amount, $currency, $phone, $operator, $country = 'zm') {
        $url = $this->baseUrl . "/collections/mobile-money";
        $data = [
            'amount' => $amount,
            'currency' => $currency,
            'phone' => $phone,
            'operator' => $operator,
            'country' => $country,
            'reference' => 'SUB-' . uniqid() . '-' . time()
        ];

        return $this->makeRequest('POST', $url, $data);
    }

    public function verifyTransaction($reference) {
        $url = $this->baseUrl . "/transactions/" . $reference;
        return $this->makeRequest('GET', $url);
    }

    private function makeRequest($method, $url, $data = null) {
        $ch = curl_init();

        $headers = [
            'Authorization: Bearer ' . $this->apiKey,
            'Content-Type: application/json',
            'Accept: application/json'
        ];

        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

        if ($method === 'POST') {
            curl_setopt($ch, CURLOPT_POST, true);
            if ($data) {
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
            }
        }

        $response = curl_exec($ch);
        $err = curl_error($ch);
        curl_close($ch);

        if ($err) {
            return ['status' => false, 'message' => 'cURL Error: ' . $err];
        } else {
            return json_decode($response, true);
        }
    }
}
?>