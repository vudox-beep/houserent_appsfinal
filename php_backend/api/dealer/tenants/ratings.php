<?php
require_once '../../cors.php';
require_once '../../db.php';
require_once '../../auth.php';

$user = authorize(['dealer', 'admin']);
$dealerId = (int)($user['id'] ?? 0);

function tenant_rating_summary(PDO $conn, int $tenantId, int $dealerId): array {
    $aggStmt = $conn->prepare("
        SELECT ROUND(COALESCE(AVG(rating), 0), 1) AS avg_rating, COUNT(*) AS total_ratings
        FROM tenant_ratings
        WHERE tenant_id = ?
    ");
    $aggStmt->execute([$tenantId]);
    $agg = $aggStmt->fetch(PDO::FETCH_ASSOC) ?: ['avg_rating' => 0, 'total_ratings' => 0];

    $mineStmt = $conn->prepare("
        SELECT rating, review, updated_at
        FROM tenant_ratings
        WHERE tenant_id = ? AND dealer_id = ?
        LIMIT 1
    ");
    $mineStmt->execute([$tenantId, $dealerId]);
    $mine = $mineStmt->fetch(PDO::FETCH_ASSOC) ?: null;

    $reviewsStmt = $conn->prepare("
        SELECT
            tr.rating,
            tr.review,
            tr.updated_at,
            u.name AS dealer_name
        FROM tenant_ratings tr
        JOIN users u ON tr.dealer_id = u.id
        WHERE tr.tenant_id = ?
          AND tr.review IS NOT NULL
          AND TRIM(tr.review) <> ''
        ORDER BY tr.updated_at DESC
        LIMIT 5
    ");
    $reviewsStmt->execute([$tenantId]);
    $reviews = $reviewsStmt->fetchAll(PDO::FETCH_ASSOC) ?: [];

    return [
        'average_rating' => (float)($agg['avg_rating'] ?? 0),
        'total_ratings' => (int)($agg['total_ratings'] ?? 0),
        'my_rating' => $mine,
        'recent_reviews' => $reviews,
    ];
}

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $tenantId = (int)($_GET['tenant_id'] ?? 0);

    try {
        // When tenant_id is not passed, return dealer's rated tenants list
        // so the app can show ratings without fetching the full tenants list.
        if ($tenantId <= 0) {
            $listStmt = $conn->prepare("
                SELECT
                    tr.tenant_id,
                    u.name AS tenant_name,
                    u.email AS tenant_email,
                    ROUND(COALESCE(AVG(tr.rating), 0), 1) AS average_rating,
                    COUNT(*) AS total_ratings,
                    MAX(tr.updated_at) AS updated_at
                FROM tenant_ratings tr
                JOIN users u ON tr.tenant_id = u.id
                GROUP BY tr.tenant_id, u.name, u.email
                ORDER BY MAX(tr.updated_at) DESC
                LIMIT 200
            ");
            $listStmt->execute();
            $rows = $listStmt->fetchAll(PDO::FETCH_ASSOC) ?: [];

            foreach ($rows as &$row) {
                $tid = (int)($row['tenant_id'] ?? 0);
                if ($tid <= 0) continue;

                $mineStmt = $conn->prepare("
                    SELECT rating, review, updated_at
                    FROM tenant_ratings
                    WHERE tenant_id = ? AND dealer_id = ?
                    LIMIT 1
                ");
                $mineStmt->execute([$tid, $dealerId]);
                $row['my_rating'] = $mineStmt->fetch(PDO::FETCH_ASSOC) ?: null;

                $reviewsStmt = $conn->prepare("
                    SELECT
                        tr2.rating,
                        tr2.review,
                        tr2.updated_at,
                        u2.name AS dealer_name
                    FROM tenant_ratings tr2
                    JOIN users u2 ON tr2.dealer_id = u2.id
                    WHERE tr2.tenant_id = ?
                      AND tr2.review IS NOT NULL
                      AND TRIM(tr2.review) <> ''
                    ORDER BY tr2.updated_at DESC
                    LIMIT 5
                ");
                $reviewsStmt->execute([$tid]);
                $row['recent_reviews'] = $reviewsStmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
            }
            unset($row);

            echo json_encode(['status' => 'success', 'data' => $rows]);
            exit;
        }

        $summary = tenant_rating_summary($conn, $tenantId, $dealerId);
        echo json_encode(['status' => 'success', 'data' => $summary]);
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'Failed to load tenant rating']);
    }
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $payload = json_decode(file_get_contents('php://input'), true) ?? $_POST;

    $tenantId = (int)($payload['tenant_id'] ?? 0);
    $rentalId = (int)($payload['rental_id'] ?? 0);
    $rating = (int)($payload['rating'] ?? 0);
    $review = trim((string)($payload['review'] ?? ''));

    if ($tenantId <= 0 || $rating < 1 || $rating > 5) {
        echo json_encode(['status' => 'error', 'message' => 'tenant_id and rating (1-5) are required']);
        exit;
    }

    try {
        // Ensure the tenant has at least one rental relationship with this dealer.
        $verifyStmt = $conn->prepare("
            SELECT id
            FROM rentals
            WHERE dealer_id = ? AND tenant_id = ?
            LIMIT 1
        ");
        $verifyStmt->execute([$dealerId, $tenantId]);
        if (!$verifyStmt->fetch(PDO::FETCH_ASSOC)) {
            echo json_encode(['status' => 'error', 'message' => 'You can only rate your own tenant']);
            exit;
        }

        $upsert = $conn->prepare("
            INSERT INTO tenant_ratings (dealer_id, tenant_id, rental_id, rating, review)
            VALUES (:dealer_id, :tenant_id, :rental_id, :rating, :review)
            ON DUPLICATE KEY UPDATE
                rating = VALUES(rating),
                review = VALUES(review),
                rental_id = VALUES(rental_id),
                updated_at = CURRENT_TIMESTAMP
        ");
        $upsert->execute([
            ':dealer_id' => $dealerId,
            ':tenant_id' => $tenantId,
            ':rental_id' => $rentalId > 0 ? $rentalId : null,
            ':rating' => $rating,
            ':review' => $review,
        ]);

        $summary = tenant_rating_summary($conn, $tenantId, $dealerId);
        echo json_encode([
            'status' => 'success',
            'message' => 'Tenant rating saved',
            'data' => $summary,
        ]);
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'Failed to save tenant rating']);
    }
    exit;
}

http_response_code(405);
echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
