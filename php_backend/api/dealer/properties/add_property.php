<?php
ob_start();
ini_set('display_errors', 0);
error_reporting(E_ALL);

function json_response(array $payload, int $code = 200): void {
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

header('Content-Type: application/json'); 
header('Access-Control-Allow-Origin: *'); 
header('Access-Control-Allow-Methods: GET, POST'); 
header('Access-Control-Allow-Headers: Content-Type, Authorization'); 

require_once '../../db.php'; 
require_once '../../auth.php';

$user = verifyToken();
if (!$user || !isset($user['id'])) {
    json_response(['status' => 'error', 'message' => 'Unauthorized'], 401);
}
// Same upload/create flow for landlord (dealer), agent, and private company.
$role = strtolower(trim((string) ($user['role'] ?? '')));
if (!in_array($role, ['dealer', 'agent', 'company', 'admin'], true)) {
    json_response(['status' => 'error', 'message' => 'User role not authorized'], 403);
}
$dealer_id = $user['id'];

$rawInput = file_get_contents("php://input");
$data = [];
if (!empty($rawInput)) {
    $decoded = json_decode($rawInput, true);
    if (is_array($decoded)) {
        $data = $decoded;
    }
}
if (empty($data) && !empty($_POST)) $data = $_POST;
if (empty($data) && !empty($_GET)) $data = $_GET;

$action = $data['action'] ?? 'create_property'; 

if ($action === 'create_property') { 
    // --- CREATE PROPERTY --- 
    
    if (empty($data['title']) || empty($data['price']) || empty($data['location'])) { 
        json_response(['status' => 'error', 'message' => 'Title, Price, and Location are required.']); 
    } 

    // Determine auto-feature status based on subscription 
    $is_featured = 0; 
    try { 
        $checkPaid = $conn->prepare("SELECT COUNT(*) FROM transactions WHERE user_id = ? AND status = 'successful'"); 
        $checkPaid->execute([$dealer_id]); 
        if ($checkPaid->fetchColumn() > 0) { 
            $is_featured = 1; 
        } 
    } catch (Exception $e) {} 

    $propData = [ 
        'dealer_id' => $dealer_id, 
        'title' => htmlspecialchars($data['title']), 
        'description' => htmlspecialchars($data['description'] ?? ''), 
        'price' => floatval($data['price']), 
        'currency' => $data['currency'] ?? 'ZMW', 
        'property_type' => $data['property_type'] ?? 'house', 
        'listing_purpose' => $data['listing_purpose'] ?? 'rent', 
        'location' => htmlspecialchars($data['location']), 
        'city' => htmlspecialchars($data['city'] ?? ''), 
        'country' => htmlspecialchars($data['country'] ?? ''), 
        'latitude' => !empty($data['latitude']) ? floatval($data['latitude']) : null, 
        'longitude' => !empty($data['longitude']) ? floatval($data['longitude']) : null, 
        'status' => 'available', 
        'is_featured' => $is_featured, 
        'amenities' => htmlspecialchars($data['amenities'] ?? ''), 
        'video_url' => htmlspecialchars($data['video_url'] ?? ''), 
        'capacity' => null, 
        'people_per_room' => null, 
        'event_type' => null, 
        'catering_available' => 0, 
        'equipment_available' => 0,
        'verification_image' => null, 
        'is_verified' => 0 
    ]; 

    // Dynamic fields based on property type 
    $type = $propData['property_type']; 

    if ($type === 'House' || $type === 'Apartment' || $type === 'house' || $type === 'apartment') { 
        $propData['bedrooms'] = isset($data['bedrooms']) ? intval($data['bedrooms']) : null; 
        $propData['bathrooms'] = isset($data['bathrooms']) ? intval($data['bathrooms']) : null; 
    } elseif ($type === 'Boarding Houses' || $type === 'boarding_house') { 
        $propData['capacity'] = !empty($data['capacity']) ? intval($data['capacity']) : null; 
        $propData['people_per_room'] = !empty($data['people_per_room']) ? intval($data['people_per_room']) : null; 
    } elseif ($type === 'Wedding Lodges' || $type === 'Studios' || $type === 'event_space') { 
        $propData['capacity'] = !empty($data['capacity']) ? intval($data['capacity']) : null; 
        $propData['event_type'] = !empty($data['event_type']) ? htmlspecialchars($data['event_type']) : null; 
        $propData['catering_available'] = !empty($data['catering_available']) ? 1 : 0; 
        $propData['equipment_available'] = !empty($data['equipment_available']) ? 1 : 0; 
    } elseif ($type === 'Commercial' || $type === 'office' || $type === 'shop' || $type === 'warehouse') { 
        $propData['size_sqm'] = isset($data['size_sqm']) ? floatval($data['size_sqm']) : null; 
        $propData['rooms'] = isset($data['rooms']) ? intval($data['rooms']) : null; 
    } 

    try {
        $stmt = $conn->prepare("
            INSERT INTO properties (
                dealer_id, title, description, price, currency, bedrooms, bathrooms, rooms, size_sqm, 
                property_type, listing_purpose, location, city, country, latitude, longitude, 
                status, is_featured, amenities, video_url, capacity, people_per_room, event_type, 
                catering_available, equipment_available, is_verified
            ) VALUES (
                :dealer_id, :title, :description, :price, :currency, :bedrooms, :bathrooms, :rooms, :size_sqm, 
                :property_type, :listing_purpose, :location, :city, :country, :latitude, :longitude, 
                :status, :is_featured, :amenities, :video_url, :capacity, :people_per_room, :event_type, 
                :catering_available, :equipment_available, 0
            )
        ");

        $stmt->execute([
            ':dealer_id' => $dealer_id, 
            ':title' => $propData['title'], 
            ':description' => $propData['description'], 
            ':price' => $propData['price'], 
            ':currency' => $propData['currency'], 
            ':bedrooms' => $propData['bedrooms'] ?? null, 
            ':bathrooms' => $propData['bathrooms'] ?? null, 
            ':rooms' => $propData['rooms'] ?? null, 
            ':size_sqm' => $propData['size_sqm'] ?? null, 
            ':property_type' => $propData['property_type'], 
            ':listing_purpose' => $propData['listing_purpose'], 
            ':location' => $propData['location'], 
            ':city' => $propData['city'], 
            ':country' => $propData['country'], 
            ':latitude' => $propData['latitude'] ?? null, 
            ':longitude' => $propData['longitude'] ?? null, 
            ':status' => $propData['status'], 
            ':is_featured' => $propData['is_featured'], 
            ':amenities' => $propData['amenities'], 
            ':video_url' => $propData['video_url'], 
            ':capacity' => $propData['capacity'], 
            ':people_per_room' => $propData['people_per_room'], 
            ':event_type' => $propData['event_type'], 
            ':catering_available' => $propData['catering_available'], 
            ':equipment_available' => $propData['equipment_available']
        ]);

        $property_id = $conn->lastInsertId();

        $queuedNotification = false;
        if ($property_id) {
            try {
                $stmtCol = $conn->query("SHOW COLUMNS FROM properties LIKE 'emails_sent'");
                if ($stmtCol->rowCount() == 0) {
                    $conn->exec("ALTER TABLE properties ADD COLUMN emails_sent TINYINT(1) DEFAULT 1");
                    $conn->exec("UPDATE properties SET emails_sent = 1");
                }

                $stmtMark = $conn->prepare("UPDATE properties SET emails_sent = 0 WHERE id = ?");
                $stmtMark->execute([$property_id]);
                $queuedNotification = true;
            } catch (Exception $e) {
                $queuedNotification = false;
            }
        }

        if ($property_id) { 
            json_response([
                'status' => 'success', 
                'message' => 'Property created successfully.', 
                'property_id' => $property_id,
                'queued_email_notification' => $queuedNotification
            ]); 
        } else { 
            json_response(['status' => 'error', 'message' => 'Failed to create property.']); 
        }
    } catch (PDOException $e) {
        json_response(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
    }

} elseif ($action === 'update_property') {
    // --- UPDATE PROPERTY ---
    $property_id = $data['property_id'] ?? '';
    if (empty($property_id)) {
        json_response(['status' => 'error', 'message' => 'Property ID is required.']);
    }

    if (empty($data['title']) || empty($data['price']) || empty($data['location'])) {
        json_response(['status' => 'error', 'message' => 'Title, Price, and Location are required.']);
    }

    try {
        $verifyStmt = $conn->prepare("SELECT id FROM properties WHERE id = ? AND dealer_id = ?");
        $verifyStmt->execute([$property_id, $dealer_id]);
        if (!$verifyStmt->fetch()) {
            json_response(['status' => 'error', 'message' => 'Unauthorized']);
        }

        $type = $data['property_type'] ?? 'House';
        $isHouseLike = in_array($type, ['House', 'Apartment', 'house', 'apartment']);
        $isBoarding = in_array($type, ['Boarding Houses', 'boarding_house']);
        $isEvent = in_array($type, ['Wedding Lodges', 'Studios', 'event_space']);

        $bedrooms = $isHouseLike ? (isset($data['bedrooms']) ? intval($data['bedrooms']) : null) : null;
        $bathrooms = $isHouseLike ? (isset($data['bathrooms']) ? intval($data['bathrooms']) : null) : null;
        $rooms = ($isHouseLike || $isBoarding || !$isEvent) ? (isset($data['rooms']) ? intval($data['rooms']) : null) : null;
        $size_sqm = isset($data['size_sqm']) ? floatval($data['size_sqm']) : null;
        $capacity = ($isBoarding || $isEvent) ? (!empty($data['capacity']) ? intval($data['capacity']) : null) : null;
        $people_per_room = $isBoarding ? (!empty($data['people_per_room']) ? intval($data['people_per_room']) : null) : null;
        $event_type = $isEvent ? (!empty($data['event_type']) ? htmlspecialchars($data['event_type']) : null) : null;
        $catering_available = $isEvent && !empty($data['catering_available']) ? 1 : 0;
        $equipment_available = $isEvent && !empty($data['equipment_available']) ? 1 : 0;

        $stmt = $conn->prepare("
            UPDATE properties SET
                title = :title,
                description = :description,
                price = :price,
                currency = :currency,
                bedrooms = :bedrooms,
                bathrooms = :bathrooms,
                rooms = :rooms,
                size_sqm = :size_sqm,
                property_type = :property_type,
                listing_purpose = :listing_purpose,
                location = :location,
                city = :city,
                country = :country,
                latitude = :latitude,
                longitude = :longitude,
                amenities = :amenities,
                video_url = :video_url,
                capacity = :capacity,
                people_per_room = :people_per_room,
                event_type = :event_type,
                catering_available = :catering_available,
                equipment_available = :equipment_available
            WHERE id = :property_id AND dealer_id = :dealer_id
        ");

        $stmt->execute([
            ':title' => htmlspecialchars($data['title']),
            ':description' => htmlspecialchars($data['description'] ?? ''),
            ':price' => floatval($data['price']),
            ':currency' => $data['currency'] ?? 'ZMW',
            ':bedrooms' => $bedrooms,
            ':bathrooms' => $bathrooms,
            ':rooms' => $rooms,
            ':size_sqm' => $size_sqm,
            ':property_type' => $type,
            ':listing_purpose' => $data['listing_purpose'] ?? 'rent',
            ':location' => htmlspecialchars($data['location']),
            ':city' => htmlspecialchars($data['city'] ?? ''),
            ':country' => htmlspecialchars($data['country'] ?? ''),
            ':latitude' => !empty($data['latitude']) ? floatval($data['latitude']) : null,
            ':longitude' => !empty($data['longitude']) ? floatval($data['longitude']) : null,
            ':amenities' => htmlspecialchars($data['amenities'] ?? ''),
            ':video_url' => htmlspecialchars($data['video_url'] ?? ''),
            ':capacity' => $capacity,
            ':people_per_room' => $people_per_room,
            ':event_type' => $event_type,
            ':catering_available' => $catering_available,
            ':equipment_available' => $equipment_available,
            ':property_id' => $property_id,
            ':dealer_id' => $dealer_id
        ]);

        json_response(['status' => 'success', 'message' => 'Property updated successfully.']);
    } catch (PDOException $e) {
        json_response(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
    }
} elseif ($action === 'delete_property') {
    // --- DELETE PROPERTY ---
    $property_id = $data['property_id'] ?? '';
    if (empty($property_id)) {
        json_response(['status' => 'error', 'message' => 'Property ID is required.']);
    }

    try {
        $verifyStmt = $conn->prepare("SELECT id FROM properties WHERE id = ? AND dealer_id = ?");
        $verifyStmt->execute([$property_id, $dealer_id]);
        if (!$verifyStmt->fetch()) {
            json_response(['status' => 'error', 'message' => 'Unauthorized']);
        }

        $conn->beginTransaction();
        $conn->prepare("DELETE FROM property_images WHERE property_id = ?")->execute([$property_id]);
        $conn->prepare("DELETE FROM properties WHERE id = ? AND dealer_id = ?")->execute([$property_id, $dealer_id]);
        $conn->commit();

        json_response(['status' => 'success', 'message' => 'Property deleted successfully.']);
    } catch (PDOException $e) {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }
        json_response(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
    }
} elseif ($action === 'delete_property_image') {
    // --- DELETE ONE PROPERTY IMAGE (same shape Flutter already expects) ---
    $property_id = $data['property_id'] ?? ($_POST['property_id'] ?? '');
    $image_id = $data['image_id'] ?? ($_POST['image_id'] ?? '');
    if ($property_id === '' || $image_id === '') {
        json_response(['status' => 'error', 'message' => 'Property ID and image ID are required.']);
    }

    try {
        $verifyStmt = $conn->prepare("SELECT id FROM properties WHERE id = ? AND dealer_id = ?");
        $verifyStmt->execute([$property_id, $dealer_id]);
        if (!$verifyStmt->fetch()) {
            json_response(['status' => 'error', 'message' => 'Unauthorized']);
        }

        $imgStmt = $conn->prepare(
            "SELECT id, image_path, is_main FROM property_images WHERE id = ? AND property_id = ? LIMIT 1"
        );
        $imgStmt->execute([$image_id, $property_id]);
        $image = $imgStmt->fetch(PDO::FETCH_ASSOC);
        if (!$image) {
            json_response(['status' => 'error', 'message' => 'Image not found.']);
        }

        $conn->beginTransaction();
        $conn->prepare("DELETE FROM property_images WHERE id = ? AND property_id = ?")
            ->execute([$image_id, $property_id]);

        // If we removed the cover, promote the next remaining image.
        if ((int) ($image['is_main'] ?? 0) === 1) {
            $next = $conn->prepare(
                "SELECT id FROM property_images WHERE property_id = ? ORDER BY id ASC LIMIT 1"
            );
            $next->execute([$property_id]);
            $nextId = $next->fetchColumn();
            if ($nextId) {
                $conn->prepare("UPDATE property_images SET is_main = 1 WHERE id = ? AND property_id = ?")
                    ->execute([$nextId, $property_id]);
            }
        }
        $conn->commit();

        // Best-effort disk cleanup (do not fail the API if file is already gone).
        $rel = ltrim(str_replace('\\', '/', (string) ($image['image_path'] ?? '')), '/');
        if ($rel !== '' && strpos($rel, '..') === false) {
            $full = rtrim($_SERVER['DOCUMENT_ROOT'] ?? '', '/\\') . '/' . $rel;
            if (is_file($full)) {
                @unlink($full);
            }
        }

        json_response(['status' => 'success', 'message' => 'Image deleted successfully.']);
    } catch (PDOException $e) {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }
        json_response(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
    }
} elseif ($action === 'upload_property_images' || $action === 'replace_property_images') {
    // --- UPLOAD PROPERTY IMAGES & VIDEOS (concurrency-safe, same response shape) ---
    @set_time_limit(180);
    @ini_set('max_execution_time', '180');

    $property_id = $data['property_id'] ?? ($_POST['property_id'] ?? '');
    $replace_existing = $action === 'replace_property_images';

    if ($property_id === '') {
        json_response(['status' => 'error', 'message' => 'Property ID is required']);
    }

    // Verify dealer owns this property
    $verifyStmt = $conn->prepare("SELECT id FROM properties WHERE id = ? AND dealer_id = ?");
    $verifyStmt->execute([$property_id, $dealer_id]);
    if (!$verifyStmt->fetch()) {
        json_response(['status' => 'error', 'message' => 'Unauthorized']);
    }

    // Diagnose empty multipart (often post_max_size / upload_max_filesize under load).
    $contentLength = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
    $postMax = ini_get('post_max_size');
    if ((!isset($_FILES['images']) || empty($_FILES['images']['name'][0])) && $contentLength > 0 && empty($_POST)) {
        json_response([
            'status' => 'error',
            'message' => 'Upload too large for the server limit (post_max_size=' . $postMax
                . '). Please upload fewer/smaller photos at a time and try again.',
        ], 413);
    }

    if (!isset($_FILES['images']) || empty($_FILES['images']['name'][0])) {
        json_response(['status' => 'error', 'message' => 'No files provided. Add property photos and try again.']);
    }

    $documentRoot = rtrim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''), '/\\');
    $uploadDir = $documentRoot . '/assets/images/properties/';

    if ($documentRoot === '' || !is_dir($documentRoot . '/assets')) {
        $uploadDir = __DIR__ . '/../../../../assets/images/properties/';
    }

    if (!is_dir($uploadDir) && !@mkdir($uploadDir, 0755, true) && !is_dir($uploadDir)) {
        json_response(['status' => 'error', 'message' => 'Upload folder is not writable on the server.'], 500);
    }

    $uploadedFiles = [];
    $skipped = [];
    $allowedTypes = ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov'];
    $maxFileBytes = 12 * 1024 * 1024; // 12MB per file
    $maxFilesPerRequest = 5; // Clients should chunk; keeps concurrent uploads stable

    $names = $_FILES['images']['name'] ?? [];
    if (!is_array($names)) {
        // Single-file shape → normalize to array
        $_FILES['images'] = [
            'name' => [$_FILES['images']['name']],
            'type' => [$_FILES['images']['type']],
            'tmp_name' => [$_FILES['images']['tmp_name']],
            'error' => [$_FILES['images']['error']],
            'size' => [$_FILES['images']['size']],
        ];
        $names = $_FILES['images']['name'];
    }

    $fileCount = count($names);
    if ($fileCount > $maxFilesPerRequest) {
        json_response([
            'status' => 'error',
            'message' => 'Please upload at most ' . $maxFilesPerRequest
                . ' files per request. The app will send the rest automatically.',
        ], 422);
    }

    try {
        $conn->beginTransaction();

        // Lock property row so concurrent uploads don't race on is_main / replace.
        $lock = $conn->prepare("SELECT id FROM properties WHERE id = ? AND dealer_id = ? FOR UPDATE");
        $lock->execute([$property_id, $dealer_id]);
        if (!$lock->fetch()) {
            $conn->rollBack();
            json_response(['status' => 'error', 'message' => 'Unauthorized']);
        }

        if ($replace_existing) {
            $old = $conn->prepare("SELECT image_path FROM property_images WHERE property_id = ?");
            $old->execute([$property_id]);
            $oldPaths = $old->fetchAll(PDO::FETCH_COLUMN);
            $conn->prepare("DELETE FROM property_images WHERE property_id = ?")->execute([$property_id]);
            foreach ($oldPaths as $rel) {
                $rel = ltrim(str_replace('\\', '/', (string) $rel), '/');
                if ($rel === '' || strpos($rel, '..') !== false) {
                    continue;
                }
                $full = $documentRoot . '/' . $rel;
                if (is_file($full)) {
                    @unlink($full);
                }
            }
        }

        $hasMainStmt = $conn->prepare(
            "SELECT COUNT(*) FROM property_images WHERE property_id = ? AND is_main = 1"
        );
        $hasMainStmt->execute([$property_id]);
        $hasMain = ((int) $hasMainStmt->fetchColumn()) > 0;
        $is_main = $hasMain ? 0 : 1;

        $imgStmt = $conn->prepare(
            "INSERT INTO property_images (property_id, image_path, is_main) VALUES (?, ?, ?)"
        );
        $vidStmt = $conn->prepare("UPDATE properties SET video_url = ? WHERE id = ? AND dealer_id = ?");

        foreach ($_FILES['images']['tmp_name'] as $key => $tmp_name) {
            $err = (int) ($_FILES['images']['error'][$key] ?? UPLOAD_ERR_NO_FILE);
            $origName = (string) ($_FILES['images']['name'][$key] ?? ('file_' . $key));
            $size = (int) ($_FILES['images']['size'][$key] ?? 0);

            if ($err !== UPLOAD_ERR_OK) {
                $skipped[] = basename($origName) . ' (upload error ' . $err . ')';
                continue;
            }
            if ($size <= 0 || $size > $maxFileBytes) {
                $skipped[] = basename($origName) . ' (max 12MB)';
                continue;
            }
            if (!is_uploaded_file($tmp_name)) {
                $skipped[] = basename($origName) . ' (invalid upload)';
                continue;
            }

            $fileExt = strtolower(pathinfo($origName, PATHINFO_EXTENSION));
            if (!in_array($fileExt, $allowedTypes, true)) {
                $skipped[] = basename($origName) . ' (unsupported type)';
                continue;
            }

            $newName = 'prop_' . $property_id . '_' . bin2hex(random_bytes(8)) . '_' . time() . '.' . $fileExt;
            $targetPath = rtrim($uploadDir, '/\\') . DIRECTORY_SEPARATOR . $newName;

            if (!@move_uploaded_file($tmp_name, $targetPath)) {
                $skipped[] = basename($origName) . ' (could not save)';
                continue;
            }
            @chmod($targetPath, 0644);
            $dbPath = 'assets/images/properties/' . $newName;

            if ($fileExt === 'mp4' || $fileExt === 'mov') {
                $vidStmt->execute([$dbPath, $property_id, $dealer_id]);
            } else {
                $imgStmt->execute([$property_id, $dbPath, $is_main]);
                $is_main = 0;
            }

            $uploadedFiles[] = 'https://houseforrent.site/' . ltrim($dbPath, '/');
        }

        $conn->commit();

        if (count($uploadedFiles) > 0) {
            $msg = count($uploadedFiles) . ' files uploaded successfully';
            if (!empty($skipped)) {
                $msg .= '. Skipped: ' . implode(', ', $skipped);
            }
            json_response([
                'status' => 'success',
                'message' => $msg,
                'urls' => $uploadedFiles,
            ]);
        }

        json_response([
            'status' => 'error',
            'message' => 'Failed to upload any valid files'
                . (!empty($skipped) ? (': ' . implode(', ', $skipped)) : '')
                . '. Use JPG/PNG/WEBP (photos) or MP4/MOV (video), max 12MB each.',
        ]);
    } catch (PDOException $e) {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }
        json_response(['status' => 'error', 'message' => 'Database error during upload: ' . $e->getMessage()]);
    } catch (Throwable $e) {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }
        error_log('Property upload error: ' . $e->getMessage());
        json_response(['status' => 'error', 'message' => 'Upload failed temporarily. Please try again.'], 500);
    }
} else {
    json_response(['status' => 'error', 'message' => 'Invalid action']);
}

