<?php
require 'php_backend/api/db.php';
$db = new Database();
$conn = $db->connect();
$stmt = $conn->query("SELECT amount, status, message FROM transactions LIMIT 10");
if ($stmt) print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
?>