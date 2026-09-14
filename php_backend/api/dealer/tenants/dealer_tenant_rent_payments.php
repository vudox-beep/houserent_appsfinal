<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once '../../db.php';
require_once '../../auth.php';

function dealerTenantDueDate(string $startDate, int $monthsCovered): DateTime
{
    $start = new DateTime($startDate);
    $startYear = (int)$start->format('Y');
    $startMonth = (int)$start->format('n');
    $startDay = (int)$start->format('j');
    $monthIndex = ($startYear * 12) + ($startMonth - 1) + max(0, $monthsCovered);
    $dueYear = intdiv($monthIndex, 12);
    $dueMonth = ($monthIndex % 12) + 1;
    $lastDay = (int)(new DateTime(sprintf('%04d-%02d-01', $dueYear, $dueMonth)))->format('t');

    return new DateTime(sprintf(
        '%04d-%02d-%02d',
        $dueYear,
        $dueMonth,
        min($startDay, $lastDay)
    ));
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if (!in_array($_SERVER['REQUEST_METHOD'], ['GET', 'POST'], true)) {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

$user = authorize(['dealer']);
$dealerId = (int)$user['id'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode(file_get_contents('php://input'), true);
    if (!is_array($data)) {
        $data = $_POST;
    }

    $action = trim((string)($data['action'] ?? 'add_tenant_by_email'));
    if ($action === 'review_payment') {
        $paymentId = (int)($data['payment_id'] ?? 0);
        $reviewStatus = strtolower(trim((string)($data['status'] ?? '')));
        $dealerNotes = trim((string)($data['dealer_notes'] ?? ''));

        if ($paymentId < 1 || !in_array($reviewStatus, ['pending', 'approved', 'rejected'], true)) {
            http_response_code(422);
            echo json_encode(['status' => 'error', 'message' => 'Valid payment and review status are required']);
            exit;
        }

        try {
            $paymentStatement = $conn->prepare("
                SELECT rp.id, rp.status
                FROM rent_payments rp
                INNER JOIN rentals r ON r.id = rp.rental_id
                WHERE rp.id = :payment_id AND r.dealer_id = :dealer_id
                LIMIT 1
            ");
            $paymentStatement->execute([
                ':payment_id' => $paymentId,
                ':dealer_id' => $dealerId,
            ]);
            $payment = $paymentStatement->fetch(PDO::FETCH_ASSOC);

            if (!$payment) {
                http_response_code(404);
                echo json_encode(['status' => 'error', 'message' => 'Payment was not found for this dealer']);
                exit;
            }
            $currentStatus = (string)$payment['status'];
            $validTransition = ($currentStatus === 'pending' && in_array($reviewStatus, ['approved', 'rejected'], true))
                || (in_array($currentStatus, ['approved', 'rejected'], true) && $reviewStatus === 'pending');
            if (!$validTransition) {
                http_response_code(409);
                echo json_encode(['status' => 'error', 'message' => 'Payment status changed already. Refresh and try again']);
                exit;
            }

            $updateStatement = $conn->prepare("
                UPDATE rent_payments
                SET status = :status, dealer_notes = :dealer_notes
                WHERE id = :payment_id AND status = :current_status
            ");
            $updateStatement->execute([
                ':status' => $reviewStatus,
                ':dealer_notes' => $reviewStatus === 'pending'
                    ? null
                    : ($dealerNotes === '' ? null : $dealerNotes),
                ':payment_id' => $paymentId,
                ':current_status' => $currentStatus,
            ]);

            if ($updateStatement->rowCount() !== 1) {
                http_response_code(409);
                echo json_encode(['status' => 'error', 'message' => 'Payment was already updated. Refresh and try again']);
                exit;
            }

            echo json_encode([
                'status' => 'success',
                'message' => $reviewStatus === 'pending'
                    ? 'Payment reverted to pending'
                    : 'Payment ' . $reviewStatus . ' successfully',
                'payment_id' => $paymentId,
                'payment_status' => $reviewStatus,
            ]);
        } catch (PDOException $exception) {
            http_response_code(500);
            echo json_encode(['status' => 'error', 'message' => 'Unable to review payment']);
        }
        exit;
    }

    if ($action !== 'add_tenant_by_email') {
        http_response_code(422);
        echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
        exit;
    }

    $email = strtolower(trim((string)($data['email'] ?? '')));
    $propertyId = (int)($data['property_id'] ?? 0);
    $rentAmount = $data['rent_amount'] ?? null;
    $startDate = trim((string)($data['start_date'] ?? ''));
    $endDate = trim((string)($data['end_date'] ?? ''));
    $roomNumber = trim((string)($data['room_number'] ?? ''));

    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        http_response_code(422);
        echo json_encode(['status' => 'error', 'message' => 'Enter a valid tenant email address']);
        exit;
    }
    if ($propertyId < 1 || !is_numeric($rentAmount) || (float)$rentAmount <= 0) {
        http_response_code(422);
        echo json_encode(['status' => 'error', 'message' => 'Property and a valid rent amount are required']);
        exit;
    }

    $parsedStart = DateTime::createFromFormat('!Y-m-d', $startDate);
    $parsedEnd = $endDate === '' ? null : DateTime::createFromFormat('!Y-m-d', $endDate);
    if (!$parsedStart || $parsedStart->format('Y-m-d') !== $startDate ||
        ($endDate !== '' && (!$parsedEnd || $parsedEnd->format('Y-m-d') !== $endDate))) {
        http_response_code(422);
        echo json_encode(['status' => 'error', 'message' => 'Use valid start and end dates']);
        exit;
    }
    if ($parsedEnd && $parsedEnd < $parsedStart) {
        http_response_code(422);
        echo json_encode(['status' => 'error', 'message' => 'End date cannot be before the start date']);
        exit;
    }

    try {
        $propertyStatement = $conn->prepare('SELECT id, title, currency FROM properties WHERE id = :property_id AND dealer_id = :dealer_id LIMIT 1');
        $propertyStatement->execute([':property_id' => $propertyId, ':dealer_id' => $dealerId]);
        $property = $propertyStatement->fetch(PDO::FETCH_ASSOC);
        if (!$property) {
            http_response_code(404);
            echo json_encode(['status' => 'error', 'message' => 'Property not found for this dealer']);
            exit;
        }

        $tenantStatement = $conn->prepare("SELECT id, name, email FROM users WHERE LOWER(email) = :email AND role = 'user' LIMIT 1");
        $tenantStatement->execute([':email' => $email]);
        $tenant = $tenantStatement->fetch(PDO::FETCH_ASSOC);
        if (!$tenant) {
            http_response_code(404);
            echo json_encode(['status' => 'error', 'message' => 'No registered tenant was found with that email']);
            exit;
        }

        $duplicateStatement = $conn->prepare("SELECT id FROM rentals WHERE dealer_id = :dealer_id AND property_id = :property_id AND tenant_id = :tenant_id AND status = 'active' LIMIT 1");
        $duplicateStatement->execute([
            ':dealer_id' => $dealerId,
            ':property_id' => $propertyId,
            ':tenant_id' => $tenant['id'],
        ]);
        if ($duplicateStatement->fetch(PDO::FETCH_ASSOC)) {
            http_response_code(409);
            echo json_encode(['status' => 'error', 'message' => 'This tenant already has an active rental for the selected property']);
            exit;
        }

        $paymentReference = '';
        for ($digit = 0; $digit < 16; $digit++) {
            $paymentReference .= (string)random_int(0, 9);
        }

        $insertStatement = $conn->prepare("
            INSERT INTO rentals
                (property_id, dealer_id, tenant_id, status, start_date, end_date, rent_amount, currency, payment_reference, room_number)
            VALUES
                (:property_id, :dealer_id, :tenant_id, 'active', :start_date, :end_date, :rent_amount, :currency, :payment_reference, :room_number)
        ");
        $insertStatement->execute([
            ':property_id' => $propertyId,
            ':dealer_id' => $dealerId,
            ':tenant_id' => $tenant['id'],
            ':start_date' => $startDate,
            ':end_date' => $endDate === '' ? null : $endDate,
            ':rent_amount' => (float)$rentAmount,
            ':currency' => $property['currency'] ?: 'ZMW',
            ':payment_reference' => $paymentReference,
            ':room_number' => $roomNumber === '' ? null : $roomNumber,
        ]);

        http_response_code(201);
        echo json_encode([
            'status' => 'success',
            'message' => 'Tenant added successfully',
            'rental_id' => (int)$conn->lastInsertId(),
            'payment_reference' => $paymentReference,
            'tenant' => $tenant,
        ]);
    } catch (PDOException $exception) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'Unable to add tenant']);
    }
    exit;
}

$requestedStatus = strtolower(trim((string)($_GET['status'] ?? 'all')));
$allowedStatuses = ['all', 'pending', 'approved', 'rejected'];

if (!in_array($requestedStatus, $allowedStatuses, true)) {
    http_response_code(422);
    echo json_encode(['status' => 'error', 'message' => 'Invalid payment status']);
    exit;
}

try {
    // One row per rental, including tenants who have not submitted a payment yet.
    $tenantStatement = $conn->prepare("
        SELECT
            r.id AS rental_id,
            r.tenant_id,
            r.status AS rental_status,
            r.start_date,
            r.end_date,
            r.rent_amount,
            r.currency,
            r.room_number,
            r.payment_reference,
            u.name AS tenant_name,
            u.email AS tenant_email,
            u.phone AS tenant_phone,
            p.id AS property_id,
            p.title AS property_title,
            latest.id AS latest_payment_id,
            latest.month_year AS latest_payment_month,
            latest.amount AS latest_payment_amount,
            latest.status AS latest_payment_status,
            latest.payment_method AS latest_payment_method,
            latest.created_at AS latest_payment_date,
            (
                SELECT COALESCE(SUM(GREATEST(
                    COALESCE(rp3.months_paid, 1),
                    COALESCE(FLOOR(rp3.amount / NULLIF(r.rent_amount, 0)), 1),
                    1
                )), 0)
                FROM rent_payments rp3
                WHERE rp3.rental_id = r.id AND rp3.status = 'approved'
            ) AS paid_months
        FROM rentals r
        INNER JOIN users u ON u.id = r.tenant_id
        INNER JOIN properties p ON p.id = r.property_id
        LEFT JOIN rent_payments latest
            ON latest.id = (
                SELECT rp2.id
                FROM rent_payments rp2
                WHERE rp2.rental_id = r.id
                ORDER BY rp2.created_at DESC, rp2.id DESC
                LIMIT 1
            )
        WHERE r.dealer_id = :dealer_id
        ORDER BY r.status = 'active' DESC, u.name ASC
    ");
    $tenantStatement->execute([':dealer_id' => $dealerId]);
    $tenants = $tenantStatement->fetchAll(PDO::FETCH_ASSOC);

    foreach ($tenants as &$tenant) {
        $tenant['latest_payment_status'] = $tenant['latest_payment_status'] ?? 'not_paid';
        $paidMonths = max(0, (int)$tenant['paid_months']);
        $nextDueDate = dealerTenantDueDate($tenant['start_date'], $paidMonths);
        $paidThroughDate = clone $nextDueDate;
        $paidThroughDate->modify('-1 day');
        $today = new DateTime('today');
        $tenant['months_covered'] = $paidMonths;
        $tenant['next_due_date'] = $nextDueDate->format('Y-m-d');
        $tenant['paid_through_date'] = $paidMonths > 0
            ? $paidThroughDate->format('Y-m-d')
            : null;
        $tenant['days_until_due'] = (int)$today->diff($nextDueDate)->format('%r%a');
        $tenant['due_status'] = $tenant['rental_status'] !== 'active'
            ? 'inactive'
            : ($nextDueDate < $today ? 'overdue' : 'upcoming');
    }
    unset($tenant);

    $statusClause = '';
    $parameters = [':dealer_id' => $dealerId];
    if ($requestedStatus !== 'all') {
        $statusClause = ' AND rp.status = :payment_status';
        $parameters[':payment_status'] = $requestedStatus;
    }

    $paymentStatement = $conn->prepare("
        SELECT
            rp.id AS payment_id,
            rp.rental_id,
            rp.tenant_id,
            rp.month_year,
            rp.amount,
            rp.currency,
            rp.status AS payment_status,
            rp.payment_method,
            rp.months_paid,
            GREATEST(
                COALESCE(rp.months_paid, 1),
                COALESCE(FLOOR(rp.amount / NULLIF(r.rent_amount, 0)), 1),
                1
            ) AS covered_months,
            rp.reference,
            rp.proof_file,
            rp.dealer_notes,
            rp.created_at AS submitted_at,
            u.name AS tenant_name,
            u.email AS tenant_email,
            u.phone AS tenant_phone,
            p.id AS property_id,
            p.title AS property_title,
            r.room_number,
            r.rent_amount,
            r.payment_reference
        FROM rent_payments rp
        INNER JOIN rentals r ON r.id = rp.rental_id
            AND r.tenant_id = rp.tenant_id
        INNER JOIN users u ON u.id = rp.tenant_id
        INNER JOIN properties p ON p.id = r.property_id
        WHERE r.dealer_id = :dealer_id{$statusClause}
        ORDER BY rp.created_at DESC, rp.id DESC
        LIMIT 200
    ");
    $paymentStatement->execute($parameters);
    $payments = $paymentStatement->fetchAll(PDO::FETCH_ASSOC);

    foreach ($payments as &$payment) {
        $payment['proof_url'] = empty($payment['proof_file'])
            ? null
            : (strpos($payment['proof_file'], 'http') === 0
                ? $payment['proof_file']
                : 'https://houseforrent.site/' . ltrim($payment['proof_file'], '/'));
    }
    unset($payment);

    $dueDatesByRental = [];
    foreach ($tenants as $tenant) {
        $dueDatesByRental[(string)$tenant['rental_id']] = [
            'next_due_date' => $tenant['next_due_date'],
            'paid_through_date' => $tenant['paid_through_date'],
            'months_covered' => $tenant['months_covered'],
            'days_until_due' => $tenant['days_until_due'],
            'due_status' => $tenant['due_status'],
        ];
    }
    foreach ($payments as &$payment) {
        $dueData = $dueDatesByRental[(string)$payment['rental_id']] ?? null;
        if ($dueData) {
            $payment = array_merge($payment, $dueData);
        }
    }
    unset($payment);

    $counts = ['all' => 0, 'pending' => 0, 'approved' => 0, 'rejected' => 0];
    $countStatement = $conn->prepare("
        SELECT rp.status, COUNT(*) AS total
        FROM rent_payments rp
        INNER JOIN rentals r ON r.id = rp.rental_id
        WHERE r.dealer_id = :dealer_id
        GROUP BY rp.status
    ");
    $countStatement->execute([':dealer_id' => $dealerId]);
    foreach ($countStatement->fetchAll(PDO::FETCH_ASSOC) as $row) {
        if (isset($counts[$row['status']])) {
            $counts[$row['status']] = (int)$row['total'];
            $counts['all'] += (int)$row['total'];
        }
    }

    $propertyStatement = $conn->prepare("
        SELECT id, title, price, currency, status, listing_purpose
        FROM properties
        WHERE dealer_id = :dealer_id
          AND status = 'available'
          AND listing_purpose IN ('rent', 'service', 'lease')
        ORDER BY title ASC
    ");
    $propertyStatement->execute([':dealer_id' => $dealerId]);
    $properties = $propertyStatement->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'status' => 'success',
        'tenants' => $tenants,
        'payments' => $payments,
        'properties' => $properties,
        'recent_activity' => array_slice($payments, 0, 10),
        'pending_payments' => array_values(array_filter(
            $payments,
            static fn($payment) => $payment['payment_status'] === 'pending'
        )),
        'counts' => $counts,
        'total_tenants' => count($tenants),
        'active_tenants' => count(array_filter(
            $tenants,
            static fn($tenant) => $tenant['rental_status'] === 'active'
        )),
    ]);
} catch (PDOException $exception) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Unable to load tenant payments',
    ]);
}
