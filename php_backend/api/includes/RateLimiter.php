<?php
class RateLimiter {
    private $limit;
    private $timeframe;
    private $storageDir;

    public function __construct($limit = 10, $timeframe = 60) {
        $this->limit = $limit;
        $this->timeframe = $timeframe;
        // Use a directory inside the project to avoid sys_get_temp_dir() permission issues on live servers (like LiteSpeed/cPanel)
        $this->storageDir = __DIR__ . '/rate_limits';
        
        if (!is_dir($this->storageDir)) {
            @mkdir($this->storageDir, 0777, true);
        }
    }

    public function check($identifier) {
        $file = $this->storageDir . '/' . md5($identifier) . '.json';
        $now = time();
        $timestamps = [];

        if (file_exists($file)) {
            $content = file_get_contents($file);
            if ($content !== false) {
                $data = json_decode($content, true);
                if (is_array($data)) {
                    $timestamps = $data;
                }
            }
        }

        // Sliding window: filter out timestamps older than the timeframe
        $validTimestamps = [];
        foreach ($timestamps as $ts) {
            if ($now - $ts < $this->timeframe) {
                $validTimestamps[] = $ts;
            }
        }

        if (count($validTimestamps) >= $this->limit) {
            return false; // Rate limit exceeded
        }

        // Add current request timestamp
        $validTimestamps[] = $now;
        @file_put_contents($file, json_encode($validTimestamps));
        
        return true;
    }
}
?>