<?php 
require 'php_backend/api/db.php'; 
$db = new Database();
$conn = $db->connect();
print_r($conn->query('SELECT COUNT(*) FROM payments')->fetchAll(PDO::FETCH_ASSOC)); 
?>
