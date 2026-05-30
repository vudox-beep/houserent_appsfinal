<?php
require 'php_backend/api/db.php';
try {
$db = new Database();
$conn = $db->connect();
$stmt = $conn->query("SHOW COLUMNS FROM users");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
$stmt2 = $conn->query("SHOW TABLES");
print_r($stmt2->fetchAll(PDO::FETCH_COLUMN));
} catch(Exception $e) { echo $e->getMessage(); }
?>