<?php
/**
 * Lightweight SMTP client with retries for SpaceMail / shared hosting.
 * Failures under traffic are usually connection limits or brief SMTP refusals.
 */
class SimpleSMTP {
    private $host;
    private $port;
    private $user;
    private $pass;
    private $localhost = 'localhost';
    private $timeout = 20;
    private $maxAttempts = 3;

    public function __construct($host, $port, $user, $pass) {
        $this->host = $host;
        $this->port = (int) $port;
        $this->user = $user;
        $this->pass = $pass;
        if (!empty($_SERVER['SERVER_NAME'])) {
            $this->localhost = preg_replace('/[^A-Za-z0-9.\-]/', '', (string) $_SERVER['SERVER_NAME']) ?: 'localhost';
        }
    }

    public function send($to, $subject, $body, $fromName) {
        $lastError = '';
        for ($attempt = 1; $attempt <= $this->maxAttempts; $attempt++) {
            try {
                if ($this->sendOnce($to, $subject, $body, $fromName)) {
                    return true;
                }
            } catch (Exception $e) {
                $lastError = $e->getMessage();
                error_log('SimpleSMTP attempt ' . $attempt . ' failed: ' . $lastError);
            }

            if ($attempt < $this->maxAttempts) {
                usleep(400000 * $attempt);
            }
        }

        if ($lastError !== '') {
            error_log('SimpleSMTP gave up for ' . $to . ': ' . $lastError);
        }
        return false;
    }

    private function sendOnce($to, $subject, $body, $fromName) {
        $errno = 0;
        $errstr = '';
        $socket = @fsockopen($this->host, $this->port, $errno, $errstr, $this->timeout);
        if (!$socket) {
            throw new Exception("Connect failed ({$errno}): {$errstr}");
        }

        stream_set_timeout($socket, $this->timeout);

        try {
            $this->expect($socket, '220');

            $this->cmd($socket, 'EHLO ' . $this->localhost);
            $this->expect($socket, '250');

            if ($this->port !== 465) {
                $this->cmd($socket, 'STARTTLS');
                $this->expect($socket, '220');

                $crypto = STREAM_CRYPTO_METHOD_TLS_CLIENT;
                if (defined('STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT')) {
                    $crypto = STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT;
                }
                if (!@stream_socket_enable_crypto($socket, true, $crypto)) {
                    throw new Exception('TLS handshake failed');
                }

                $this->cmd($socket, 'EHLO ' . $this->localhost);
                $this->expect($socket, '250');
            }

            $this->cmd($socket, 'AUTH LOGIN');
            $this->expect($socket, '334');
            $this->cmd($socket, base64_encode($this->user));
            $this->expect($socket, '334');
            $this->cmd($socket, base64_encode($this->pass));
            $this->expect($socket, '235');

            $this->cmd($socket, 'MAIL FROM: <' . $this->user . '>');
            $this->expect($socket, '250');

            $this->cmd($socket, 'RCPT TO: <' . $to . '>');
            $this->expect($socket, '250');

            $this->cmd($socket, 'DATA');
            $this->expect($socket, '354');

            $safeFrom = str_replace(["\r", "\n"], '', (string) $fromName);
            $safeSubject = str_replace(["\r", "\n"], '', (string) $subject);
            $headers  = "MIME-Version: 1.0\r\n";
            $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
            $headers .= 'Date: ' . date('r') . "\r\n";
            $headers .= 'From: ' . $safeFrom . ' <' . $this->user . ">\r\n";
            $headers .= 'To: <' . $to . ">\r\n";
            $headers .= 'Subject: ' . $safeSubject . "\r\n";
            $headers .= 'Reply-To: ' . $safeFrom . ' <' . $this->user . ">\r\n";
            $headers .= 'Message-ID: <' . md5(uniqid((string) microtime(true), true)) . '@' . $this->localhost . ">\r\n";
            $headers .= "X-Mailer: HouseRentMailer\r\n";
            $headers .= "X-Priority: 3\r\n";

            $normalizedBody = str_replace(["\r\n", "\r"], "\n", (string) $body);
            $normalizedBody = str_replace("\n", "\r\n", $normalizedBody);
            $normalizedBody = preg_replace('/^\./m', '..', $normalizedBody);

            fwrite($socket, $headers . "\r\n" . $normalizedBody . "\r\n.\r\n");
            $this->expect($socket, '250');

            $this->cmd($socket, 'QUIT');
            fclose($socket);
            return true;
        } catch (Exception $e) {
            fclose($socket);
            throw $e;
        }
    }

    private function cmd($socket, $line) {
        if (fwrite($socket, $line . "\r\n") === false) {
            throw new Exception('Failed writing to SMTP socket');
        }
    }

    private function expect($socket, $code) {
        $response = '';
        while (($line = fgets($socket, 515)) !== false) {
            $response .= $line;
            if (isset($line[3]) && $line[3] === ' ') {
                break;
            }
            $meta = stream_get_meta_data($socket);
            if (!empty($meta['timed_out'])) {
                throw new Exception('SMTP read timed out');
            }
        }

        if ($response === '' || substr($response, 0, 3) !== (string) $code) {
            throw new Exception('Expected SMTP ' . $code . ', got: ' . trim($response));
        }
    }
}
?>
