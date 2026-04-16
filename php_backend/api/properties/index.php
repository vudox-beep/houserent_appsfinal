<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    if (isset($_GET['id'])) {
        // Get single property
        try {
            $stmt = $conn->prepare("
                SELECT p.*, u.name as dealer_name, u.phone as dealer_phone, u.email as dealer_email
                FROM properties p
                JOIN users u ON p.dealer_id = u.id
                JOIN dealers d ON d.user_id = p.dealer_id
                WHERE p.id = ?
                  AND d.subscription_status = 'active'
                  AND d.subscription_expiry IS NOT NULL
                  AND d.subscription_expiry <> '0000-00-00 00:00:00'
                  AND d.subscription_expiry >= NOW()
            ");
            $stmt->execute([$_GET['id']]);
            
            if ($stmt->rowCount() == 0) {
                http_response_code(404);
                echo json_encode(["message" => "Property not found"]);
                exit();
            }

            $property = $stmt->fetch();
            
            $imgStmt = $conn->prepare("SELECT id, image_path as url, is_main FROM property_images WHERE property_id = ?");
            $imgStmt->execute([$property['id']]);
            $images = $imgStmt->fetchAll(PDO::FETCH_ASSOC);
            
            $main_image = null;
            $formatted_images = [];
            
            foreach ($images as $img) {
                // Ensure full URL formatting
                $img_url = trim($img['url']);
                $img_url = str_replace('`', '', $img_url); // Clean any backticks
                $img_url = ltrim($img_url, '/');
                
                if (strpos($img_url, 'http') !== 0) {
                    // First, strip off any existing "assets/" or "php_backend/" from the raw db string to avoid double mapping
                    $clean_path = preg_replace('/^(assets\/|php_backend\/api\/|uploads\/)/', '', $img_url);
                    
                    // Now FORCE the single source of truth URL directly to the outside assets folder
                    $img_url = 'https://houseforrent.site/assets/' . $clean_path;
                }
                
                $img['url'] = $img_url;
                
                if ($img['is_main'] == 1 && !$main_image) {
                    $main_image = $img_url;
                }
                
                $formatted_images[] = $img;
            }
            
            if (!$main_image && count($formatted_images) > 0) {
                $main_image = $formatted_images[0]['url'];
            }
            
            // Clean the main image URL one last time just to be safe
            if ($main_image) {
                $main_image = trim(str_replace('`', '', $main_image));
            }
            
            $property['images'] = $formatted_images;
            $property['main_image'] = $main_image;
            
            // Preserve the video URL if it exists, format it to be a full URL if needed
            if (!empty($property['video_url']) && strpos($property['video_url'], 'http') !== 0) {
                $clean_vid_path = preg_replace('/^(assets\/|php_backend\/api\/|uploads\/)/', '', $property['video_url']);
                $property['video_url'] = 'https://houseforrent.site/assets/' . ltrim($clean_vid_path, '/');
            }

            echo json_encode(["status" => "success", "data" => [$property]]);
        } catch (Exception $e) {
            http_response_code(500);
            echo json_encode(["message" => "Server error"]);
        }
    } else {
        // Get all properties with filters
        try {
            $query = "
                SELECT p.*, u.name as dealer_name, u.phone as dealer_phone, u.email as dealer_email
                FROM properties p
                JOIN users u ON p.dealer_id = u.id
                JOIN dealers d ON d.user_id = p.dealer_id
                WHERE p.status = 'available'
                  AND d.subscription_status = 'active'
                  AND d.subscription_expiry IS NOT NULL
                  AND d.subscription_expiry <> '0000-00-00 00:00:00'
                  AND d.subscription_expiry >= NOW()
            ";
            $params = [];

            if (isset($_GET['location'])) {
                $query .= " AND p.city LIKE ?";
                $params[] = "%" . $_GET['location'] . "%";
            }
            if (isset($_GET['minPrice'])) {
                $query .= " AND p.price >= ?";
                $params[] = $_GET['minPrice'];
            }
            if (isset($_GET['maxPrice'])) {
                $query .= " AND p.price <= ?";
                $params[] = $_GET['maxPrice'];
            }
            if (isset($_GET['type'])) {
                $query .= " AND p.property_type = ?";
                $params[] = $_GET['type'];
            }
            if (isset($_GET['purpose'])) {
                $query .= " AND p.listing_purpose = ?";
                $params[] = $_GET['purpose'];
            }
            if (isset($_GET['featured'])) {
                // Cast to integer safely, 1 is featured, 0 is not
                $featuredVal = (int)$_GET['featured'];
                $query .= " AND p.is_featured = ?";
                $params[] = $featuredVal;
            }
            if (isset($_GET['bedrooms'])) {
                $query .= " AND p.bedrooms >= ?";
                $params[] = $_GET['bedrooms'];
            }
            if (isset($_GET['dealer_id'])) {
                $query .= " AND p.dealer_id = ?";
                $params[] = $_GET['dealer_id'];
            }

            $query .= " ORDER BY p.created_at DESC";

            $stmt = $conn->prepare($query);
            $stmt->execute($params);
            $properties = $stmt->fetchAll(PDO::FETCH_ASSOC);

            foreach ($properties as &$prop) {
                $imgStmt = $conn->prepare("SELECT id, image_path as url, is_main FROM property_images WHERE property_id = ?");
                $imgStmt->execute([$prop['id']]);
                $images = $imgStmt->fetchAll(PDO::FETCH_ASSOC);
                
                $main_image = null;
                $formatted_images = [];
                
                foreach ($images as $img) {
                    // Ensure full URL formatting
                    $img_url = trim($img['url']);
                    $img_url = str_replace('`', '', $img_url); // Clean any backticks
                    $img_url = ltrim($img_url, '/');
                    
                    if (strpos($img_url, 'http') !== 0) {
                        // The frontend needs the EXACT path to the outside assets folder
                        // First, strip off any existing "assets/" or "php_backend/" from the raw db string to avoid double mapping
                        $clean_path = preg_replace('/^(assets\/|php_backend\/api\/|uploads\/)/', '', $img_url);
                        
                        // Now FORCE the single source of truth URL directly to the outside assets folder
                        $img_url = 'https://houseforrent.site/assets/' . $clean_path;
                    }
                    
                    $img['url'] = $img_url;
                    
                    if ($img['is_main'] == 1 && !$main_image) {
                        $main_image = $img_url;
                    }
                    
                    $formatted_images[] = $img;
                }
                
                if (!$main_image && count($formatted_images) > 0) {
                    $main_image = $formatted_images[0]['url'];
                }
                
                // Clean the main image URL one last time just to be safe
                if ($main_image) {
                    $main_image = trim(str_replace('`', '', $main_image));
                }
                
                $prop['images'] = $formatted_images;
                $prop['main_image'] = $main_image;
                
                // Preserve the video URL if it exists; format it to be a full URL if needed
                if (!empty($prop['video_url']) && strpos($prop['video_url'], 'http') !== 0) {
                    $clean_vid_path = preg_replace('/^(assets\/|php_backend\/api\/|uploads\/)/', '', $prop['video_url']);
                    $prop['video_url'] = 'https://houseforrent.site/assets/' . ltrim($clean_vid_path, '/');
                }
            }

            echo json_encode(["status" => "success", "data" => $properties]);
        } catch (Exception $e) {
            http_response_code(500);
            echo json_encode(["message" => "Server error"]);
        }
    }
} elseif ($method === 'POST') {
    $user = authorize(['dealer', 'admin']);
    
    // Check if it's multipart/form-data for file uploads
    $title = $_POST['title'] ?? '';
    $description = $_POST['description'] ?? '';
    $price = $_POST['price'] ?? 0;
    $bedrooms = $_POST['bedrooms'] ?? 0;
    $bathrooms = $_POST['bathrooms'] ?? 0;
    $property_type = $_POST['property_type'] ?? 'house';
    $location = $_POST['location'] ?? '';
    $city = $_POST['city'] ?? '';
    $country = $_POST['country'] ?? '';

    try {
        $stmt = $conn->prepare("
            INSERT INTO properties (dealer_id, title, description, price, bedrooms, bathrooms, property_type, location, city, country)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute([$user['id'], $title, $description, $price, $bedrooms, $bathrooms, $property_type, $location, $city, $country]);
        $propertyId = $conn->lastInsertId();

        // Handle file uploads (simplified)
        if (!empty($_FILES['images']['name'][0])) {
            $uploadDir = '../uploads/';
            if (!is_dir($uploadDir)) {
                mkdir($uploadDir, 0777, true);
            }

            foreach ($_FILES['images']['tmp_name'] as $key => $tmp_name) {
                $fileName = time() . '-' . basename($_FILES['images']['name'][$key]);
                $targetFilePath = $uploadDir . $fileName;

                if (move_uploaded_file($tmp_name, $targetFilePath)) {
                    $imgStmt = $conn->prepare("INSERT INTO property_images (property_id, image_path, type) VALUES (?, ?, 'image')");
                    // Store relative path
                    $imgStmt->execute([$propertyId, 'uploads/' . $fileName]);
                }
            }
        }

        http_response_code(201);
        echo json_encode(["message" => "Property created", "propertyId" => $propertyId]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error"]);
    }
} elseif ($method === 'PUT') {
    $user = authorize(['dealer', 'admin']);
    $data = json_decode(file_get_contents("php://input"));
    $id = $_GET['id'] ?? null;

    if (!$id) {
        http_response_code(400);
        echo json_encode(["message" => "Property ID required"]);
        exit();
    }

    try {
        $stmt = $conn->prepare("SELECT dealer_id FROM properties WHERE id = ?");
        $stmt->execute([$id]);
        $prop = $stmt->fetch();

        if (!$prop) {
            http_response_code(404);
            echo json_encode(["message" => "Not found"]);
            exit();
        }

        if ($prop['dealer_id'] != $user['id'] && $user['role'] !== 'admin') {
            http_response_code(403);
            echo json_encode(["message" => "Unauthorized"]);
            exit();
        }

        $stmt = $conn->prepare("UPDATE properties SET title=?, description=?, price=? WHERE id=?");
        $stmt->execute([$data->title, $data->description, $data->price, $id]);
        echo json_encode(["message" => "Property updated"]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error"]);
    }
} elseif ($method === 'DELETE') {
    $user = authorize(['dealer', 'admin']);
    $id = $_GET['id'] ?? null;

    if (!$id) {
        http_response_code(400);
        echo json_encode(["message" => "Property ID required"]);
        exit();
    }

    try {
        $stmt = $conn->prepare("SELECT dealer_id FROM properties WHERE id = ?");
        $stmt->execute([$id]);
        $prop = $stmt->fetch();

        if (!$prop) {
            http_response_code(404);
            echo json_encode(["message" => "Not found"]);
            exit();
        }

        if ($prop['dealer_id'] != $user['id'] && $user['role'] !== 'admin') {
            http_response_code(403);
            echo json_encode(["message" => "Unauthorized"]);
            exit();
        }

        $stmt = $conn->prepare("DELETE FROM properties WHERE id = ?");
        $stmt->execute([$id]);
        echo json_encode(["message" => "Property removed"]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error"]);
    }
} else {
    http_response_code(405);
}
?>
