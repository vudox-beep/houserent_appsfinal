import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import '../../utils/app_error.dart';

class DealerIdentityVerificationScreen extends StatefulWidget {
  final String userId;
  const DealerIdentityVerificationScreen({super.key, required this.userId});

  @override
  State<DealerIdentityVerificationScreen> createState() => _DealerIdentityVerificationScreenState();
}

class _DealerIdentityVerificationScreenState extends State<DealerIdentityVerificationScreen> {
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
      final status = await ApiService.checkDealerStatus(widget.userId);
      final identityStatus = status['identity_status']?.toString().toLowerCase() ?? '';
      final identityVerifiedRaw = status['identity_verified'];
      final identityVerified = identityVerifiedRaw is String
          ? int.tryParse(identityVerifiedRaw) ?? 0
          : (identityVerifiedRaw as int? ?? 0);
      final hasVerificationDoc =
          ((status['verification_document'] ?? status['verification_doc'])?.toString().trim().isNotEmpty ?? false);
      if (mounted) {
        setState(() {
          _isSubmittedWaitingApproval = identityStatus == 'pending' || (identityVerified == 0 && hasVerificationDoc);
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
      final response = await ApiService.uploadVerificationDocument(widget.userId, _selectedFilePath!);
      print('Upload Response: $response'); // Added print statement to catch what exactly is returning
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.green, size: 28),
                    SizedBox(width: 10),
                    Text('Submitted'),
                  ],
                ),
                content: const Text(
                  'Submitted, waiting for approval.\n\nPlease check back within 1 to 24 hours.',
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                actions: <Widget>[
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF0F2041), // Deep blue
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Go to Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('/dealer-dashboard');
                    },
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
            SnackBar(content: Text(response['message'] ?? 'Failed to upload document.'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppError.userMessage(e, fallback: 'Failed to upload document.')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingStatus) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Identity Verification')),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: _isSubmittedWaitingApproval
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_empty, size: 80, color: Colors.orange),
                    const SizedBox(height: 24),
                    const Text(
                      'Submitted, Waiting For Approval',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Submitted, waiting for approval.\n\nPlease check back within 1 to 24 hours.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                setState(() => _isLoading = true);
                                await _loadVerificationStatus();
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                }
                              },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Status', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => context.go('/dealer-dashboard'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black87,
                        ),
                        child: const Text('Go to Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Verify Your Identity', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const Text('As a dealer, you must verify your identity before accessing the dashboard. Please upload a valid ID (JPG, PNG, or PDF).', style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          Icon(Icons.upload_file, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Select Document'),
                          ),
                          if (_selectedFileName != null) ...[
                            const SizedBox(height: 16),
                            Text('Selected: $_selectedFileName', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ]
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _selectedFilePath != null && !_isLoading ? _uploadDocument : null,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107), foregroundColor: Colors.black87),
                        child: _isLoading ? const CircularProgressIndicator() : const Text('Submit Document', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
        ),
      ),
    );
  }
}
