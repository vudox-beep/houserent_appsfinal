<?php 
 header('Content-Type: application/json'); 
 header('Access-Control-Allow-Origin: *'); 
 header('Access-Control-Allow-Methods: POST, GET, OPTIONS'); 
 header('Access-Control-Allow-Headers: Content-Type, Authorization'); 

 require_once '../db.php';
require_once '../auth.php';

// First try to get the user ID from the auth token
$user = null;
try {
    if (function_exists('verifyToken')) {
        $user = verifyToken();
    }
} catch (Exception $e) {
    // Ignore token errors
}
$user_id = $user ? $user['id'] : null;

try {
    // Create favorites table if it doesn't exist
    $conn->exec("CREATE TABLE IF NOT EXISTS favorites (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        property_id INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY user_prop (user_id, property_id)
    )");
} catch(PDOException $e) {
    echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
    exit;
}

 $data = json_decode(file_get_contents("php://input"), true);
 if (!$data) $data = $_POST;
 if (!$data) $data = $_GET;

 $action = $data['action'] ?? '';
 
 // If token didn't provide user_id, fallback to request body
 if (!$user_id) {
     $user_id = $data['user_id'] ?? '';
 }

 // Debug logging to see exactly what we're receiving
 file_put_contents('debug.log', "Action: $action, UserID: $user_id, TokenUser: " . print_r($user, true) . ", Data: " . print_r($data, true) . ", POST: " . print_r($_POST, true) . "\n", FILE_APPEND);

 if (empty($user_id)) {
     echo json_encode(['status' => 'error', 'message' => 'User ID is required']);
     exit;
 } 
 
 try { 
     if ($action === 'toggle') { 
         // --- ADD OR REMOVE FROM FAVORITES --- 
         $property_id = $data['property_id'] ?? ''; 
         
         if (empty($property_id)) { 
             echo json_encode(['status' => 'error', 'message' => 'Property ID is required']); 
             exit; 
         } 
 
         // Check if it already exists
        $stmt = $conn->prepare("SELECT id FROM favorites WHERE user_id = ? AND property_id = ?");
        $stmt->execute([$user_id, $property_id]);
        $exists = $stmt->fetch();

        if ($exists) { 
            // Remove from favorites
            $del = $conn->prepare("DELETE FROM favorites WHERE user_id = ? AND property_id = ?");
            $del->execute([$user_id, $property_id]);
            echo json_encode(['status' => 'success', 'message' => 'Removed from favorites', 'is_favorite' => false]);
        } else {
            // Add to favorites
            $ins = $conn->prepare("INSERT INTO favorites (user_id, property_id) VALUES (?, ?)");
            $ins->execute([$user_id, $property_id]);
            echo json_encode(['status' => 'success', 'message' => 'Added to favorites', 'is_favorite' => true]);
        } 
     } 
     elseif ($action === 'get_all') {
        // --- GET ALL FAVORITE PROPERTIES FOR A USER ---
        $stmt = $conn->prepare("
            SELECT p.*, f.created_at as favorited_at
            FROM favorites f
            JOIN properties p ON f.property_id = p.id
            WHERE f.user_id = ?
            ORDER BY f.created_at DESC
        ");
        $stmt->execute([$user_id]);
        $properties = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $result = [];
        $site_url = 'https://houseforrent.site/php_backend/api';

        // Fetch images for each property
        foreach ($properties as $prop) {
            $imgStmt = $conn->prepare("SELECT image_path, is_main FROM property_images WHERE property_id = ?");
            $imgStmt->execute([$prop['id']]);
            $images = $imgStmt->fetchAll(PDO::FETCH_ASSOC);

            $main_image = null;
            $formatted_images = [];

            foreach ($images as $img) {
                $img_url = ltrim($img['image_path'], '/');
                
                if (strpos($img_url, 'http') !== 0) {
                    // First, strip off any existing "assets/" or "php_backend/" from the raw db string to avoid double mapping
                    $clean_path = preg_replace('/^(assets\/|php_backend\/api\/|uploads\/)/', '', $img_url);
                    
                    // Now FORCE the single source of truth URL directly to the outside assets folder
                    $img_url = 'https://houseforrent.site/assets/' . $clean_path;
                }

                if ($img['is_main'] == 1 && !$main_image) {
                    $main_image = $img_url;
                }
                
                $formatted_images[] = $img_url;
            }

            // Fallback to first image if no main image
            if (!$main_image && count($formatted_images) > 0) {
                $main_image = $formatted_images[0];
            }

            // Just provide array of images to match flutter expectations
            $prop['images'] = $formatted_images;
            $prop['main_image'] = $main_image;

            $result[] = $prop;
        }

        echo json_encode([
            'status' => 'success',
            'data' => $result
        ]);
    } 
     elseif ($action === 'check') {
        // --- CHECK IF A SPECIFIC PROPERTY IS FAVORITED ---
        $property_id = $data['property_id'] ?? '';
        
        if (empty($property_id)) {
            echo json_encode(['status' => 'error', 'message' => 'Property ID is required']);
            exit;
        }

        $stmt = $conn->prepare("SELECT id FROM favorites WHERE user_id = ? AND property_id = ?");
        $stmt->execute([$user_id, $property_id]);
        $exists = $stmt->fetch();

        echo json_encode([
            'status' => 'success',
            'is_favorite' => $exists ? true : false
        ]);
    } 
     else { 
         echo json_encode(['status' => 'error', 'message' => 'Invalid action']); 
     } 
 
 } catch (PDOException $e) { 
     echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]); 
 }
