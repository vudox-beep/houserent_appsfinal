import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

class PlaceSelection {
  const PlaceSelection({
    required this.address,
    required this.placeId,
    required this.latitude,
    required this.longitude,
  });

  final String address;
  final String placeId;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toApiMap() => {
        'address': address,
        'place_id': placeId,
        'latitude': latitude,
        'longitude': longitude,
      };
}

class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.initialAddress,
    required this.onSelected,
    this.country = 'zm',
    this.biasLat,
    this.biasLng,
  });

  final String label;
  final String hint;
  final IconData icon;
  final String? initialAddress;
  final ValueChanged<PlaceSelection> onSelected;

  /// ISO country filter; use '' for worldwide search.
  final String country;

  /// Optional GPS bias so nearby places rank first.
  final double? biasLat;
  final double? biasLng;

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<Map<String, dynamic>> _predictions = [];
  bool _loading = false;
  bool _suppressNext = false;
  bool _noResults = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_suppressNext) {
      _suppressNext = false;
      return;
    }
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _predictions = [];
        _noResults = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      var results = await ApiService.autocompleteAddress(
        value.trim(),
        country: widget.country,
        biasLat: widget.biasLat,
        biasLng: widget.biasLng,
      );
      // Retry with the opposite scope: a strict country filter falls back to
      // worldwide, and a failed worldwide search falls back to Zambia (also
      // covers servers still running the older maps.php).
      if (results.isEmpty) {
        results = await ApiService.autocompleteAddress(
          value.trim(),
          country: widget.country.isEmpty ? 'zm' : '',
          biasLat: widget.biasLat,
          biasLng: widget.biasLng,
        );
      }
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _noResults = results.isEmpty;
        _loading = false;
      });
    });
  }

  Future<void> _pick(Map<String, dynamic> prediction) async {
    final placeId = (prediction['place_id'] ?? '').toString();
    final description = (prediction['description'] ?? '').toString();
    if (placeId.isEmpty) return;

    setState(() {
      _loading = true;
      _predictions = [];
    });

    final details = await ApiService.getPlaceDetails(placeId);
    if (!mounted) return;

    final lat = double.tryParse(
          details?['latitude']?.toString() ??
              details?['lat']?.toString() ??
              details?['location']?['lat']?.toString() ??
              '',
        ) ??
        double.tryParse(details?['geometry']?['location']?['lat']?.toString() ?? '');
    final lng = double.tryParse(
          details?['longitude']?.toString() ??
              details?['lng']?.toString() ??
              details?['location']?['lng']?.toString() ??
              '',
        ) ??
        double.tryParse(details?['geometry']?['location']?['lng']?.toString() ?? '');

    setState(() => _loading = false);

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load that place. Try another.')),
      );
      return;
    }

    final address =
        (details?['formatted_address'] ?? details?['address'] ?? description)
            .toString();
    _suppressNext = true;
    _controller.text = address;
    widget.onSelected(
      PlaceSelection(
        address: address,
        placeId: placeId,
        latitude: lat,
        longitude: lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon, color: const Color(0xFFFFC107)),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFFC107),
                      ),
                    ),
                  )
                : (_controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _predictions = []);
                        },
                      )),
            filled: true,
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFFC107), width: 1.5),
            ),
          ),
        ),
        if (_noResults && !_loading && _controller.text.trim().length >= 3)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'No places found — check the spelling or add the city name.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _predictions.length.clamp(0, 5),
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 20),
                  title: Text(
                    (p['description'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  onTap: () => _pick(p),
                );
              },
            ),
          ),
      ],
    );
  }
}
