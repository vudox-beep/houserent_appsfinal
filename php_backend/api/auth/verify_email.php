<?php
require_once '../db.php';

if (!isset($_GET['token']) || empty($_GET['token'])) {
    die("Invalid or missing verification token.");
}

$token = $_GET['token'];

try {
    // Check if token exists and is valid
    $stmt = $conn->prepare("SELECT id, email, token_expiry FROM users WHERE verification_token = ?");
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        die("Invalid verification token. It may have already been used or doesn't exist.");
    }

    $expiry = strtotime($user['token_expiry']);
    if (time() > $expiry) {
        die("Verification token has expired. Please request a new one.");
    }

    // Mark as verified
    $updateStmt = $conn->prepare("UPDATE users SET is_verified = 1, verification_token = NULL, token_expiry = NULL WHERE id = ?");
    if ($updateStmt->execute([$user['id']])) {
        echo "<h2>Email successfully verified!</h2>";
        echo "<p>You can now log in to the HouseRent Africa app.</p>";
    } else {
        echo "<h2>Error verifying email.</h2>";
        echo "<p>Please try again or contact support.</p>";
    }

} catch (Exception $e) {
    die("Server error: " . $e->getMessage());
}
?>