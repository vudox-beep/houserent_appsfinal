<?php
require 'e:/my work/houserent africa/flutter_application_1/houserent/php_backend/api/db.php';
$stmt = $conn->query('SELECT * FROM rentals');
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
