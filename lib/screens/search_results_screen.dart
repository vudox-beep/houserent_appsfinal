import 'package:flutter/material.dart';
import '../widgets/app_logo.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/api_service.dart';
import 'home_screen.dart'; // for PropertyCard

class _MapItem {
  final String id;
  final LatLng position;
  final dynamic property;

  const _MapItem({
    required this.id,
    required this.position,
    required this.property,
  });
}

class SearchResultsScreen extends StatefulWidget {
  final Map<String, String> searchParams;

  const SearchResultsScreen({super.key, required this.searchParams});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  List<dynamic> _properties = [];
  bool _isLoading = true;
  String _selectedCategory = 'All';
  bool _isMapView = false;
  GoogleMapController? _mapController;
  CameraPosition? _cameraPosition;
  Timer? _mapRebuildDebounce;
  bool _clusterEnabled = true;
  bool _radiusEnabled = false;
  double _radiusKm = 5.0;
  List<_MapItem> _mapItems = [];
  Set<Marker> _mapMarkers = {};
  final LatLng _defaultCenter = const LatLng(-15.4167, 28.2833);

  final List<Map<String, dynamic>> _categories = [
    {'label': 'All', 'type': '', 'purpose': ''},
    {'label': 'For Rent', 'type': '', 'purpose': 'rent'},
    {'label': 'For Sale', 'type': '', 'purpose': 'sale'},
    {'label': 'Boarding Houses', 'type': 'boarding_house', 'purpose': ''},
    {'label': 'Land for Sale', 'type': 'land', 'purpose': 'sale'},
    {'label': 'Apartments', 'type': 'apartment', 'purpose': ''},
    {'label': 'Studios', 'type': 'studio', 'purpose': ''},
    {'label': 'Wedding Lodges', 'type': 'wedding_lodge', 'purpose': ''},
    {'label': 'Shop / Commercial', 'type': 'shop', 'purpose': ''},
    {'label': 'Office Space', 'type': 'office', 'purpose': ''},
  ];

  @override
  void initState() {
    super.initState();
    _isMapView = (widget.searchParams['view'] ?? '').toLowerCase() == 'map';
    // Pre-select category based on initial params
    final initType = widget.searchParams['type'] ?? '';
    final initPurpose = widget.searchParams['purpose'] ?? '';

    // Explicitly handle "For Rent" / "For Sale" / "Land for Sale" overlaps
    if (initType == 'land' && initPurpose == 'sale') {
      _selectedCategory = 'Land for Sale';
    } else if (initType == '' && initPurpose == 'rent') {
      _selectedCategory = 'For Rent';
    } else if (initType == '' && initPurpose == 'sale') {
      _selectedCategory = 'For Sale';
    } else {
      for (var cat in _categories) {
        if (cat['type'] == initType &&
            cat['label'] != 'All' &&
            cat['label'] != 'For Rent' &&
            cat['label'] != 'For Sale' &&
            cat['label'] != 'Land for Sale') {
          _selectedCategory = cat['label'];
          break;
        }
      }
    }

    _fetchResults();
  }

  LatLng? _propertyLatLng(dynamic property) {
    final latRaw = property is Map ? property['latitude'] : null;
    final lngRaw = property is Map ? property['longitude'] : null;
    final lat = double.tryParse(latRaw?.toString() ?? '');
    final lng = double.tryParse(lngRaw?.toString() ?? '');
    if (lat == null || lng == null) return null;
    if (lat.isNaN || lng.isNaN) return null;
    return LatLng(lat, lng);
  }

