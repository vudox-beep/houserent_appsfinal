import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  String? _location;
  String? _city;
  String? _country;
  String? _purpose;
  String? _category;
  String? _minPrice;
  String? _maxPrice;
  String? _bedrooms;

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

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 16.0),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black54,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({String? hint, IconData? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: Colors.white,
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
      suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: Colors.black54, size: 20) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Advanced Search',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFFFFC107),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home'); // Fallback to home if no history
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 500), // Adjusted width for better mobile fit
            margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            padding: const EdgeInsets.all(20), // Slightly reduced padding to prevent horizontal squeeze
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.tune, color: Colors.black87),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Filters',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _location = null;
                          _city = null;
                          _country = null;
                          _purpose = null;
                          _category = null;
                          _minPrice = null;
                          _maxPrice = null;
                          _bedrooms = null;
                        });
                      },
                      child: const Text('Clear All', style: TextStyle(color: Colors.blue), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                _buildSectionLabel('Location'),
                TextFormField(
                  initialValue: _location,
                  decoration: InputDecoration(
                    hintText: 'City, Area...',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFFFC107))),
                    prefixIcon: const Icon(Icons.search, color: Colors.black38, size: 20),
                    suffixIcon: Container(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: Colors.grey.shade300)),
                      ),
                      child: const Icon(Icons.location_on_outlined, color: Colors.black54, size: 20),
                    ),
                  ),
                  onChanged: (v) => _location = v,
                ),

                _buildSectionLabel('City'),
                TextFormField(
                  initialValue: _city,
                  decoration: _buildInputDecoration(hint: 'e.g. Lusaka'),
                  onChanged: (v) => _city = v,
                ),

                _buildSectionLabel('Country'),
                DropdownButtonFormField<String>(
                  value: _country,
                  dropdownColor: Colors.white,
                  decoration: _buildInputDecoration(),
                  hint: const Text('All Countries', style: TextStyle(color: Colors.black87, fontSize: 14)),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                  items: _africanCountries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _country = v),
                ),

                _buildSectionLabel('Purpose'),
                DropdownButtonFormField<String>(
                  value: _purpose,
                  dropdownColor: Colors.white,
                  decoration: _buildInputDecoration(),
                  hint: const Text('Any Purpose', style: TextStyle(color: Colors.black87, fontSize: 14)),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                  items: const [
                    DropdownMenuItem(value: 'rent', child: Text('For Rent')),
                    DropdownMenuItem(value: 'sale', child: Text('For Sale')),
                  ],
                  onChanged: (v) => setState(() => _purpose = v),
                ),

                _buildSectionLabel('Category'),
                DropdownButtonFormField<String>(
                  value: _category,
                  dropdownColor: Colors.white,
                  decoration: _buildInputDecoration(),
                  hint: const Text('All Categories', style: TextStyle(color: Colors.black87, fontSize: 14)),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                  items: const [
                    DropdownMenuItem(value: 'house', child: Text('House')),
                    DropdownMenuItem(value: 'apartment', child: Text('Apartment')),
                    DropdownMenuItem(value: 'boarding_house', child: Text('Boarding Houses')),
                    DropdownMenuItem(value: 'wedding_lodge', child: Text('Wedding Lodges')),
                    DropdownMenuItem(value: 'studio', child: Text('Studios')),
                    DropdownMenuItem(value: 'land', child: Text('Land for Sale')),
                    DropdownMenuItem(value: 'shop', child: Text('Shop / Commercial')),
                    DropdownMenuItem(value: 'office', child: Text('Office Space')),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),

                _buildSectionLabel('Min Price'),
                TextFormField(
                  initialValue: _minPrice,
                  decoration: _buildInputDecoration(hint: 'Min'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _minPrice = v,
                ),

                _buildSectionLabel('Max Price'),
                TextFormField(
                  initialValue: _maxPrice,
                  decoration: _buildInputDecoration(hint: 'Max'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _maxPrice = v,
                ),

                _buildSectionLabel('Bedrooms'),
                DropdownButtonFormField<String>(
                  value: _bedrooms,
                  dropdownColor: Colors.white,
                  decoration: _buildInputDecoration(),
                  hint: const Text('Any', style: TextStyle(color: Colors.black87, fontSize: 14)),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('1')),
                    DropdownMenuItem(value: '2', child: Text('2')),
                    DropdownMenuItem(value: '3', child: Text('3')),
                    DropdownMenuItem(value: '4', child: Text('4')),
                    DropdownMenuItem(value: '5', child: Text('5+')),
                  ],
                  onChanged: (v) => setState(() => _bedrooms = v),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final queryParams = <String, String>{};
                      if (_location != null && _location!.isNotEmpty) queryParams['location'] = _location!;
                      if (_city != null && _city!.isNotEmpty) queryParams['city'] = _city!;
                      if (_country != null) queryParams['country'] = _country!;
                      if (_purpose != null) queryParams['purpose'] = _purpose!;
                      if (_category != null) queryParams['type'] = _category!;
                      if (_minPrice != null && _minPrice!.isNotEmpty) queryParams['minPrice'] = _minPrice!;
                      if (_maxPrice != null && _maxPrice!.isNotEmpty) queryParams['maxPrice'] = _maxPrice!;
                      if (_bedrooms != null) queryParams['bedrooms'] = _bedrooms!;

                      context.push('/search-results', extra: queryParams);
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Update Results', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      elevation: 0,
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
}
