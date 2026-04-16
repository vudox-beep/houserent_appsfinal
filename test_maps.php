<?php
$ch = curl_init("https://houseforrent.site/php_backend/api/maps.php");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HEADER, true);
$response = curl_exec($ch);
echo $response;
?>