  String? _propertyImageUrl(dynamic property) {
    if (property is! Map) return null;

    String? imageUrl;
    final mainImage = property['main_image']?.toString().trim();
    if (mainImage != null && mainImage.isNotEmpty) {
      imageUrl = mainImage.replaceAll('`', '').trim();
    } else if (property['images'] != null && property['images'].isNotEmpty) {
      final firstImage = property['images'][0];
      if (firstImage is Map && firstImage['url'] != null) {
        imageUrl = firstImage['url'].toString().replaceAll('`', '').trim();
      } else if (firstImage is String) {
        imageUrl = firstImage.replaceAll('`', '').trim();
      }
    }

    if (imageUrl == null || imageUrl.isEmpty) return null;

    if (imageUrl.startsWith('http')) return imageUrl;

    var imagePath = imageUrl;
    if (imagePath.startsWith('/')) imagePath = imagePath.substring(1);

    if (imagePath.startsWith('assets/')) {
      return 'https://houseforrent.site/$imagePath';
    }
    if (imagePath.startsWith('uploads/')) {
      return 'https://houseforrent.site/php_backend/api/$imagePath';
    }
    return 'https://houseforrent.site/assets/$imagePath';
  }

  Marker _propertyMarker(_MapItem item) {
    return Marker(
      markerId: MarkerId(item.id),
      position: item.position,
      onTap: () => _openMarkerSheet(item.property),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
    );
  }

  double _distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final h =
        sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLng * sinDLng;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  double _clusterCellDegrees(double zoom) {
    final scale = math.pow(2.0, zoom).toDouble();
    final cell = 20.0 / scale;
    if (cell < 0.002) return 0.002;
    if (cell > 1.0) return 1.0;
    return cell;
  }

