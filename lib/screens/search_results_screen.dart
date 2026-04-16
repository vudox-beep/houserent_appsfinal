import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import 'home_screen.dart'; // for PropertyCard

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
        if (cat['type'] == initType && cat['label'] != 'All' && cat['label'] != 'For Rent' && cat['label'] != 'For Sale' && cat['label'] != 'Land for Sale') {
          _selectedCategory = cat['label'];
          break;
        }
      }
    }
    
    _fetchResults();
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
      final cat = _categories.firstWhere((c) => c['label'] == _selectedCategory);
      if (cat['type'] != '') cleanParams['type'] = cat['type'];
      else if (_selectedCategory != 'All') cleanParams.remove('type');
      
      if (cat['purpose'] != '') cleanParams['purpose'] = cat['purpose'];
      else if (_selectedCategory != 'All') cleanParams.remove('purpose');
        
      // Fetch ALL properties and apply completely robust client-side filtering 
      // because the backend SQL queries often fail on case mapping or string structure
      final results = await ApiService.fetchProperties({});
      
      List<dynamic> filteredResults = results;
      
      if (cleanParams.containsKey('type')) {
        final type = cleanParams['type']!.toLowerCase().trim();
        filteredResults = filteredResults.where((p) {
          final pType = (p['property_type']?.toString() ?? p['type']?.toString() ?? '').toLowerCase().trim();
          
          if (type == 'boarding_house' && pType.contains('boarding')) return true;
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
          final pPurpose = (p['purpose']?.toString() ?? p['listing_purpose']?.toString() ?? '').toLowerCase();
          return pPurpose.contains(purpose);
        }).toList();
      }
      
      if (cleanParams.containsKey('featured') || cleanParams.containsKey('is_featured')) {
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
          final joinedCityCountry = [pCity, pCountry].where((e) => e.isNotEmpty).join(', ');
          final joinedCountryCity = [pCountry, pCity].where((e) => e.isNotEmpty).join(', ');
          final searchable = [pLocation, pAddress, pTitle, pCity, pCountry, joinedCityCountry, joinedCountryCity].join(' | ');
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
          if (beds == '5' && int.tryParse(pBeds) != null && int.parse(pBeds) >= 5) return true;
          return pBeds == beds;
        }).toList();
      }

      if (cleanParams.containsKey('minPrice')) {
        final minP = double.tryParse(cleanParams['minPrice']!) ?? 0;
        filteredResults = filteredResults.where((p) {
          final price = double.tryParse(p['price']?.toString().replaceAll(',', '') ?? '0') ?? 0;
          return price >= minP;
        }).toList();
      }

      if (cleanParams.containsKey('maxPrice')) {
        final maxP = double.tryParse(cleanParams['maxPrice']!) ?? double.infinity;
        filteredResults = filteredResults.where((p) {
          final price = double.tryParse(p['price']?.toString().replaceAll(',', '') ?? '0') ?? 0;
          return price <= maxP;
        }).toList();
      }
      
      if (mounted) {
        setState(() {
          _properties = filteredResults;
          _isLoading = false;
        });
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => context.go('/home'),
          child: Row(
            children: [
              const Icon(Icons.real_estate_agent, color: Colors.white, size: 28),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'HouseRent Africa', 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -0.5, fontSize: 20),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (MediaQuery.of(context).size.width > 350) ...[
                const SizedBox(width: 8),
                const Text('| Search Results', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ],
            ],
          ),
        ),
        backgroundColor: const Color(0xFFFFC107),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            context.go('/home'); // Always go directly home to prevent stack loops
          },
        ),
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.white,
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
                      color: isSelected ? Colors.black87 : Colors.black54,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: Colors.grey.shade100,
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
                ? const Center(child: Text('No properties found matching your criteria', style: TextStyle(fontSize: 18)))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.of(context).size.width > 800 ? 4 : (MediaQuery.of(context).size.width > 500 ? 3 : 2),
                        childAspectRatio: MediaQuery.of(context).size.width < 400 ? 0.52 : 0.60,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _properties.length,
                      itemBuilder: (context, index) {
                        return PropertyCard(
                          property: _properties[index],
                          isFeatured: _properties[index]['is_featured']?.toString() == '1',
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
