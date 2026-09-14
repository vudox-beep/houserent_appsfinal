/// Dark Yango-style Google Map JSON — keeps street names + light POI labels.
const String kYangoMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d1d1d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1d1d1d"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#4a4a4a"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#242424"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"featureType":"poi.business","elementType":"labels.icon","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c2c2c"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212121"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#b0b0b0"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#333333"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3a3a3a"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#cfcfcf"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#9a9a9a"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f2f2f"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1620"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]}
]
''';

/// Navigation style — brighter street names at close zoom.
const String kYangoNavMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#c8c8c8"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1a1a"},{"weight":2}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"simplified"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#9a9a9a"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"simplified"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2e2e2e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1f1f1f"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#f0f0f0"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#111111"},{"weight":3}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#3a3a3a"}]},
  {"featureType":"road.arterial","elementType":"labels.text.fill","stylers":[{"color":"#ffe082"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#444444"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#ffc107"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#eeeeee"}]},
  {"featureType":"road.local","elementType":"labels.text.stroke","stylers":[{"color":"#0d0d0d"},{"weight":3}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1620"}]}
]
''';