  Set<Marker> _clusterMarkers(List<_MapItem> items, double zoom) {
    final cell = _clusterCellDegrees(zoom);
    final groups = <String, List<_MapItem>>{};

    for (final item in items) {
      final gx = (item.position.latitude / cell).floor();
      final gy = (item.position.longitude / cell).floor();
      final key = '$gx,$gy';
      (groups[key] ??= []).add(item);
    }

    final markers = <Marker>{};
    for (final entry in groups.entries) {
      final group = entry.value;
      if (group.length == 1) {
        markers.add(_propertyMarker(group.first));
        continue;
      }

      final avgLat =
          group.map((e) => e.position.latitude).reduce((a, b) => a + b) /
          group.length;
      final avgLng =
          group.map((e) => e.position.longitude).reduce((a, b) => a + b) /
          group.length;
      final pos = LatLng(avgLat, avgLng);
      final count = group.length;
      final markerId = 'cluster_${entry.key}_$count';

      markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: pos,
          infoWindow: InfoWindow(title: '$count homes'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          onTap: () {
            final controller = _mapController;
            final current = _cameraPosition;
            if (controller == null || current == null) return;
            final nextZoom = (current.zoom + 2).clamp(10.0, 18.0);
            controller.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: pos, zoom: nextZoom),
              ),
            );
          },
        ),
      );
    }

    return markers;
  }

  void _rebuildMapMarkers() {
    final camera = _cameraPosition;
    final center = camera?.target;
    final zoom = camera?.zoom ?? 12.0;

    final baseItems = _mapItems;
    List<_MapItem> visible = baseItems;
    if (_radiusEnabled && center != null) {
      visible = visible
          .where((e) => _distanceKm(center, e.position) <= _radiusKm)
          .toList();
    }

    final Set<Marker> markers;
    if (_clusterEnabled) {
      markers = _clusterMarkers(visible, zoom);
    } else {
      markers = visible.map(_propertyMarker).toSet();
    }

    if (!mounted) return;
    setState(() {
      _mapMarkers = markers;
    });
  }

  LatLng _initialCenterFor(Set<Marker> markers) {
    if (markers.isEmpty) return _defaultCenter;
    return markers.first.position;
  }

  void _fitToMarkers(GoogleMapController controller, Set<Marker> markers) {
    if (markers.isEmpty) return;
    double? minLat, maxLat, minLng, maxLng;
    for (final m in markers) {
      final lat = m.position.latitude;
      final lng = m.position.longitude;
      minLat = minLat == null ? lat : (lat < minLat ? lat : minLat);
      maxLat = maxLat == null ? lat : (lat > maxLat ? lat : maxLat);
      minLng = minLng == null ? lng : (lng < minLng ? lng : minLng);
      maxLng = maxLng == null ? lng : (lng > maxLng ? lng : maxLng);
    }
    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _openMarkerSheet(dynamic property) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final id = (property is Map ? property['id'] : null)?.toString() ?? '';
    final title =
        (property is Map ? property['title'] : null)?.toString() ?? '';
    final city = (property is Map ? property['city'] : null)?.toString() ?? '';
    final country =
        (property is Map ? property['country'] : null)?.toString() ?? '';
    final location = [city, country].where((e) => e.isNotEmpty).join(', ');
    final currency =
        (property is Map ? property['currency'] : null)?.toString() ?? 'ZMW';
    final price =
        (property is Map ? property['price'] : null)?.toString() ?? '0';
    final imageUrl = _propertyImageUrl(property);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                width: 44,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              if (imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: isDark ? Colors.white10 : Colors.black12,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                title.isEmpty ? 'Property' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  location,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '$currency $price',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFC107),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      onPressed: id.isEmpty
                          ? null
                          : () {
                              Navigator.pop(context);
                              this.context.push('/property/$id');
                            },
                      child: const Text(
                        'View details',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      side: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchResults() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Ensure we pass the parameters correctly, avoiding any nulls or empty strings
      // if they aren't meant to be queried.
      final cleanParams = Map<String, String>.from(widget.searchParams)
        ..removeWhere((key, value) => value.trim().isEmpty);

      // Override with selected category params if not 'All'
      final cat = _categories.firstWhere(
        (c) => c['label'] == _selectedCategory,
      );
      if (cat['type'] != '')
        cleanParams['type'] = cat['type'];
      else if (_selectedCategory != 'All')
        cleanParams.remove('type');

      if (cat['purpose'] != '')
        cleanParams['purpose'] = cat['purpose'];
      else if (_selectedCategory != 'All')
        cleanParams.remove('purpose');

      // Fetch ALL properties and apply completely robust client-side filtering
      // because the backend SQL queries often fail on case mapping or string structure
      final results = await ApiService.fetchProperties({});

      final zedBineTypes = ['salon', 'gadget', 'mechanic', 'other_service'];
      List<dynamic> filteredResults = results.where((p) {
        final type = (p['property_type'] ?? p['type'] ?? '')
            .toString()
            .toLowerCase();
        return !zedBineTypes.contains(type);
      }).toList();

      if (cleanParams.containsKey('type')) {
        final type = cleanParams['type']!.toLowerCase().trim();
        filteredResults = filteredResults.where((p) {
          final pType =
              (p['property_type']?.toString() ?? p['type']?.toString() ?? '')
                  .toLowerCase()
                  .trim();

          if (type == 'boarding_house' && pType.contains('boarding'))
            return true;
          if (type == 'wedding_lodge' && pType.contains('wedding')) return true;
          if (type == 'studio' && pType.contains('studio')) return true;
          if (type == 'land' && pType.contains('land')) return true;
          if (type == 'apartment' && pType.contains('apartment')) return true;
          if (type == 'shop' && pType.contains('shop')) return true;
          if (type == 'office' && pType.contains('office')) return true;
          if (type == 'house' && pType == 'house') return true;

          return pType == type || pType.replaceAll(' ', '_') == type;
        }).toList();
      }

      if (cleanParams.containsKey('purpose')) {
        final purpose = cleanParams['purpose']!.toLowerCase();
        filteredResults = filteredResults.where((p) {
          final pPurpose =
              (p['purpose']?.toString() ??
                      p['listing_purpose']?.toString() ??
                      '')
                  .toLowerCase();
          return pPurpose.contains(purpose);
        }).toList();
      }

      if (cleanParams.containsKey('featured') ||
          cleanParams.containsKey('is_featured')) {
        filteredResults = filteredResults.where((p) {
          return p['is_featured']?.toString() == '1';
        }).toList();
      }

      // Advanced Search parameters
      if (cleanParams.containsKey('location')) {
        final loc = cleanParams['location']!.toLowerCase().trim();
        filteredResults = filteredResults.where((p) {
          final pLocation = (p['location']?.toString() ?? '').toLowerCase();
          final pAddress = (p['address']?.toString() ?? '').toLowerCase();
          final pTitle = (p['title']?.toString() ?? '').toLowerCase();
          final pCity = (p['city']?.toString() ?? '').toLowerCase();
          final pCountry = (p['country']?.toString() ?? '').toLowerCase();
          final joinedCityCountry = [
            pCity,
            pCountry,
          ].where((e) => e.isNotEmpty).join(', ');
          final joinedCountryCity = [
            pCountry,
            pCity,
          ].where((e) => e.isNotEmpty).join(', ');
          final searchable = [
            pLocation,
            pAddress,
            pTitle,
            pCity,
            pCountry,
            joinedCityCountry,
            joinedCountryCity,
          ].join(' | ');
          return searchable.contains(loc);
        }).toList();
      }

      if (cleanParams.containsKey('city')) {
        final city = cleanParams['city']!.toLowerCase().trim();
        filteredResults = filteredResults.where((p) {
          final pCity = (p['city']?.toString() ?? '').toLowerCase();
          return pCity == city || pCity.contains(city);
        }).toList();
      }

      if (cleanParams.containsKey('country')) {
        final country = cleanParams['country']!.toLowerCase().trim();
        filteredResults = filteredResults.where((p) {
          final pCountry = (p['country']?.toString() ?? '').toLowerCase();
          return pCountry == country || pCountry.contains(country);
        }).toList();
      }

      if (cleanParams.containsKey('bedrooms')) {
        final beds = cleanParams['bedrooms']!;
        filteredResults = filteredResults.where((p) {
          final pBeds = p['bedrooms']?.toString() ?? '0';
          if (beds == '5' &&
              int.tryParse(pBeds) != null &&
              int.parse(pBeds) >= 5)
            return true;
          return pBeds == beds;
        }).toList();
      }

      if (cleanParams.containsKey('minPrice')) {
        final minP = double.tryParse(cleanParams['minPrice']!) ?? 0;
        filteredResults = filteredResults.where((p) {
          final price =
              double.tryParse(
                p['price']?.toString().replaceAll(',', '') ?? '0',
              ) ??
              0;
          return price >= minP;
        }).toList();
      }

      if (cleanParams.containsKey('maxPrice')) {
        final maxP =
            double.tryParse(cleanParams['maxPrice']!) ?? double.infinity;
        filteredResults = filteredResults.where((p) {
          final price =
              double.tryParse(
                p['price']?.toString().replaceAll(',', '') ?? '0',
              ) ??
              0;
          return price <= maxP;
        }).toList();
      }

      if (mounted) {
        final items = <_MapItem>[];
        for (final p in filteredResults) {
          final pos = _propertyLatLng(p);
          if (pos == null) continue;
          final id = (p is Map ? p['id'] : null)?.toString();
          if (id == null || id.isEmpty) continue;
          items.add(_MapItem(id: id, position: pos, property: p));
        }

        setState(() {
          _properties = filteredResults;
          _mapItems = items;
          _isLoading = false;
        });

        _rebuildMapMarkers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load search results')),
        );
      }
    }
  }

  @override
  void dispose() {
    _mapRebuildDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => context.go('/home'),
          child: Row(
            children: [
              const AppBrand(textColor: Colors.white),
              if (MediaQuery.of(context).size.width > 350) ...[
                const SizedBox(width: 8),
                const Text(
                  '| Search Results',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ],
          ),
        ),
        backgroundColor: isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFFFC107),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            context.go(
              '/home',
            ); // Always go directly home to prevent stack loops
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isMapView ? Icons.grid_view_rounded : Icons.map_outlined,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _isMapView = !_isMapView),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: () {
              context.go('/advanced-search');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Summary Row
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_properties.length} Properties Found',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // Filter Chips
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category['label'];

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(category['label']),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = category['label'];
                        });
                        _fetchResults();
                      }
                    },
                    selectedColor: const Color(0xFFFFC107),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.black87
                          : (isDark ? Colors.white70 : Colors.black54),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF2C2C2C)
                        : Colors.grey.shade100,
                  ),
                );
              },
            ),
          ),

          // Results Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _properties.isEmpty
                ? const Center(
                    child: Text(
                      'No properties found matching your criteria',
                      style: TextStyle(fontSize: 18),
                    ),
                  )
                : _isMapView
                ? _buildMapView(context)
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 16.0,
                    ),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.of(context).size.width > 800
                            ? 4
                            : (MediaQuery.of(context).size.width > 500 ? 3 : 2),
                        childAspectRatio:
                            MediaQuery.of(context).size.width < 400
                            ? 0.52
                            : 0.60,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _properties.length,
                      itemBuilder: (context, index) {
                        return PropertyCard(
                          property: _properties[index],
                          isFeatured:
                              _properties[index]['is_featured']?.toString() ==
                              '1',
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canShowInteractiveMap =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!canShowInteractiveMap) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 48,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(height: 10),
              Text(
                'Map View is unavailable on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Switch back to Grid View to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black87,
                ),
                onPressed: () => setState(() => _isMapView = false),
                child: const Text('Go to Grid View'),
              ),
            ],
          ),
        ),
      );
    }

    final markers = _mapMarkers;
    final initialTarget = _initialCenterFor(markers);

    if (_mapItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 48,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(height: 10),
              Text(
                'No homes have map coordinates yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You can still browse in Grid View.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black87,
                ),
                onPressed: () => setState(() => _isMapView = false),
                child: const Text('Go to Grid View'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialTarget,
            zoom: 12.0,
          ),
          markers: markers,
          onMapCreated: (controller) {
            _mapController = controller;
            _cameraPosition = CameraPosition(target: initialTarget, zoom: 12.0);
            _rebuildMapMarkers();
            _fitToMarkers(controller, markers);
          },
          onCameraMove: (position) {
            _cameraPosition = position;
            _mapRebuildDebounce?.cancel();
            _mapRebuildDebounce = Timer(const Duration(milliseconds: 220), () {
              _rebuildMapMarkers();
            });
          },
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_pin, color: Color(0xFFFFC107)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_mapItems.length} listings • ${markers.length} pins',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fit pins',
                      onPressed: () {
                        final controller = _mapController;
                        if (controller == null) return;
                        _fitToMarkers(controller, markers);
                      },
                      icon: Icon(
                        Icons.center_focus_strong,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cluster pins',
                      onPressed: () {
                        setState(() => _clusterEnabled = !_clusterEnabled);
                        _rebuildMapMarkers();
                      },
                      icon: Icon(
                        Icons.hub_outlined,
                        color: _clusterEnabled
                            ? const Color(0xFFFFC107)
                            : (isDark ? Colors.white54 : Colors.black45),
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Radius filter',
                      onPressed: () {
                        setState(() => _radiusEnabled = !_radiusEnabled);
                        _rebuildMapMarkers();
                      },
                      icon: Icon(
                        Icons.circle_outlined,
                        color: _radiusEnabled
                            ? const Color(0xFFFFC107)
                            : (isDark ? Colors.white54 : Colors.black45),
                        size: 20,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isMapView = false),
                      child: const Text('Grid'),
                    ),
                  ],
                ),
                if (_radiusEnabled) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Radius: ${_radiusKm.toStringAsFixed(0)} km',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _radiusKm = 5.0;
                          });
                          _rebuildMapMarkers();
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  Slider(
                    value: _radiusKm,
                    min: 1,
                    max: 25,
                    divisions: 24,
                    activeColor: const Color(0xFFFFC107),
                    onChanged: (v) {
                      setState(() => _radiusKm = v);
                      _rebuildMapMarkers();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
