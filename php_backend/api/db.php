<?php
// db.php
$host = "localhost";
$db_name = "atphieleqa_house";
$username = "root";
$password = "";

try {
    $conn = new PDO("mysql:host=" . $host . ";dbname=" . $db_name . ";charset=utf8mb4", $username, $password);
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $conn->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    $conn->exec("SET NAMES utf8mb4");
} catch(PDOException $exception) {
    echo json_encode(["message" => "Connection error: " . $exception->getMessage()]);
    exit();
}
?>