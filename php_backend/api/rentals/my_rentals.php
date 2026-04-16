<?php
require_once '../cors.php';
require_once '../db.php';
require_once '../auth.php';

$user = authorize(['user', 'tenant']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $conn->prepare("
            SELECT r.*, p.title, p.location, p.price, p.property_type,
                   d.name as landlord_name, d.phone as landlord_phone
            FROM rentals r
            JOIN properties p ON r.property_id = p.id
            JOIN users d ON r.dealer_id = d.id
            WHERE r.tenant_id = ?
            ORDER BY r.created_at DESC
        ");
        $stmt->execute([$user['id']]);
        $rentals = $stmt->fetchAll();

        foreach ($rentals as &$rental) {
            $payStmt = $conn->prepare("
                SELECT * FROM rent_payments 
                WHERE rental_id = ? 
                ORDER BY created_at DESC LIMIT 1
            ");
            $payStmt->execute([$rental['id']]);
            $rental['latest_payment'] = $payStmt->fetch() ?: null;

            // Compute a reliable next due date for tenant dashboard cards.
            $startRaw = !empty($rental['start_date']) ? $rental['start_date'] : 'now';
            try {
                $startDate = new DateTime($startRaw);
            } catch (Exception $e) {
                $startDate = new DateTime('now');
            }
            $startDay = (int)$startDate->format('d');
            $rentAmount = (float)($rental['rent_amount'] ?? 0);
            $today = new DateTime('today');

            $lastPaidStmt = $conn->prepare("
                SELECT month_year, amount, months_paid
                FROM rent_payments
                WHERE rental_id = ?
                  AND status IN ('approved', 'completed')
                ORDER BY created_at DESC
                LIMIT 1
            ");
            $lastPaidStmt->execute([$rental['id']]);
            $lastPaid = $lastPaidStmt->fetch(PDO::FETCH_ASSOC);

            if ($lastPaid && !empty($lastPaid['month_year'])) {
                $lastPaidDate = DateTime::createFromFormat('!F Y', (string)$lastPaid['month_year']);
                if ($lastPaidDate) {
                    $monthsPaid = (int)($lastPaid['months_paid'] ?? 0);
                    if ($monthsPaid < 1) {
                        $paidAmount = (float)($lastPaid['amount'] ?? 0);
                        $monthsPaid = ($rentAmount > 0) ? (int)round($paidAmount / $rentAmount) : 1;
                        if ($monthsPaid < 1) {
                            $monthsPaid = 1;
                        }
                    }

                    $nextDue = clone $lastPaidDate;
                    $nextDue->modify('+' . $monthsPaid . ' month');
                    $daysInTargetMonth = (int)$nextDue->format('t');
                    $targetDay = min($startDay, $daysInTargetMonth);
                    $nextDue->setDate((int)$nextDue->format('Y'), (int)$nextDue->format('m'), $targetDay);
                    $rental['next_due_date'] = $nextDue->format('M d, Y');
                } else {
                    $rental['next_due_date'] = date('M d, Y', strtotime('+1 month'));
                }
            } else {
                // If there are no approved/completed payments yet, show the next
                // upcoming due date based on the rental start day.
                if ($startDate > $today) {
                    $rental['next_due_date'] = $startDate->format('M d, Y');
                } else {
                    $year = (int)$today->format('Y');
                    $month = (int)$today->format('m');
                    if ((int)$today->format('d') > $startDay) {
                        $month += 1;
                        if ($month > 12) {
                            $month = 1;
                            $year += 1;
                        }
                    }

                    $daysInMonth = cal_days_in_month(CAL_GREGORIAN, $month, $year);
                    $targetDay = min($startDay, $daysInMonth);
                    $nextDue = DateTime::createFromFormat('!Y-n-j', $year . '-' . $month . '-' . $targetDay);
                    $rental['next_due_date'] = $nextDue ? $nextDue->format('M d, Y') : $today->format('M d, Y');
                }
            }
        }

        echo json_encode($rentals);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(["message" => "Server error fetching rentals"]);
    }
} else {
    http_response_code(405);
}
?>
