import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../utils/app_error.dart';

class DealerImageUploadScreen extends StatefulWidget {
  final Map<String, dynamic> propertyData;
  final String? propertyId;
  final bool isEditing;

  const DealerImageUploadScreen({
    super.key,
    required this.propertyData,
    this.propertyId,
    this.isEditing = false,
  });

  @override
  State<DealerImageUploadScreen> createState() => _DealerImageUploadScreenState();
}

class _DealerImageUploadScreenState extends State<DealerImageUploadScreen> {
  final List<XFile> _selectedFiles = [];
  final List<Map<String, dynamic>> _existingImages = [];
  final Set<String> _removedImageIds = {};
  bool _isUploading = false;
  bool _isLoadingExisting = false;
  bool _isLoadingPlan = false;
  bool _isProUser = false;
  final ImagePicker _picker = ImagePicker();
  static const int _freeMaxImages = 9;

  @override
  void initState() {
    super.initState();
    _loadPlanStatus();
    if (widget.isEditing && (widget.propertyId?.isNotEmpty ?? false)) {
      _loadExistingImages();
    }
  }

  Future<void> _loadPlanStatus() async {
    setState(() {
      _isLoadingPlan = true;
    });
    try {
      final subscription = await ApiService.fetchDealerSubscription();
      final profile = await ApiService.getProfile();
      if (!mounted) return;
      setState(() {
        _isProUser = _resolveIsPro(subscription, profile);
      });
    } catch (_) {
      // Default stays free for safety.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPlan = false;
        });
      }
    }
  }

  bool _resolveIsPro(Map<String, dynamic>? subscription, Map<String, dynamic>? profile) {
    String lower(dynamic v) => (v ?? '').toString().trim().toLowerCase();
    final subStatus = lower(subscription?['subscription_status']);
    final planName = lower(subscription?['plan_name']);
    final paidType = lower(profile?['paid_type'] ?? subscription?['paid_type']);
    final accountType = lower(profile?['account_type'] ?? subscription?['account_type']);

    final isExplicitFree = planName.contains('free') || planName.contains('trial') || accountType.contains('free') || paidType.contains('free');
    final isProToken = planName.contains('pro') || accountType.contains('pro') || paidType.contains('pro') || paidType.contains('paid');
    final isActive = subStatus == 'active';

    if (isExplicitFree && !isProToken) return false;
    return isProToken || isActive;
  }

  bool _isVideoFilePath(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov') || p.endsWith('.m4v') || p.endsWith('.avi');
  }

  int _existingImageCountAfterRemovals() {
    return _existingImages.where((img) {
      final id = (img['id'] ?? '').toString();
      if (id.isEmpty) return true;
      return !_removedImageIds.contains(id);
    }).length;
  }

  int _newSelectedImageCount() {
    return _selectedFiles.where((f) => !_isVideoFilePath(f.path)).length;
  }

  Future<void> _loadExistingImages() async {
    final propertyId = widget.propertyId;
    if (propertyId == null || propertyId.isEmpty) return;

    setState(() {
      _isLoadingExisting = true;
    });
    try {
      final details = await ApiService.fetchPropertyDetails(propertyId);
      final rawImages = details['images'];
      if (rawImages is List) {
        final parsed = <Map<String, dynamic>>[];
        for (final img in rawImages) {
          if (img is Map) {
            final map = Map<String, dynamic>.from(img);
            final imageId = (map['id'] ?? '').toString();
            final url = (map['url'] ?? map['image_path'] ?? '').toString().trim();
            if (imageId.isNotEmpty && url.isNotEmpty) {
              parsed.add({
                'id': imageId,
                'url': url,
                'is_main': map['is_main']?.toString() == '1',
              });
            }
          } else if (img is String && img.trim().isNotEmpty) {
            parsed.add({
              'id': '',
              'url': img.trim(),
              'is_main': false,
            });
          }
        }
        if (mounted) {
          setState(() {
            _existingImages
              ..clear()
              ..addAll(parsed);
          });
        }
      }
    } catch (_) {
      // Keep edit flow usable even if existing image fetch fails.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingExisting = false;
        });
      }
    }
  }

  void _removeExistingImage(Map<String, dynamic> image) {
    final id = (image['id'] ?? '').toString();
    if (id.isNotEmpty) {
      _removedImageIds.add(id);
    }
    setState(() {
      _existingImages.removeWhere((e) => (e['id'] ?? '').toString() == id && id.isNotEmpty);
      if (id.isEmpty) {
        _existingImages.remove(image);
      }
    });
  }

  Future<void> _pickFiles() async {
    try {
      // Pick multiple images and optionally a video
      final List<XFile> pickedImages = await _picker.pickMultiImage();
      if (pickedImages.isNotEmpty) {
        if (!_isProUser) {
          final currentImages = _existingImageCountAfterRemovals() + _newSelectedImageCount();
          final allowedRemaining = _freeMaxImages - currentImages;
          if (allowedRemaining <= 0) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Upgrade to Pro to upload 10 or more images. Free accounts can use up to 9 images.')),
              );
            }
            return;
          }

          final capped = pickedImages.take(allowedRemaining).toList();
          setState(() {
            _selectedFiles.addAll(capped);
          });

          if (pickedImages.length > capped.length && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Upgrade to Pro to upload 10 or more images.')),
            );
          }
          return;
        }

        setState(() {
          _selectedFiles.addAll(pickedImages);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e, fallback: 'Unable to pick files.'))),
      );
    }
  }

  Future<void> _pickVideo() async {
    if (!_isProUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video upload is available on Pro only. Please upgrade to Pro.')),
      );
      return;
    }
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          _selectedFiles.add(video);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e, fallback: 'Unable to pick video.'))),
      );
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _submitProperty() async {
    if (!widget.isEditing && _selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one image.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      if (widget.isEditing) {
        final propertyId = widget.propertyId;
        if (propertyId == null || propertyId.isEmpty) {
          throw Exception('Missing property ID for update');
        }

        if (!_isProUser) {
          final totalImagesAfter = _existingImageCountAfterRemovals() + _newSelectedImageCount();
          if (totalImagesAfter > _freeMaxImages) {
            throw Exception('Upgrade to Pro to upload 10 or more images.');
          }
          final hasVideo = _selectedFiles.any((f) => _isVideoFilePath(f.path));
          if (hasVideo) {
            throw Exception('Video upload is available on Pro only.');
          }
        }

        final updateResponse = await ApiService.updateProperty(propertyId, widget.propertyData);
        if (updateResponse['status'] != 'success') {
          throw Exception(updateResponse['message'] ?? 'Failed to update property');
        }

        if (_removedImageIds.isNotEmpty) {
          for (final imageId in _removedImageIds) {
            final removeResp = await ApiService.deletePropertyImage(
              propertyId: propertyId,
              imageId: imageId,
            );
            if (removeResp['status'] != 'success') {
              throw Exception(removeResp['message'] ?? 'Failed to remove image');
            }
          }
        }

        if (_selectedFiles.isNotEmpty) {
          final filePaths = _selectedFiles.map((f) => f.path).toList();
          final addResponse = await ApiService.uploadPropertyImages(propertyId, filePaths);
          if (addResponse['status'] != 'success') {
            throw Exception(addResponse['message'] ?? 'Failed to add new images');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Property updated successfully!')),
          );
          Navigator.of(context).pop();
          Navigator.of(context).pop(true);
        }
      } else {
        if (!_isProUser) {
          final totalImages = _newSelectedImageCount();
          if (totalImages > _freeMaxImages) {
            throw Exception('Upgrade to Pro to upload 10 or more images.');
          }
          final hasVideo = _selectedFiles.any((f) => _isVideoFilePath(f.path));
          if (hasVideo) {
            throw Exception('Video upload is available on Pro only.');
          }
        }

        // 1. Create the property
        final createResponse = await ApiService.createProperty(widget.propertyData);
        if (createResponse['status'] != 'success') {
          throw Exception(createResponse['message'] ?? 'Failed to create property');
        }

        final propertyId = createResponse['property_id'].toString();

        // 2. Upload images/videos
        final filePaths = _selectedFiles.map((f) => f.path).toList();
        final uploadResponse = await ApiService.uploadPropertyImages(propertyId, filePaths);

        if (uploadResponse['status'] != 'success') {
          throw Exception(uploadResponse['message'] ?? 'Failed to upload images');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Property added successfully!')),
          );
          Navigator.of(context).pop();
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        final raw = e.toString().replaceFirst('Exception: ', '').trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(raw.isNotEmpty ? raw : AppError.userMessage(e, fallback: 'Upload failed. Please try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Update Media' : 'Upload Media'),
        backgroundColor: const Color(0xFF5A3D31),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isUploading 
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFFFFC107)),
                SizedBox(height: 16),
                Text('Uploading property and media...', style: TextStyle(fontSize: 16)),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Photos & Video',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isEditing
                      ? 'Select files only if you want to replace current media. The first selected image will become the cover.'
                      : 'The first image will be used as the cover photo. You can select multiple images at once.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                if (_isLoadingPlan)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Checking plan...', style: TextStyle(color: Colors.black54)),
                  )
                else if (!_isProUser)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Free plan limits: up to 9 images, video is locked. Upgrade to Pro for 10+ images and video.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pickFiles,
                        icon: const Icon(Icons.image),
                        label: const Text('Add Images'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pickVideo,
                        icon: const Icon(Icons.video_library),
                        label: const Text('Add Video'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isProUser ? Colors.grey.shade200 : Colors.grey.shade300,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                if (widget.isEditing) ...[
                  const Text('Current Images:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_isLoadingExisting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: CircularProgressIndicator(color: Color(0xFFFFC107)),
                    )
                  else if (_existingImages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12.0),
                      child: Text('No existing images found for this listing.', style: TextStyle(color: Colors.black54)),
                    )
                  else
                    SizedBox(
                      height: 130,
                      child: GridView.builder(
                        scrollDirection: Axis.horizontal,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1,
                        ),
                        itemCount: _existingImages.length,
                        itemBuilder: (context, index) {
                          final image = _existingImages[index];
                          final imageUrl = (image['url'] ?? '').toString();
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, _, __) => const Center(child: Icon(Icons.image_not_supported)),
                                ),
                              ),
                              if (image['is_main'] == true)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFC107),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Current Cover', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeExistingImage(image),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                
                if (_selectedFiles.isNotEmpty) ...[
                  const Text('Selected Files:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        final file = _selectedFiles[index];
                        final isVideo = file.path.toLowerCase().endsWith('.mp4') || file.path.toLowerCase().endsWith('.mov');
                        
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: isVideo 
                                ? Container(
                                    color: Colors.black12,
                                    child: const Center(child: Icon(Icons.videocam, size: 40, color: Colors.black54)),
                                  )
                                : Image.file(
                                    File(file.path),
                                    fit: BoxFit.cover,
                                  ),
                            ),
                            if (index == 0 && !isVideo)
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC107),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Cover', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => _removeFile(index),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ] else
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('No media selected yet', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      bottomNavigationBar: _isUploading ? null : Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: const Text('Back'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: (!widget.isEditing && _selectedFiles.isEmpty) ? null : _submitProperty,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107), // Yellow theme for final action
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  elevation: 0,
                ),
                child: Text(
                  widget.isEditing ? 'Update Property' : 'Publish Property',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
