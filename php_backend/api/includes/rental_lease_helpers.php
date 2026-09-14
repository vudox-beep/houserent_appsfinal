<?php
/**
 * Shared digital lease helpers for website + API.
 */

if (!function_exists('hr_lease_default_terms')) {
    function hr_lease_default_terms(array $data): string
    {
        $site = defined('SITE_NAME') ? SITE_NAME : 'HouseRent Africa';
        $title = $data['property_title'] ?? 'the property';
        $location = $data['property_location'] ?? '';
        $dealer = $data['dealer_name'] ?? 'Landlord';
        $tenant = $data['tenant_name'] ?? 'Tenant';
        $rent = number_format((float) ($data['rent_amount'] ?? 0), 2);
        $deposit = number_format((float) ($data['deposit_amount'] ?? 0), 2);
        $currency = $data['currency'] ?? 'ZMW';
        $start = $data['start_date'] ?? '';
        $end = $data['end_date'] ?: 'open-ended (until ended by either party with notice)';
        $dueDay = (int) ($data['due_day'] ?? 1);
        $room = trim((string) ($data['room_number'] ?? ''));
        $roomLine = $room !== '' ? "Room/unit: {$room}." : '';

        return <<<TXT
RENTAL AGREEMENT ({$site})

1. Parties
Landlord/Agent: {$dealer}
Tenant: {$tenant}

2. Property
{$title}
Location: {$location}
{$roomLine}

3. Term
Start date: {$start}
End date: {$end}

4. Rent & deposit
Monthly rent: {$currency} {$rent}
Deposit: {$currency} {$deposit}
Rent is due on day {$dueDay} of each month.

5. Tenant responsibilities
- Pay rent on time and keep the property clean and undamaged.
- Not sublet without written landlord consent.
- Report maintenance issues promptly through HouseRent Africa.
- Allow reasonable access for repairs after notice.

6. Landlord responsibilities
- Provide peaceful enjoyment of the property.
- Keep structural and essential services in working order.
- Review rent payments fairly and keep payment records.

7. Ending the tenancy
Either party may end the tenancy according to the agreed end date or with reasonable written notice. Outstanding rent remains payable.

8. Digital signatures
By signing in the HouseRent Africa app or website, both parties agree this electronic signature is valid for this agreement.

Generated for use on {$site}. This is a simple platform agreement template and does not replace legal advice.
TXT;
    }
}

