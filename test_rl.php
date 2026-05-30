<?php
require 'php_backend/api/includes/RateLimiter.php';
$rl = new RateLimiter(5, 60);
for($i=1; $i<=6; $i++) {
    echo 'Try '.$i.': '.($rl->check('test_user_new') ? 'Pass' : 'Fail')."\n";
}
