<?php
require 'php_backend/api/db.php';
global $conn;
$stmt = $conn->query("DESCRIBE users");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
?>
