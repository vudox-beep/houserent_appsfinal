<?php
require 'php_backend/api/db.php';
$db = new Database();
$conn = $db->connect();
$stmt = $conn->query("SHOW COLUMNS FROM subscriptions");
if($stmt) print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
$stmt = $conn->query("SHOW COLUMNS FROM transactions");
if($stmt) print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
?>