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
        if ($this->isBlocked($identifier)) {
            return false; // Rate limit exceeded
        }
        $this->record($identifier);
        return true;
    }

    // True when the identifier already used up its attempts. Does NOT record.
    public function isBlocked($identifier) {
        return count($this->validTimestamps($identifier)) >= $this->limit;
    }

    // Records one attempt (call this only for FAILED logins so successful
    // sign-ins never lock people out).
    public function record($identifier) {
        $valid = $this->validTimestamps($identifier);
        $valid[] = time();
        @file_put_contents($this->fileFor($identifier), json_encode($valid));
    }

    // Wipes the counter, e.g. after a successful login.
    public function clear($identifier) {
        @unlink($this->fileFor($identifier));
    }

    private function fileFor($identifier) {
        return $this->storageDir . '/' . md5($identifier) . '.json';
    }

    private function validTimestamps($identifier) {
        $file = $this->fileFor($identifier);
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

        // Sliding window: keep only timestamps inside the timeframe
        $valid = [];
        foreach ($timestamps as $ts) {
            if ($now - $ts < $this->timeframe) {
                $valid[] = $ts;
            }
        }
        return $valid;
    }
}
?>