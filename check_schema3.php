<?php
require 'php_backend/api/db.php';
$db = new Database();
$conn = $db->connect();
$stmt = $conn->query("SELECT DISTINCT status FROM transactions");
print_r($stmt->fetchAll(PDO::FETCH_COLUMN));
?>