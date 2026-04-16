<?php
require_once '../db.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $token = $_POST['token'] ?? '';
    $password = $_POST['password'] ?? '';
    $confirm_password = $_POST['confirm_password'] ?? '';

    if (empty($token) || empty($password) || $password !== $confirm_password) {
        die("Invalid request or passwords do not match.");
    }

    // Check token
    $stmt = $conn->prepare("SELECT id, reset_expires FROM users WHERE reset_token = ?");
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user || time() > strtotime($user['reset_expires'])) {
        die("Invalid or expired reset token.");
    }

    $hashedPassword = password_hash($password, PASSWORD_BCRYPT);
    $upd = $conn->prepare("UPDATE users SET password = ?, reset_token = NULL, reset_expires = NULL WHERE id = ?");
    if ($upd->execute([$hashedPassword, $user['id']])) {
        echo "<h2>Password successfully reset!</h2>";
        echo "<p>You can now log in to the HouseRent Africa app with your new password.</p>";
    } else {
        echo "<h2>Error resetting password.</h2>";
    }
    exit;
}

$token = $_GET['token'] ?? '';
if (empty($token)) {
    die("Missing token.");
}

// Verify token validity for the GET request
$stmt = $conn->prepare("SELECT id, reset_expires FROM users WHERE reset_token = ?");
$stmt->execute([$token]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user || time() > strtotime($user['reset_expires'])) {
    die("Invalid or expired reset token.");
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Reset Password - HouseRent Africa</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f4f4f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .container { background: #fff; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); width: 100%; max-width: 400px; }
        h2 { text-align: center; color: #333; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; color: #666; }
        input[type="password"] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 5px; box-sizing: border-box; }
        button { width: 100%; padding: 10px; background: #fbbf24; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; }
        button:hover { background: #f59e0b; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Reset Password</h2>
        <form method="POST" action="reset_password.php">
            <input type="hidden" name="token" value="<?php echo htmlspecialchars($token); ?>">
            <div class="form-group">
                <label>New Password</label>
                <input type="password" name="password" required>
            </div>
            <div class="form-group">
                <label>Confirm Password</label>
                <input type="password" name="confirm_password" required>
            </div>
            <button type="submit">Reset Password</button>
        </form>
    </div>
</body>
</html>