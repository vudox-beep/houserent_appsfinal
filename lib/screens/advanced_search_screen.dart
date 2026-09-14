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
  bool _openInMapView = false;

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

  Widget _buildSectionLabel(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 16.0),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white54 : Colors.black54,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(BuildContext context, {String? hint, IconData? suffixIcon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFFFFC107)),
      ),
      suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: isDark ? Colors.white54 : Colors.black54, size: 20) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          'Advanced Search',
          style: TextStyle(color: isDark ? Colors.white : Colors.white, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFC107),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.white),
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
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.tune, color: isDark ? Colors.white : Colors.black87),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Filters',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
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
                          _openInMapView = false;
                        });
                      },
                      child: const Text('Clear All', style: TextStyle(color: Colors.blue), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                _buildSectionLabel(context, 'Location'),
                TextFormField(
                  initialValue: _location,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'City, Area...',
                    hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFFFC107))),
                    prefixIcon: Icon(Icons.search, color: isDark ? Colors.white38 : Colors.black38, size: 20),
                    suffixIcon: Container(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                      ),
                      child: Icon(Icons.location_on_outlined, color: isDark ? Colors.white54 : Colors.black54, size: 20),
                    ),
                  ),
                  onChanged: (v) => _location = v,
                ),

                _buildSectionLabel(context, 'City'),
                TextFormField(
                  initialValue: _city,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: _buildInputDecoration(context, hint: 'e.g. Lusaka'),
                  onChanged: (v) => _city = v,
                ),

                _buildSectionLabel(context, 'Country'),
                DropdownButtonFormField<String>(
                  value: _country,
                  dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                  decoration: _buildInputDecoration(context),
                  hint: Text('All Countries', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                  icon: Icon(Icons.keyboard_arrow_down, color: isDark ? Colors.white54 : Colors.black54),
                  items: _africanCountries.map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(color: isDark ? Colors.white : Colors.black87)))).toList(),
                  onChanged: (v) => setState(() => _country = v),
                ),

                _buildSectionLabel(context, 'Purpose'),
                DropdownButtonFormField<String>(
                  value: _purpose,
                  dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                  decoration: _buildInputDecoration(context),
                  hint: Text('Any Purpose', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                  icon: Icon(Icons.keyboard_arrow_down, color: isDark ? Colors.white54 : Colors.black54),
                  items: [
                    DropdownMenuItem<String>(value: 'rent', child: Text('For Rent', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'sale', child: Text('For Sale', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                  ],
                  onChanged: (v) => setState(() => _purpose = v),
                ),

                _buildSectionLabel(context, 'Category'),
                DropdownButtonFormField<String>(
                  value: _category,
                  dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                  decoration: _buildInputDecoration(context),
                  hint: Text('All Categories', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                  icon: Icon(Icons.keyboard_arrow_down, color: isDark ? Colors.white54 : Colors.black54),
                  items: [
                    DropdownMenuItem<String>(value: 'house', child: Text('House', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'apartment', child: Text('Apartment', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'boarding_house', child: Text('Boarding Houses', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'wedding_lodge', child: Text('Wedding Lodges', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'studio', child: Text('Studios', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'land', child: Text('Land for Sale', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'shop', child: Text('Shop / Commercial', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: 'office', child: Text('Office Space', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),

                _buildSectionLabel(context, 'Min Price'),
                TextFormField(
                  initialValue: _minPrice,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: _buildInputDecoration(context, hint: 'Min'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _minPrice = v,
                ),

                _buildSectionLabel(context, 'Max Price'),
                TextFormField(
                  initialValue: _maxPrice,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: _buildInputDecoration(context, hint: 'Max'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _maxPrice = v,
                ),

                _buildSectionLabel(context, 'Bedrooms'),
                DropdownButtonFormField<String>(
                  value: _bedrooms,
                  dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                  decoration: _buildInputDecoration(context),
                  hint: Text('Any', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                  icon: Icon(Icons.keyboard_arrow_down, color: isDark ? Colors.white54 : Colors.black54),
                  items: [
                    DropdownMenuItem<String>(value: '1', child: Text('1', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: '2', child: Text('2', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: '3', child: Text('3', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: '4', child: Text('4', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                    DropdownMenuItem<String>(value: '5', child: Text('5+', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                  ],
                  onChanged: (v) => setState(() => _bedrooms = v),
                ),

                _buildSectionLabel(context, 'View'),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                  child: SwitchListTile(
                    value: _openInMapView,
                    onChanged: (v) => setState(() => _openInMapView = v),
                    activeColor: const Color(0xFFFFC107),
                    title: Text(
                      'Open results in Map View',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'See available homes pinned on the map',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
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
                      if (_openInMapView) queryParams['view'] = 'map';

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