if (!function_exists('hr_lease_fetch_rental_context')) {
    function hr_lease_fetch_rental_context(PDO $pdo, int $rentalId): ?array
    {
        $stmt = $pdo->prepare(
            "SELECT r.id AS rental_id, r.property_id, r.dealer_id, r.tenant_id, r.start_date, r.end_date,
                    r.rent_amount, r.currency, r.room_number, r.status AS rental_status,
                    p.title AS property_title, p.location AS property_location,
                    d.name AS dealer_name, t.name AS tenant_name
             FROM rentals r
             JOIN properties p ON p.id = r.property_id
             JOIN users d ON d.id = r.dealer_id
             JOIN users t ON t.id = r.tenant_id
             WHERE r.id = :id
             LIMIT 1"
        );
        $stmt->execute([':id' => $rentalId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    }
}

if (!function_exists('hr_lease_create_from_rental')) {
    /**
     * @return array{ok:bool,lease_id?:int,message?:string,lease?:array}
     */
    function hr_lease_create_from_rental(
        PDO $pdo,
        int $rentalId,
        int $createdBy,
        float $depositAmount = 0.0,
        ?string $customTerms = null,
        bool $sendToTenant = true
    ): array {
        $ctx = hr_lease_fetch_rental_context($pdo, $rentalId);
        if (!$ctx) {
            return ['ok' => false, 'message' => 'Rental not found.'];
        }
        if (($ctx['rental_status'] ?? '') !== 'active') {
            return ['ok' => false, 'message' => 'Lease can only be created for an active rental.'];
        }

        $open = $pdo->prepare(
            "SELECT id FROM rental_leases
             WHERE rental_id = :rid AND status IN ('draft','pending_tenant','pending_dealer')
             LIMIT 1"
        );
        $open->execute([':rid' => $rentalId]);
        if ($open->fetchColumn()) {
            return ['ok' => false, 'message' => 'An open lease already exists for this rental.'];
        }

        $start = (string) $ctx['start_date'];
        $dueDay = 1;
        try {
            $dueDay = max(1, min(28, (int) (new DateTime($start))->format('j')));
        } catch (Throwable $e) {
            $dueDay = 1;
        }

        $payload = [
            'property_title' => $ctx['property_title'],
            'property_location' => $ctx['property_location'],
            'dealer_name' => $ctx['dealer_name'],
            'tenant_name' => $ctx['tenant_name'],
            'rent_amount' => $ctx['rent_amount'],
            'deposit_amount' => $depositAmount,
            'currency' => $ctx['currency'] ?: 'ZMW',
            'start_date' => $ctx['start_date'],
            'end_date' => $ctx['end_date'],
            'due_day' => $dueDay,
            'room_number' => $ctx['room_number'],
        ];
        $terms = trim((string) $customTerms);
        if ($terms === '') {
            $terms = hr_lease_default_terms($payload);
        }

        $status = $sendToTenant ? 'pending_tenant' : 'draft';

        $ins = $pdo->prepare(
            "INSERT INTO rental_leases
             (rental_id, property_id, dealer_id, tenant_id, property_title, property_location,
              dealer_name, tenant_name, room_number, rent_amount, deposit_amount, currency,
              start_date, end_date, due_day, terms_body, status, created_by)
             VALUES
             (:rental_id, :property_id, :dealer_id, :tenant_id, :property_title, :property_location,
              :dealer_name, :tenant_name, :room_number, :rent_amount, :deposit_amount, :currency,
              :start_date, :end_date, :due_day, :terms_body, :status, :created_by)"
        );
        $ins->execute([
            ':rental_id' => (int) $ctx['rental_id'],
            ':property_id' => (int) $ctx['property_id'],
            ':dealer_id' => (int) $ctx['dealer_id'],
            ':tenant_id' => (int) $ctx['tenant_id'],
            ':property_title' => $ctx['property_title'],
            ':property_location' => $ctx['property_location'],
            ':dealer_name' => $ctx['dealer_name'],
            ':tenant_name' => $ctx['tenant_name'],
            ':room_number' => $ctx['room_number'],
            ':rent_amount' => (float) $ctx['rent_amount'],
            ':deposit_amount' => max(0, $depositAmount),
            ':currency' => $ctx['currency'] ?: 'ZMW',
            ':start_date' => $ctx['start_date'],
            ':end_date' => $ctx['end_date'] ?: null,
            ':due_day' => $dueDay,
            ':terms_body' => $terms,
            ':status' => $status,
            ':created_by' => $createdBy,
        ]);

        $leaseId = (int) $pdo->lastInsertId();
        $lease = hr_lease_get($pdo, $leaseId);

        return ['ok' => true, 'lease_id' => $leaseId, 'lease' => $lease];
    }
}

if (!function_exists('hr_lease_get')) {
    function hr_lease_get(PDO $pdo, int $leaseId): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM rental_leases WHERE id = :id LIMIT 1');
        $stmt->execute([':id' => $leaseId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    }
}

if (!function_exists('hr_lease_sign')) {
    /**
     * @return array{ok:bool,message?:string,lease?:array}
     */
    function hr_lease_sign(
        PDO $pdo,
        int $leaseId,
        int $userId,
        string $role,
        string $signedName,
        string $signatureData
    ): array {
        $lease = hr_lease_get($pdo, $leaseId);
        if (!$lease) {
            return ['ok' => false, 'message' => 'Lease not found.'];
        }
        if (in_array($lease['status'], ['signed', 'cancelled'], true)) {
            return ['ok' => false, 'message' => 'This lease can no longer be signed.'];
        }

        $signedName = trim($signedName);
        $signatureData = trim($signatureData);
        if ($signedName === '' || $signatureData === '') {
            return ['ok' => false, 'message' => 'Name and signature are required.'];
        }
        if (strlen($signatureData) > 900000) {
            return ['ok' => false, 'message' => 'Signature image is too large.'];
        }

        $role = strtolower($role);
        $now = date('Y-m-d H:i:s');

        if ($role === 'dealer') {
            if ((int) $lease['dealer_id'] !== $userId) {
                return ['ok' => false, 'message' => 'Not allowed to sign this lease.'];
            }
            if (!empty($lease['dealer_signed_at'])) {
                return ['ok' => false, 'message' => 'Dealer already signed.'];
            }
            $newStatus = !empty($lease['tenant_signed_at']) ? 'signed' : 'pending_tenant';
            $upd = $pdo->prepare(
                "UPDATE rental_leases
                 SET dealer_signed_name = :name, dealer_signature_data = :sig, dealer_signed_at = :at, status = :status
                 WHERE id = :id"
            );
            $upd->execute([
                ':name' => $signedName,
                ':sig' => $signatureData,
                ':at' => $now,
                ':status' => $newStatus,
                ':id' => $leaseId,
            ]);
        } elseif ($role === 'user' || $role === 'tenant') {
            if ((int) $lease['tenant_id'] !== $userId) {
                return ['ok' => false, 'message' => 'Not allowed to sign this lease.'];
            }
            if (!empty($lease['tenant_signed_at'])) {
                return ['ok' => false, 'message' => 'Tenant already signed.'];
            }
            $newStatus = !empty($lease['dealer_signed_at']) ? 'signed' : 'pending_dealer';
            $upd = $pdo->prepare(
                "UPDATE rental_leases
                 SET tenant_signed_name = :name, tenant_signature_data = :sig, tenant_signed_at = :at, status = :status
                 WHERE id = :id"
            );
            $upd->execute([
                ':name' => $signedName,
                ':sig' => $signatureData,
                ':at' => $now,
                ':status' => $newStatus,
                ':id' => $leaseId,
            ]);
        } else {
            return ['ok' => false, 'message' => 'Invalid signer role.'];
        }

        return ['ok' => true, 'lease' => hr_lease_get($pdo, $leaseId)];
    }
}

if (!function_exists('hr_lease_notify_party')) {
    function hr_lease_notify_party(PDO $pdo, array $lease, string $title, string $message, string $targetRole): void
    {
        $firebaseCandidates = [
            dirname(__DIR__, 2) . '/php_backend/api/notifications/firebase_push.php',
            dirname(__DIR__, 3) . '/php_backend/api/notifications/firebase_push.php',
            dirname(__DIR__) . '/notifications/firebase_push.php',
            __DIR__ . '/../notifications/firebase_push.php',
        ];
        $firebase = '';
        foreach ($firebaseCandidates as $candidate) {
            if (is_file($candidate)) {
                $firebase = $candidate;
                break;
            }
        }
        if ($firebase === '') {
            return;
        }
        try {
            require_once $firebase;
            if (!function_exists('sendFirebaseNotificationEnsuringUsers')) {
                return;
            }
            $userId = $targetRole === 'dealer'
                ? (int) $lease['dealer_id']
                : (int) $lease['tenant_id'];
            sendFirebaseNotificationEnsuringUsers(
                $pdo,
                $targetRole === 'dealer' ? 'dealer' : 'user',
                [$userId],
                $title,
                $message,
                [
                    'type' => 'rental_lease',
                    'lease_id' => (string) $lease['id'],
                    'rental_id' => (string) $lease['rental_id'],
                ]
            );
        } catch (Throwable $e) {
            error_log('Lease push failed: ' . $e->getMessage());
        }
    }
}
