import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/moving_marketplace_service.dart';
import '../../utils/app_error.dart';

/// Driver uploads licence OR NRC front+back. Admin verifies before they can work.
class DriverIdentityVerificationScreen extends StatefulWidget {
  const DriverIdentityVerificationScreen({super.key});

  @override
  State<DriverIdentityVerificationScreen> createState() =>
      _DriverIdentityVerificationScreenState();
}

class _DriverIdentityVerificationScreenState
    extends State<DriverIdentityVerificationScreen> {
  static const _accent = Color(0xFFFFC107);
  static const _brown = Color(0xFF5A3D31);

  bool _loading = true;
  bool _uploading = false;
  String _status = 'unverified';
  String _message = '';
  String? _docType; // licence | nrc
  String _chosenType = 'licence';

  String? _licencePath;
  String? _licenceName;
  String? _nrcFrontPath;
  String? _nrcFrontName;
  String? _nrcBackPath;
  String? _nrcBackName;
  List<Map<String, dynamic>> _photos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await MovingMarketplaceService.getDriverMe();
      if (!mounted) return;
      final photos = (me['identity_photos'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _status = (me['identity_status'] ?? 'unverified').toString();
        _message = (me['identity_message'] ?? '').toString();
        _docType = me['identity_doc_type']?.toString();
        if (_docType == 'nrc' || _docType == 'licence') {
          _chosenType = _docType!;
        }
        // Hide document photos while pending — show again only if rejected/verified.
        _photos = _status == 'pending' ? const [] : photos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = AppError.userMessage(e);
      });
    }
  }

  Future<String?> _pickImage(void Function(String path, String name) onPicked) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    onPicked(path, file.name);
    return path;
  }

  Future<void> _submit() async {
    if (_chosenType == 'licence' && _licencePath == null) {
      _toast('Choose a clear photo of your driver’s licence.', error: true);
      return;
    }
    if (_chosenType == 'nrc' &&
        (_nrcFrontPath == null || _nrcBackPath == null)) {
      _toast('Upload both NRC front and back photos.', error: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final result = await MovingMarketplaceService.uploadDriverIdentity(
        docType: _chosenType,
        licencePath: _licencePath,
        nrcFrontPath: _nrcFrontPath,
        nrcBackPath: _nrcBackPath,
      );
      if (!mounted) return;
      setState(() {
        // Always lock the form after a successful submit.
        _status = 'pending';
        _message = (result['identity_message'] ??
                'Documents submitted. Waiting for admin approval.')
            .toString();
        _docType = result['identity_doc_type']?.toString() ?? _chosenType;
        _photos = const [];
        _licencePath = null;
        _licenceName = null;
        _nrcFrontPath = null;
        _nrcFrontName = null;
        _nrcBackPath = null;
        _nrcBackName = null;
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Text('Pending approval'),
            ],
          ),
          content: const Text(
            'Your documents were sent for review.\n\n'
            'You cannot change them while approval is pending.\n'
            'You can go online after admin approval (usually 1–24 hours).',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _toast(AppError.userMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Color _statusColor() {
    switch (_status) {
      case 'verified':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return _accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = _status == 'verified';
    final pending = _status == 'pending';
    final rejected = _status == 'rejected';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          pending ? 'Pending approval' : 'Driver ID verification',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : _brown,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : pending
              ? _buildPendingPage(isDark)
              : verified
                  ? _buildVerifiedPage(isDark)
                  : _buildUploadPage(isDark, rejected: rejected),
    );
  }

  /// Full-page pending state — no documents, no re-upload.
  Widget _buildPendingPage(bool isDark) {
    final docLabel = _docType == 'nrc'
        ? 'NRC'
        : _docType == 'licence'
            ? 'Driver licence'
            : 'ID documents';

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    size: 56,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Pending approval',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _message.isNotEmpty
                      ? _message
                      : 'Your $docLabel was submitted and is waiting for admin approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'You cannot view or change your documents while approval is pending.\n\n'
                    'If they are rejected, you will be able to upload again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Colors.orange.shade200
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Refresh status',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Back',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifiedPage(bool isDark) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 56,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Verified',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _message.isNotEmpty
                      ? _message
                      : 'Your identity is verified. You can go online and accept jobs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ..._photos.map((p) {
                    final url = p['url']?.toString() ?? '';
                    if (url.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: isDark ? const Color(0xFF2A2A2A) : Colors.black12,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(url, fit: BoxFit.cover),
                    );
                  }),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadPage(bool isDark, {required bool rejected}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _statusColor().withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    rejected
                        ? Icons.error_outline_rounded
                        : Icons.badge_outlined,
                    color: _statusColor(),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rejected ? 'REJECTED' : 'UNVERIFIED',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _statusColor(),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _message.isNotEmpty
                    ? _message
                    : 'Upload your driver’s licence or NRC so tenants can trust your bookings.',
                style: TextStyle(
                  height: 1.4,
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (rejected && _photos.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Previously submitted photos',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          ..._photos.map((p) {
            final url = p['url']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isDark ? const Color(0xFF2A2A2A) : Colors.black12,
              ),
              clipBehavior: Clip.antiAlias,
              child: url.isEmpty
                  ? const SizedBox.shrink()
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
            );
          }),
        ],
        const SizedBox(height: 22),
        Text(
          rejected ? 'Upload new documents' : 'Choose ID type',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _typeChip(
                label: 'Driver licence',
                selected: _chosenType == 'licence',
                onTap: () => setState(() => _chosenType = 'licence'),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _typeChip(
                label: 'NRC (front + back)',
                selected: _chosenType == 'nrc',
                onTap: () => setState(() => _chosenType = 'nrc'),
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_chosenType == 'licence')
          _fileTile(
            title: 'Driver licence photo',
            subtitle: _licenceName ?? 'Tap to choose JPG/PNG',
            path: _licencePath,
            onTap: () => _pickImage((path, name) {
              setState(() {
                _licencePath = path;
                _licenceName = name;
              });
            }),
            isDark: isDark,
          )
        else ...[
          _fileTile(
            title: 'NRC front page',
            subtitle: _nrcFrontName ?? 'Tap to choose JPG/PNG',
            path: _nrcFrontPath,
            onTap: () => _pickImage((path, name) {
              setState(() {
                _nrcFrontPath = path;
                _nrcFrontName = name;
              });
            }),
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _fileTile(
            title: 'NRC back page',
            subtitle: _nrcBackName ?? 'Tap to choose JPG/PNG',
            path: _nrcBackPath,
            onTap: () => _pickImage((path, name) {
              setState(() {
                _nrcBackPath = path;
                _nrcBackName = name;
              });
            }),
            isDark: isDark,
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _uploading ? null : _submit,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.upload_file_rounded),
            label: Text(
              _uploading
                  ? 'Uploading…'
                  : (rejected
                      ? 'Resubmit for verification'
                      : 'Submit for verification'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _typeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: selected
          ? _accent.withValues(alpha: 0.22)
          : (isDark ? const Color(0xFF2A2A2A) : Colors.white),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _accent
                  : (isDark ? Colors.white12 : Colors.black12),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileTile({
    required String title,
    required String subtitle,
    required String? path,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: path == null
                      ? ColoredBox(
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFF0F0F0),
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        )
                      : Image.file(File(path), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
