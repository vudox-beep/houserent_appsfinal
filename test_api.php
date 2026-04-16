<?php
$ch = curl_init('https://houseforrent.site/php_backend/api/properties/index.php');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$result = curl_exec($ch);
curl_close($ch);

$data = json_decode($result, true);
if (isset($data['data'])) {
    foreach (array_slice($data['data'], 0, 5) as $prop) {
        echo "ID: " . $prop['id'] . "\n";
        echo "Main Image: " . $prop['main_image'] . "\n";
        echo "All Images: \n";
        foreach ($prop['images'] as $img) {
            echo "  - " . $img['url'] . "\n";
        }
        echo "----------------------\n";
    }
}
?>