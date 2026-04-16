import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../utils/app_error.dart';
import 'dealer_add_property_screen.dart';

class DealerPropertiesScreen extends StatefulWidget {
  const DealerPropertiesScreen({super.key});

  @override
  State<DealerPropertiesScreen> createState() => _DealerPropertiesScreenState();
}

class _DealerPropertiesScreenState extends State<DealerPropertiesScreen> {
  List<dynamic> _properties = [];
  bool _isLoading = true;

  String? _propertyIdOf(dynamic property) {
    if (property is! Map) return null;
    final map = Map<String, dynamic>.from(property);
    final id = map['id'] ?? map['property_id'] ?? map['propertyId'];
    final parsed = id?.toString().trim();
    if (parsed == null || parsed.isEmpty) return null;
    return parsed;
  }

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  Future<void> _loadProperties() async {
    try {
      final response = await ApiService.fetchDealerProperties();
      if (mounted) {
        setState(() {
          // fetchDealerProperties returns {'status': 'success', 'data': [...]}
          // However, the backend might return the JSON array directly and ApiService puts it in 'data'.
          if (response['status'] == 'success') {
            final data = response['data'];
            if (data is List) {
              _properties = data;
            } else if (data is Map && data['properties'] != null) {
              _properties = data['properties'];
            } else if (data is Map && data['data'] != null) {
              _properties = data['data'];
            } else {
              _properties = [];
            }
          } else {
            _properties = [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppError.userMessage(e, fallback: 'Failed to load properties.'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              const Text('My Properties', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F2041))),
              ElevatedButton.icon(
                onPressed: () async {
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DealerAddPropertyScreen()),
                  );
                  if (updated == true && mounted) {
                    _loadProperties();
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add New Property', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107), // Updated to match yellow theme
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoading)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (_properties.isEmpty)
                    const Expanded(child: Center(child: Text('No properties found. Add one!', style: TextStyle(color: Colors.black54))))
                  else
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth > 1108 ? constraints.maxWidth : 1108), // 300+120+120+100+120+120+180 + 48 padding
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                    ),
                                    child: Row(
                                      children: const [
                                        SizedBox(width: 300, child: Text('PROPERTY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 120, child: Text('TYPE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 120, child: Text('PRICE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 100, child: Text('VIEWS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 120, child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 120, child: Text('DATE ADDED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 180, child: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                      ],
                                    ),
                                  ),
                                      Expanded(
                                        child: SizedBox(
                                          width: constraints.maxWidth > 1108 ? constraints.maxWidth : 1108,
                                          child: ListView.separated(
                                  itemCount: _properties.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final property = _properties[index];
                                    final title = property['title'] ?? 'Unknown Property';
                                    final location = property['location'] ?? 'Unknown Location';
                                    final type = property['property_type'] ?? property['type'] ?? 'House';
                                    final currency = property['currency'] ?? 'ZMW';
                                    final price = property['price'] ?? '0';
                                    final views = property['views'] ?? 0;
                                    final status = property['status'] ?? 'Available';
                                    
                                    // Mock date for UI display if not available in API
                                    final dateStr = property['created_at'] ?? 'Mar 02, 2026';
                                    final parts = dateStr.toString().split(' ');
                                    final displayDate = parts.isNotEmpty ? parts[0] : 'Mar 02, 2026';

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 300,
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade100,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: (() {
                                                    String? imageUrl;
                                                    
                                                    if (property['main_image'] != null && property['main_image'].toString().isNotEmpty) {
                                                      String mainImg = property['main_image'].toString().trim();
                                                      mainImg = mainImg.replaceAll('`', '');
                                                      imageUrl = mainImg;
                                                    } else if (property['images'] != null && property['images'].isNotEmpty) {
                                                      var firstImage = property['images'][0];
                                                      if (firstImage is Map && firstImage['url'] != null) {
                                                        String urlStr = firstImage['url'].toString().trim();
                                                        urlStr = urlStr.replaceAll('`', '');
                                                        imageUrl = urlStr;
                                                      } else if (firstImage is String) {
                                                        String path = firstImage.trim();
                                                        path = path.replaceAll('`', '');
                                                        
                                                        if (path.startsWith('http')) {
                                                          imageUrl = path;
                                                        } else {
                                                          if (path.startsWith('/')) path = path.substring(1);
                                                          if (path.startsWith('assets/')) {
                                                            imageUrl = 'https://houseforrent.site/$path';
                                                          } else if (path.startsWith('uploads/')) {
                                                            imageUrl = 'https://houseforrent.site/php_backend/api/$path';
                                                          } else {
                                                            if (!path.startsWith('assets/')) {
                                                              imageUrl = 'https://houseforrent.site/assets/$path';
                                                            } else {
                                                              imageUrl = 'https://houseforrent.site/$path';
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                    return imageUrl != null
                                                        ? ClipRRect(
                                                            borderRadius: BorderRadius.circular(8),
                                                            child: Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Icon(Icons.image, color: Colors.grey.shade400))
                                                          )
                                                        : Icon(Icons.home, color: Colors.grey.shade600);
                                                  })(),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F2041)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.location_on_outlined, size: 14, color: Colors.black54),
                                                          const SizedBox(width: 4),
                                                          Expanded(child: Text(location, style: const TextStyle(color: Colors.black54, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: Text(
                                              type,
                                              style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: Text(
                                              '$currency $price',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFC107)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 100, 
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.remove_red_eye, size: 14, color: Colors.black54),
                                                    const SizedBox(width: 4),
                                                    Flexible(child: Text('$views', style: const TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis)),
                                                  ],
                                                ),
                                              ),
                                            )
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  status.toUpperCase(),
                                                  style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: Text(
                                              displayDate,
                                              style: const TextStyle(color: Colors.black54),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 180, // Use explicit width instead of Expanded to fix 'no size' error
                                            child: Wrap(
                                              spacing: 4,
                                              runSpacing: 4,
                                              children: [
                                                _buildActionButton(Icons.edit_outlined, () => _editProperty(property)),
                                                _buildStatusToggleAction(property),
                                                _buildActionButton(Icons.visibility_outlined, () => _viewProperty(property)),
                                                _buildActionButton(Icons.delete_outline, () => _confirmDeleteProperty(property)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              )),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
    )],
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black54, size: 16),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildStatusToggleAction(dynamic property) {
    final status = (property['status'] ?? 'available').toString().toLowerCase();
    final isTaken = status == 'taken';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: isTaken ? Colors.green.shade300 : Colors.orange.shade300),
        borderRadius: BorderRadius.circular(4),
        color: isTaken ? Colors.green.shade50 : Colors.orange.shade50,
      ),
      child: IconButton(
        icon: Icon(isTaken ? Icons.check_circle : Icons.check_circle_outline, 
                   color: isTaken ? Colors.green.shade700 : Colors.orange.shade700, size: 16),
        tooltip: isTaken ? 'Mark as Available' : 'Mark as Taken',
        onPressed: () => _togglePropertyStatus(property),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Future<void> _togglePropertyStatus(dynamic property) async {
    final propertyId = _propertyIdOf(property);
    if (propertyId == null) return;
    
    final currentStatus = (property['status'] ?? 'available').toString().toLowerCase();
    final newStatus = currentStatus == 'taken' ? 'available' : 'taken';
    
    try {
      final response = await ApiService.updatePropertyStatus(propertyId, newStatus);
      if (response['status'] == 'success') {
        _loadProperties(); // Reload properties to show updated status
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Property marked as $newStatus')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Failed to update status')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status')),
      );
    }
  }

  Future<void> _editProperty(dynamic property) async {
    final propertyMap = Map<String, dynamic>.from(property);
    propertyMap['id'] = _propertyIdOf(property);
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DealerAddPropertyScreen(
          propertyToEdit: propertyMap,
        ),
      ),
    );

    if (updated == true && mounted) {
      _loadProperties();
    }
  }

  void _viewProperty(dynamic property) {
    final propertyId = _propertyIdOf(property);
    if (propertyId == null || propertyId.isEmpty) return;
    context.push('/property/$propertyId');
  }

  Future<void> _confirmDeleteProperty(dynamic property) async {
    final propertyId = _propertyIdOf(property);
    if (propertyId == null || propertyId.isEmpty) return;

    final title = property['title']?.toString() ?? 'this property';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Property'),
          content: Text('Are you sure you want to delete "$title"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      final response = await ApiService.deleteProperty(propertyId);
      if (response['status'] == 'success') {
        if (!mounted) return;
        _loadProperties();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Property deleted successfully')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Failed to delete property')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e, fallback: 'Failed to delete property.'))),
      );
    }
  }
}
