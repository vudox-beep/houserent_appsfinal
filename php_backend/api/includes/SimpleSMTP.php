<?php
class SimpleSMTP {
    private $host;
    private $port;
    private $user;
    private $pass;
    private $timeout;

    public function __construct($host, $port, $user, $pass, $timeout = 30) {
        $this->host = $host;
        $this->port = $port;
        $this->user = $user;
        $this->pass = $pass;
        $this->timeout = $timeout;
    }

    public function send($to, $subject, $body, $fromName = 'Admin', $fromEmail = null) {
        if (!$fromEmail) {
            $fromEmail = $this->user;
        }

        $socket = fsockopen(($this->port == 465 ? 'ssl://' : '') . $this->host, $this->port, $errno, $errstr, $this->timeout);
        if (!$socket) {
            error_log("SMTP Connection failed: $errstr ($errno)");
            return false;
        }

        $this->readResponse($socket);

        $this->sendCommand($socket, "EHLO " . $_SERVER['SERVER_NAME']);
        
        if ($this->port == 587 || $this->port == 25 || $this->port == 465) {
            $this->sendCommand($socket, "AUTH LOGIN");
            $this->sendCommand($socket, base64_encode($this->user));
            $this->sendCommand($socket, base64_encode($this->pass));
        }

        $this->sendCommand($socket, "MAIL FROM: <$fromEmail>");
        $this->sendCommand($socket, "RCPT TO: <$to>");
        $this->sendCommand($socket, "DATA");

        $headers = "From: $fromName <$fromEmail>\r\n";
        $headers .= "To: <$to>\r\n";
        $headers .= "Subject: $subject\r\n";
        $headers .= "MIME-Version: 1.0\r\n";
        $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
        $headers .= "\r\n";

        $message = $headers . $body . "\r\n.\r\n";
        fwrite($socket, $message);
        $this->readResponse($socket);

        $this->sendCommand($socket, "QUIT");
        fclose($socket);

        return true;
    }

    private function sendCommand($socket, $command) {
        fwrite($socket, $command . "\r\n");
        return $this->readResponse($socket);
    }

    private function readResponse($socket) {
        $response = "";
        while ($line = fgets($socket, 515)) {
            $response .= $line;
            if (substr($line, 3, 1) == " ") {
                break;
            }
        }
        return $response;
    }
}
?>
