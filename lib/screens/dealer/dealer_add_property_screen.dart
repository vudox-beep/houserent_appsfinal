import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dealer_image_upload_screen.dart';

class DealerAddPropertyScreen extends StatefulWidget {
  final Map<String, dynamic>? propertyToEdit;

  const DealerAddPropertyScreen({super.key, this.propertyToEdit});

  @override
  State<DealerAddPropertyScreen> createState() => _DealerAddPropertyScreenState();
}

class _DealerAddPropertyScreenState extends State<DealerAddPropertyScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Form controllers
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsController = TextEditingController();
  final _totalRoomsController = TextEditingController();
  final _sizeController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _addressController = TextEditingController();
  final _videoUrlController = TextEditingController();
  
  // New controllers for specific categories
  final _capacityController = TextEditingController();
  final _peoplePerRoomController = TextEditingController();
  final _eventTypeController = TextEditingController();
  
  bool _cateringAvailable = false;
  bool _equipmentAvailable = false;

  String _currency = 'ZMW';
  String _propertyType = 'Apartment';
  String _purpose = 'Rent';
  
  final List<String> _propertyTypes = [
    'House', 
    'Apartment', 
    'Boarding Houses', 
    'Wedding Lodges', 
    'Studios',
    'Land for Sale',
    'Shop / Commercial',
    'Office Space'
  ];

  final List<String> _purposes = ['Rent', 'Sale', 'Service'];
  
  final List<String> _amenitiesOptions = [
    'WiFi',
    'Parking',
    'Swimming Pool',
    'Gym',
    'Air Conditioning',
    'Security',
    'Balcony',
    'Furnished'
  ];
  final List<String> _selectedAmenities = [];

  final List<String> _africanCountries = [
    'Algeria', 'Angola', 'Benin', 'Botswana', 'Burkina Faso', 'Burundi', 'Cabo Verde', 
    'Cameroon', 'Central African Republic', 'Chad', 'Comoros', 'Congo (Congo-Brazzaville)', 
    'Democratic Republic of the Congo', 'Djibouti', 'Egypt', 'Equatorial Guinea', 'Eritrea', 
    'Eswatini', 'Ethiopia', 'Gabon', 'Gambia', 'Ghana', 'Guinea', 'Guinea-Bissau', 
    'Ivory Coast', 'Kenya', 'Lesotho', 'Liberia', 'Libya', 'Madagascar', 'Malawi', 'Mali', 
    'Mauritania', 'Mauritius', 'Morocco', 'Mozambique', 'Namibia', 'Niger', 'Nigeria', 
    'Rwanda', 'Sao Tome and Principe', 'Senegal', 'Seychelles', 'Sierra Leone', 'Somalia', 
    'South Africa', 'South Sudan', 'Sudan', 'Tanzania', 'Togo', 'Tunisia', 'Uganda', 
    'Zambia', 'Zimbabwe'
  ];
  String _selectedCountry = 'Zambia';
  
  // Google Maps
  GoogleMapController? _mapController;
  LatLng _selectedLocation = const LatLng(-15.3875, 28.3228); // Default to Lusaka, Zambia
  Set<Marker> _markers = {};
  bool get _isEditing => widget.propertyToEdit != null;

  @override
  void initState() {
    super.initState();
    _prefillForEdit();
    _markers.add(
      Marker(
        markerId: const MarkerId('selected_location'),
        position: _selectedLocation,
        draggable: true,
        onDragEnd: (newPosition) {
          setState(() {
            _selectedLocation = newPosition;
          });
        },
      ),
    );
  }

  void _prefillForEdit() {
    final property = widget.propertyToEdit;
    if (property == null) return;

    String mapType(dynamic rawType) {
      final type = (rawType ?? '').toString().trim().toLowerCase();
      if (type.contains('apartment')) return 'Apartment';
      if (type.contains('boarding')) return 'Boarding Houses';
      if (type.contains('wedding')) return 'Wedding Lodges';
      if (type.contains('studio')) return 'Studios';
      if (type.contains('land')) return 'Land for Sale';
      if (type.contains('shop') || type.contains('commercial')) return 'Shop / Commercial';
      if (type.contains('office')) return 'Office Space';
      return 'House';
    }

    String mapPurpose(dynamic rawPurpose, String propertyType) {
      final purpose = (rawPurpose ?? '').toString().trim().toLowerCase();
      if (purpose.contains('sale') || purpose == 'sell') return 'Sale';
      if (purpose.contains('service')) return 'Service';
      if (purpose.contains('rent')) {
        if (propertyType == 'Wedding Lodges' || propertyType == 'Studios') {
          return 'Service';
        }
        return 'Rent';
      }
      return 'Rent';
    }

    _titleController.text = (property['title'] ?? '').toString();
    _priceController.text = (property['price'] ?? '').toString();
    _descriptionController.text = (property['description'] ?? '').toString();
    _bedroomsController.text = (property['bedrooms'] ?? '').toString();
    _bathroomsController.text = (property['bathrooms'] ?? '').toString();
    _totalRoomsController.text = (property['rooms'] ?? '').toString();
    _sizeController.text = (property['size_sqm'] ?? property['size'] ?? '').toString();
    _cityController.text = (property['city'] ?? '').toString();
    _addressController.text = (property['location'] ?? property['address'] ?? '').toString();
    _videoUrlController.text = (property['video_url'] ?? '').toString();
    _capacityController.text = (property['capacity'] ?? '').toString();
    _peoplePerRoomController.text = (property['people_per_room'] ?? '').toString();
    _eventTypeController.text = (property['event_type'] ?? '').toString();

    _propertyType = mapType(property['property_type'] ?? property['type']);
    _purpose = mapPurpose(property['listing_purpose'] ?? property['purpose'], _propertyType);
    _currency = ((property['currency'] ?? 'ZMW').toString().trim().isEmpty)
        ? 'ZMW'
        : (property['currency'] ?? 'ZMW').toString().trim();
    final incomingCountry = ((property['country'] ?? 'Zambia').toString().trim().isEmpty)
        ? 'Zambia'
        : (property['country'] ?? 'Zambia').toString().trim();
    _selectedCountry = _africanCountries.contains(incomingCountry) ? incomingCountry : 'Zambia';

    final amenitiesRaw = (property['amenities'] ?? '').toString();
    if (amenitiesRaw.isNotEmpty) {
      _selectedAmenities
        ..clear()
        ..addAll(
          amenitiesRaw
              .split(',')
              .map((a) => a.trim())
              .where((a) => a.isNotEmpty),
        );
    }

    _cateringAvailable = (property['catering_available']?.toString() == '1') || property['catering_available'] == true;
    _equipmentAvailable = (property['equipment_available']?.toString() == '1') || property['equipment_available'] == true;

    final lat = double.tryParse((property['latitude'] ?? '').toString());
    final lng = double.tryParse((property['longitude'] ?? '').toString());
    if (lat != null && lng != null) {
      _selectedLocation = LatLng(lat, lng);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    _totalRoomsController.dispose();
    _sizeController.dispose();
    _cityController.dispose();
    // Country is now a string dropdown value, so no controller to dispose
    _addressController.dispose();
    _videoUrlController.dispose();
    _capacityController.dispose();
    _peoplePerRoomController.dispose();
    _eventTypeController.dispose();
    super.dispose();
  }

  void _saveAndContinue() {
    if (_formKey.currentState!.validate()) {
      // Map frontend types to backend expected values or just pass them as is.
      // Backend expects specific fields based on property_type:
      
      final propertyData = {
        'title': _titleController.text,
        'price': _priceController.text,
        'currency': _currency,
        'property_type': _propertyType, // e.g., 'Boarding Houses', 'Wedding Lodges', 'Studios'
        'listing_purpose': _purpose,
        'description': _descriptionController.text,
        'location': _addressController.text, // API expects 'location'
        'city': _cityController.text,
        'country': _selectedCountry,
        'video_url': _videoUrlController.text,
        'amenities': _selectedAmenities.join(','), // Convert list to comma-separated string for API
        'latitude': _selectedLocation.latitude.toString(),
        'longitude': _selectedLocation.longitude.toString(),
      };

      if (_propertyType == 'Apartment' || _propertyType == 'House') {
        propertyData['bedrooms'] = _bedroomsController.text;
        propertyData['bathrooms'] = _bathroomsController.text;
        propertyData['rooms'] = _totalRoomsController.text;
        propertyData['size_sqm'] = _sizeController.text;
      } else if (_propertyType == 'Boarding Houses') {
        propertyData['capacity'] = _capacityController.text;
        propertyData['people_per_room'] = _peoplePerRoomController.text;
        propertyData['rooms'] = _totalRoomsController.text;
        propertyData['size_sqm'] = _sizeController.text;
      } else if (_propertyType == 'Wedding Lodges' || _propertyType == 'Studios') {
        propertyData['capacity'] = _capacityController.text;
        propertyData['event_type'] = _eventTypeController.text;
        propertyData['catering_available'] = _cateringAvailable ? '1' : '0';
        propertyData['equipment_available'] = _equipmentAvailable ? '1' : '0';
        propertyData['size_sqm'] = _sizeController.text;
      } else {
        propertyData['rooms'] = _totalRoomsController.text;
        propertyData['size_sqm'] = _sizeController.text;
      }

      // Proceed to image upload step
      Navigator.push(
        context, 
        MaterialPageRoute(
          builder: (context) => DealerImageUploadScreen(
            propertyData: propertyData,
            propertyId: _isEditing ? widget.propertyToEdit!['id']?.toString() : null,
            isEditing: _isEditing,
          )
        )
      );
    }
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14),
          children: [
            if (required)
              const TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Property' : 'Add New Property'),
        backgroundColor: const Color(0xFF5A3D31), // Dark brown theme
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Property Title', required: true),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  validator: (value) => value!.isEmpty ? 'Please enter a title' : null,
                ),
                const SizedBox(height: 24),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxWidth < 600;
                    
                    return Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      children: [
                        SizedBox(
                          width: isSmallScreen ? double.infinity : (constraints.maxWidth - 48) / 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Price', required: true),
                              TextFormField(
                                controller: _priceController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: const BorderSide(color: Color(0xFFFFC107)),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  prefixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.only(left: 12.0, right: 4.0),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: _currency,
                                            icon: const Icon(Icons.arrow_drop_down, size: 20),
                                            isDense: true,
                                            items: ['ZMW', 'USD'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14)))).toList(),
                                            onChanged: (val) {
                                              setState(() {
                                                _currency = val!;
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                      Container(
                                        height: 24,
                                        width: 1,
                                        color: Colors.grey.shade300,
                                        margin: const EdgeInsets.only(right: 8.0),
                                      ),
                                    ],
                                  ),
                                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                ),
                                validator: (value) => value!.isEmpty ? 'Required' : null,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: isSmallScreen ? double.infinity : (constraints.maxWidth - 48) / 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Property Type', required: true),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _propertyType,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: _propertyTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)))).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _propertyType = val!;
                                    if (_propertyType == 'Wedding Lodges' || _propertyType == 'Studios') {
                                      _purpose = 'Service';
                                    } else if (_purpose == 'Service') {
                                      _purpose = 'Rent';
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: isSmallScreen ? double.infinity : (constraints.maxWidth - 48) / 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Purpose', required: true),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _purpose,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: _purposes.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)))).toList(),
                                onChanged: (_propertyType == 'Wedding Lodges' || _propertyType == 'Studios') 
                                  ? null 
                                  : (val) => setState(() => _purpose = val!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                ),
                const SizedBox(height: 24),
                
                _buildLabel('Description'),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  validator: (value) => value!.isEmpty ? 'Please enter a description' : null,
                ),
                const SizedBox(height: 24),
                  
                  // Dynamic Fields Based on Property Type
                  if (_propertyType == 'Apartment' || _propertyType == 'House') ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Bedrooms'),
                              TextFormField(
                                controller: _bedroomsController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Bathrooms'),
                              TextFormField(
                                controller: _bathroomsController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Total Rooms'),
                              TextFormField(
                                controller: _totalRoomsController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Size (sqm)'),
                              TextFormField(
                                controller: _sizeController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ] else if (_propertyType == 'Boarding Houses') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _capacityController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Total Capacity', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _peoplePerRoomController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'People per Room', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ] else if (_propertyType == 'Wedding Lodges' || _propertyType == 'Studios') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _capacityController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Capacity (People)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _eventTypeController,
                            decoration: const InputDecoration(labelText: 'Event Type (e.g., Weddings)', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            title: const Text('Catering Available', style: TextStyle(fontSize: 14)),
                            value: _cateringAvailable,
                            onChanged: (val) => setState(() => _cateringAvailable = val ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            title: const Text('Equipment Available', style: TextStyle(fontSize: 14)),
                            value: _equipmentAvailable,
                            onChanged: (val) => setState(() => _equipmentAvailable = val ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    // Default for Commercial, Land, etc.
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _totalRoomsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Total Rooms', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _sizeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Size (sqft/sqm)', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('City', required: true),
                            TextFormField(
                              controller: _cityController,
                              decoration: InputDecoration(
                                hintText: 'e.g. Lusaka',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              validator: (value) => value!.isEmpty ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Country', required: true),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _selectedCountry,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              items: _africanCountries.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)))).toList(),
                              onChanged: (val) => setState(() => _selectedCountry = val!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  _buildLabel('Address / Location', required: true),
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      hintText: 'Specific Area, Street',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    validator: (value) => value!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  const Text('Click on the map to pin the exact location.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),
                  
                  // Map Placeholder
                  Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) 
                      ? GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _selectedLocation,
                            zoom: 14.0,
                          ),
                          markers: _markers,
                          onMapCreated: (GoogleMapController controller) {
                            _mapController = controller;
                          },
                          onTap: (LatLng location) {
                            setState(() {
                              _selectedLocation = location;
                              _markers.clear();
                              _markers.add(
                                Marker(
                                  markerId: const MarkerId('selected_location'),
                                  position: _selectedLocation,
                                  draggable: true,
                                  onDragEnd: (newPosition) {
                                    setState(() {
                                      _selectedLocation = newPosition;
                                    });
                                  },
                                ),
                              );
                            });
                          },
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('Interactive Map unavailable on this device.', style: TextStyle(color: Colors.grey.shade600)),
                              Text('Coordinates: ${_selectedLocation.latitude}, ${_selectedLocation.longitude}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  _buildLabel('Amenities'),
                  TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'e.g. WiFi, Parking, Pool, Gym (Comma separated)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _amenitiesOptions.map((amenity) {
                      final isSelected = _selectedAmenities.contains(amenity);
                      return FilterChip(
                        label: Text(amenity, style: TextStyle(color: isSelected ? Colors.black87 : Colors.grey.shade700, fontSize: 13)),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              _selectedAmenities.add(amenity);
                            } else {
                              _selectedAmenities.remove(amenity);
                            }
                          });
                        },
                        selectedColor: const Color(0xFFFFC107).withOpacity(0.3),
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? const Color(0xFFFFC107) : Colors.grey.shade300),
                        ),
                        checkmarkColor: const Color(0xFF5A3D31),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  
                  _buildLabel('Video Tour URL (Optional)'),
                  TextFormField(
                    controller: _videoUrlController,
                    decoration: InputDecoration(
                      hintText: 'https://youtube.com/...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
      ),
      bottomNavigationBar: Container(
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
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _saveAndContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107), // Yellow theme from the image
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  elevation: 0,
                ),
                child: Text(
                  _isEditing ? 'Update & Manage Images' : 'Save & Continue',
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
