<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

function rating_summary(PDO $conn, int $dealerId, ?int $propertyId = null, ?int $userId = null): array {
    $params = [$dealerId];
    $where = "dealer_id = ?";

    if ($propertyId !== null) {
        $where .= " AND property_id = ?";
        $params[] = $propertyId;
    }

    $stmt = $conn->prepare("
        SELECT
            ROUND(COALESCE(AVG(rating), 0), 1) AS avg_rating,
            COUNT(*) AS total_ratings
        FROM landlord_ratings
        WHERE $where
    ");
    $stmt->execute($params);
    $aggregate = $stmt->fetch(PDO::FETCH_ASSOC) ?: ['avg_rating' => 0, 'total_ratings' => 0];

    $myRating = null;
    if ($userId !== null) {
        $mineParams = [$dealerId, $userId];
        $mineWhere = "dealer_id = ? AND user_id = ?";
        if ($propertyId !== null) {
            $mineWhere .= " AND property_id = ?";
            $mineParams[] = $propertyId;
        }
        $mineStmt = $conn->prepare("
            SELECT rating, review, updated_at
            FROM landlord_ratings
            WHERE $mineWhere
            ORDER BY updated_at DESC
            LIMIT 1
        ");
        $mineStmt->execute($mineParams);
        $myRating = $mineStmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    return [
        'average_rating' => (float)($aggregate['avg_rating'] ?? 0),
        'total_ratings' => (int)($aggregate['total_ratings'] ?? 0),
        'my_rating' => $myRating,
    ];
}

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $dealerId = (int)($_GET['dealer_id'] ?? 0);
    $propertyIdRaw = trim((string)($_GET['property_id'] ?? ''));
    $propertyId = $propertyIdRaw === '' ? null : (int)$propertyIdRaw;

    if ($dealerId <= 0) {
        echo json_encode(['status' => 'error', 'message' => 'dealer_id is required']);
        exit;
    }

    $tokenUser = verifyToken();
    $userId = isset($tokenUser['id']) ? (int)$tokenUser['id'] : null;

    try {
        $summary = rating_summary($conn, $dealerId, $propertyId, $userId);
        echo json_encode(['status' => 'success', 'data' => $summary]);
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'Failed to fetch ratings']);
    }
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = authorize(['user', 'dealer', 'admin']);
    $payload = json_decode(file_get_contents('php://input'), true) ?? $_POST;

    $action = trim((string)($payload['action'] ?? 'submit_rating'));
    if ($action !== 'submit_rating') {
        echo json_encode(['status' => 'error', 'message' => 'Unsupported action']);
        exit;
    }

    $dealerId = (int)($payload['dealer_id'] ?? 0);
    $propertyId = (int)($payload['property_id'] ?? 0);
    $rating = (int)($payload['rating'] ?? 0);
    $review = trim((string)($payload['review'] ?? ''));
    $userId = (int)($user['id'] ?? 0);

    if ($dealerId <= 0 || $propertyId <= 0 || $rating < 1 || $rating > 5) {
        echo json_encode(['status' => 'error', 'message' => 'dealer_id, property_id and rating (1-5) are required']);
        exit;
    }

    if ($dealerId === $userId) {
        echo json_encode(['status' => 'error', 'message' => 'You cannot rate your own listing']);
        exit;
    }

    try {
        $verifyStmt = $conn->prepare("SELECT id FROM properties WHERE id = ? AND dealer_id = ?");
        $verifyStmt->execute([$propertyId, $dealerId]);
        if (!$verifyStmt->fetch(PDO::FETCH_ASSOC)) {
            echo json_encode(['status' => 'error', 'message' => 'Property/dealer mismatch']);
            exit;
        }

        $upsert = $conn->prepare("
            INSERT INTO landlord_ratings (dealer_id, property_id, user_id, rating, review)
            VALUES (:dealer_id, :property_id, :user_id, :rating, :review)
            ON DUPLICATE KEY UPDATE
                rating = VALUES(rating),
                review = VALUES(review),
                updated_at = CURRENT_TIMESTAMP
        ");
        $upsert->execute([
            ':dealer_id' => $dealerId,
            ':property_id' => $propertyId,
            ':user_id' => $userId,
            ':rating' => $rating,
            ':review' => $review,
        ]);

        $summary = rating_summary($conn, $dealerId, $propertyId, $userId);
        echo json_encode([
            'status' => 'success',
            'message' => 'Rating saved',
            'data' => $summary,
        ]);
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'Failed to save rating']);
    }
    exit;
}

http_response_code(405);
echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
