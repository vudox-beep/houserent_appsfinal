<?php
$_SERVER['REQUEST_METHOD'] = 'POST';
$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer dummy';
// Mock apache_request_headers
function apache_request_headers() {
    return ['Authorization' => $_SERVER['HTTP_AUTHORIZATION']];
}
require 'e:/my work/houserent africa/flutter_application_1/houserent/php_backend/api/dealer/tenants/add_tenant.php';
