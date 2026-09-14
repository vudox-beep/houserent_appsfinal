import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import '../../utils/app_error.dart';
import '../../widgets/skeleton_loader.dart';

class DealerIdentityVerificationScreen extends StatefulWidget {
  final String userId;
  const DealerIdentityVerificationScreen({super.key, required this.userId});

  @override
  State<DealerIdentityVerificationScreen> createState() =>
      _DealerIdentityVerificationScreenState();
}

class _DealerIdentityVerificationScreenState
    extends State<DealerIdentityVerificationScreen> {
  bool _isLoading = false;
  bool _isCheckingStatus = true;
  bool _isSubmittedWaitingApproval = false;
  String? _selectedFilePath;
  String? _selectedFileName;

  @override
  void initState() {
    super.initState();
    _loadVerificationStatus();
  }

  Future<void> _loadVerificationStatus() async {
    if (widget.userId.isEmpty) {
      if (mounted) {
        setState(() {
          _isCheckingStatus = false;
        });
      }
      return;
    }

    try {
      final status = await ApiService.checkPanelStatus(widget.userId);
      final identityStatus =
          status['identity_status']?.toString().toLowerCase() ?? '';
      final identityVerifiedRaw = status['identity_verified'];
      final identityVerified = identityVerifiedRaw is String
          ? int.tryParse(identityVerifiedRaw) ?? 0
          : (identityVerifiedRaw as int? ?? 0);
      final hasVerificationDoc =
          ((status['verification_document'] ?? status['verification_doc'])
              ?.toString()
              .trim()
              .isNotEmpty ??
          false);
      if (mounted) {
        setState(() {
          _isSubmittedWaitingApproval =
              identityStatus == 'pending' ||
              (identityVerified == 0 && hasVerificationDoc);
          _isCheckingStatus = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingStatus = false;
        });
      }
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _selectedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _uploadDocument() async {
    if (_selectedFilePath == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.uploadVerificationDocument(
        widget.userId,
        _selectedFilePath!,
      );
      if (mounted) {
        if (response['status'] == 'success') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Submitted, waiting for approval.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );

          setState(() {
            _selectedFilePath = null;
            _selectedFileName = null;
          });

          // Show neat success dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFC107).withValues(alpha: 0.22),
                      ),
                      child: const Icon(
                        Icons.mark_email_read_outlined,
                        size: 36,
                        color: Color(0xFF5A3D31),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Submitted for review',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                content: const Text(
                  'Your document is with our team. Please check back within 1 to 24 hours for approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
                actions: <Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                        backgroundColor: const Color(0xFFFFC107),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Go to Dashboard',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.go('/dealer-dashboard');
                      },
                    ),
                  ),
                ],
              );
            },
          );

          if (mounted) {
            setState(() {
              _isSubmittedWaitingApproval = true;
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response['message'] ?? 'Failed to upload document.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppError.userMessage(e, fallback: 'Failed to upload document.'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildWaitingApprovalView(ColorScheme colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const brown = Color(0xFF5A3D31);
    const gold = Color(0xFFFFC107);

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            decoration: BoxDecoration(
              color: isDark ? colors.surfaceContainerLow : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withValues(alpha: 0.28),
                  border: Border.all(color: gold, width: 2),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 44,
                  color: brown,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: gold),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pending_actions_rounded, size: 16, color: brown),
                    SizedBox(width: 6),
                    Text(
                      'UNDER REVIEW',
                      style: TextStyle(
                        color: brown,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
                const SizedBox(height: 16),
                const Text(
                  'Submitted — waiting for approval',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'We received your document. An admin will review it soon. Please check back within 1 to 24 hours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                _buildStepRow(
                  done: true,
                  title: 'Document submitted',
                  subtitle: 'Your file is safely on file',
                ),
                _buildStepRow(
                  active: true,
                  title: 'Admin review',
                  subtitle: 'Usually takes 1–24 hours',
                ),
                _buildStepRow(
                  title: 'Account unlocked',
                  subtitle: 'Full dealer dashboard access',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      setState(() => _isLoading = true);
                      await _loadVerificationStatus();
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                foregroundColor: isDark ? Colors.white : Colors.black87,
                disabledBackgroundColor:
                    isDark ? Colors.white10 : Colors.grey.shade300,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isLoading ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
                    size: 24,
                    color: isDark ? Colors.white : brown,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _isLoading ? 'Checking...' : 'Refresh Status',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => context.go('/dealer-dashboard'),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black87,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.dashboard_rounded,
                    size: 24,
                    color: Colors.black87,
                  ),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Go to Dashboard',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    bool done = false,
    bool active = false,
    required String title,
    required String subtitle,
    bool isLast = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: done
                      ? Colors.green.shade600
                      : active
                          ? const Color(0xFFFFC107)
                          : (isDark ? Colors.white12 : const Color(0xFFEEEAE5)),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done
                        ? Colors.green.shade700
                        : active
                            ? const Color(0xFF8A6500)
                            : (isDark ? Colors.white24 : const Color(0xFFD5CFC7)),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  done
                      ? Icons.check_rounded
                      : active
                          ? Icons.hourglass_top_rounded
                          : Icons.lock_outline_rounded,
                  size: 18,
                  color: done
                      ? Colors.white
                      : (active
                          ? const Color(0xFF5A3D31)
                          : (isDark ? Colors.white70 : Colors.black54)),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 22,
                  margin: const EdgeInsets.only(top: 4),
                  color: isDark ? Colors.white12 : const Color(0xFFE8E4DF),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_isCheckingStatus) {
      return const Scaffold(body: SkeletonProfile());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Identity Verification')),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: _isSubmittedWaitingApproval
              ? _buildWaitingApprovalView(colors)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Verify Your Identity',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'As a landlord or verified agent, you must verify your identity before accessing the dashboard.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.14),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What to upload (required)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Upload ONE clear file that shows either:',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.badge_outlined,
                                color: Color(0xFF8A6500),
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Your NRC (National Registration Card), OR',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.home_work_outlined,
                                color: Color(0xFF8A6500),
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A clear photo of yourself standing next to the property you are listing.',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Accepted formats: JPG, PNG, or PDF. Make sure text/faces are readable.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.upload_file,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Choose NRC or selfie-at-property'),
                          ),
                          if (_selectedFileName != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Selected: $_selectedFileName',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _selectedFilePath != null && !_isLoading
                            ? _uploadDocument
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black87,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : const Text(
                                'Submit Document',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
