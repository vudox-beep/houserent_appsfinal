<?php
$host = "localhost";
$db_name = "atphieleqa_house";
$username = "root";
$password = "";

try {
    $conn = new PDO("mysql:host=" . $host . ";dbname=" . $db_name, $username, $password);
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $conn->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    
    $stmt = $conn->query("SELECT id, image_path FROM property_images ORDER BY id DESC LIMIT 5");
    $images = $stmt->fetchAll(PDO::FETCH_ASSOC);
    print_r($images);
    
} catch(PDOException $exception) {
    echo "Connection error: " . $exception->getMessage();
}
?>