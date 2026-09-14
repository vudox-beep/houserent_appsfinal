<?php

namespace App\Support;

use App\Exceptions\ApiException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class DriverIdentity
{
    public static function columnsReady(): bool
    {
        static $ready = null;
        if ($ready !== null) {
            return $ready;
        }
        try {
            $ready = Schema::hasColumn('drivers', 'identity_verified');
        } catch (\Throwable) {
            $ready = false;
        }

        return $ready;
    }

    /** @return array{code:int,status:string,message:string,doc_type:?string,has_docs:bool,photos:array<int,array{label:string,url:string}>} */
    public static function statusFor(object $driver): array
    {
        if (! self::columnsReady()) {
            return [
                'code' => 1,
                'status' => 'verified',
                'message' => 'Identity verification is not configured yet.',
                'doc_type' => null,
                'has_docs' => false,
                'photos' => [],
            ];
        }

        $code = (int) ($driver->identity_verified ?? 0);
        $docType = self::normalizeDocType($driver->identity_doc_type ?? null);
        $photos = self::photosFromRow($driver, absolute: true);
        $hasDocs = $photos !== [];

        if ($code === 1) {
            return [
                'code' => 1,
                'status' => 'verified',
                'message' => 'Your identity is verified. You can go online and accept jobs.',
                'doc_type' => $docType,
                'has_docs' => $hasDocs,
                'photos' => $photos,
            ];
        }
        if ($code === 2) {
            return [
                'code' => 2,
                'status' => 'rejected',
                'message' => 'Your documents were rejected. Please upload clear photos again.',
                'doc_type' => $docType,
                'has_docs' => $hasDocs,
                'photos' => $photos,
            ];
        }
        if ($hasDocs) {
            return [
                'code' => 0,
                'status' => 'pending',
                'message' => 'Documents submitted. Waiting for admin approval (usually 1–24 hours).',
                'doc_type' => $docType,
                'has_docs' => true,
                'photos' => $photos,
            ];
        }

        return [
            'code' => 0,
            'status' => 'unverified',
            'message' => 'Upload your driver’s licence or NRC (front and back) to start accepting jobs.',
            'doc_type' => null,
            'has_docs' => false,
            'photos' => [],
        ];
    }

    public static function requireVerified(object $user): void
    {
        if (! self::columnsReady()) {
            return;
        }
        $status = self::statusFor($user);
        if ($status['status'] === 'verified') {
            return;
        }
        throw new ApiException(
            403,
            'identity_required',
            $status['status'] === 'pending'
                ? 'Your ID is pending approval. You can use HouseRent Shifts after verification.'
                : 'Verify your driver’s licence or NRC before going online or unlocking jobs.',
        );
    }

    /**
     * Tenant-facing identity flag only when verified.
     * Licence / NRC document photos are NEVER sent to tenants — admin/driver only.
     * Tenants see the driver’s profile photo via photo_url / avatar_url instead.
     */
    public static function publicPayload(?object $row): ?array
    {
        if (! $row || ! self::columnsReady()) {
            return null;
        }
        if ((int) ($row->identity_verified ?? 0) !== 1) {
            return null;
        }

        return [
            'verified' => true,
            'doc_type' => self::normalizeDocType($row->identity_doc_type ?? null),
            'photos' => [],
        ];
    }

    public static function normalizeDocType(mixed $value): ?string
    {
        $type = strtolower(trim((string) $value));

        return in_array($type, ['licence', 'license', 'nrc'], true)
            ? ($type === 'license' ? 'licence' : $type)
            : null;
    }

    /**
     * @return array<int, array{label:string,url:string}>
     */
    public static function photosFromRow(object $row, bool $absolute = true): array
    {
        $docType = self::normalizeDocType($row->identity_doc_type ?? null);
        $out = [];
        if ($docType === 'licence') {
            $url = self::publicUrl($row->licence_photo_url ?? null, $absolute);
            if ($url !== null) {
                $out[] = ['label' => 'Driver licence', 'url' => $url];
            }

            return $out;
        }
        if ($docType === 'nrc') {
            $front = self::publicUrl($row->nrc_front_url ?? null, $absolute);
            $back = self::publicUrl($row->nrc_back_url ?? null, $absolute);
            if ($front !== null) {
                $out[] = ['label' => 'NRC front', 'url' => $front];
            }
            if ($back !== null) {
                $out[] = ['label' => 'NRC back', 'url' => $back];
            }
        }

        return $out;
    }

    public static function publicUrl(mixed $path, bool $absolute = true): ?string
    {
        $value = trim((string) $path);
        if ($value === '') {
            return null;
        }
        if (str_starts_with($value, 'http://') || str_starts_with($value, 'https://')) {
            return $value;
        }
        $value = ltrim($value, '/');
        if (! $absolute) {
            return $value;
        }

        return 'https://houseforrent.site/'.$value;
    }

    public static function storeImage(UploadedFile $file, int $driverId, string $kind): string
    {
        $ext = strtolower($file->getClientOriginalExtension() ?: 'jpg');
        if (! in_array($ext, ['jpg', 'jpeg', 'png', 'webp'], true)) {
            throw new ApiException(422, 'invalid_file', 'Please upload a JPG or PNG photo.');
        }
        if ($file->getSize() > 8 * 1024 * 1024) {
            throw new ApiException(422, 'file_too_large', 'Each photo must be under 8 MB.');
        }

        $dir = self::uploadDirectory();
        if (! is_dir($dir) && ! mkdir($dir, 0755, true) && ! is_dir($dir)) {
            throw new ApiException(500, 'upload_dir_failed', 'Could not prepare document storage.');
        }

        $name = sprintf(
            'driver_%d_%s_%s.%s',
            $driverId,
            preg_replace('/[^a-z0-9_]+/i', '', $kind) ?: 'doc',
            bin2hex(random_bytes(4)),
            $ext === 'jpeg' ? 'jpg' : $ext,
        );
        $target = rtrim($dir, DIRECTORY_SEPARATOR).DIRECTORY_SEPARATOR.$name;
        if (! $file->move(dirname($target), basename($target))) {
            throw new ApiException(500, 'upload_failed', 'Could not save your document photo.');
        }
        @chmod($target, 0644);

        return 'assets/images/driver_docs/'.$name;
    }

    public static function uploadDirectory(): string
    {
        $candidates = [
            rtrim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''), '/').'/assets/images/driver_docs',
            base_path('../../assets/images/driver_docs'),
            base_path('../../../assets/images/driver_docs'),
            storage_path('app/public/driver_docs'),
        ];
        foreach ($candidates as $path) {
            $path = str_replace(['/', '\\'], DIRECTORY_SEPARATOR, $path);
            $parent = dirname($path);
            if (is_dir($path) || is_dir($parent) || is_dir(dirname($parent))) {
                return $path;
            }
        }

        return $candidates[0];
    }

    public static function selectSql(string $alias = 'd'): string
    {
        if (! self::columnsReady()) {
            return '0 AS identity_verified, NULL AS identity_doc_type, NULL AS licence_photo_url, NULL AS nrc_front_url, NULL AS nrc_back_url';
        }

        return "{$alias}.identity_verified, {$alias}.identity_doc_type, {$alias}.licence_photo_url, {$alias}.nrc_front_url, {$alias}.nrc_back_url";
    }

    public static function markSubmitted(int $driverId, string $docType, array $paths): void
    {
        $update = [
            'identity_verified' => 0,
            'identity_doc_type' => $docType,
            'identity_submitted_at' => now(),
            'identity_reviewed_at' => null,
            'licence_photo_url' => null,
            'nrc_front_url' => null,
            'nrc_back_url' => null,
        ];
        foreach ($paths as $column => $path) {
            $update[$column] = $path;
        }
        DB::table('drivers')->where('user_id', $driverId)->update($update);
    }
}
