import 'dart:math' as math;

/// Villes principales du Burkina Faso — détection par proximité GPS.
class VilleBurkina {
  const VilleBurkina._();

  static const _villes = <({String nom, double lat, double lng})>[
    (nom: 'Ouagadougou', lat: 12.3714, lng: -1.5197),
    (nom: 'Bobo-Dioulasso', lat: 11.1772, lng: -4.2979),
    (nom: 'Koudougou', lat: 12.2526, lng: -2.3627),
    (nom: 'Banfora', lat: 10.6333, lng: -4.7667),
    (nom: 'Ouahigouya', lat: 13.5828, lng: -2.4217),
    (nom: 'Pouytenga', lat: 12.2497, lng: -0.4236),
    (nom: 'Kaya', lat: 13.0917, lng: -1.0844),
    (nom: 'Tenkodogo', lat: 11.7800, lng: -0.3697),
    (nom: 'Fada N\'Gourma', lat: 12.0614, lng: 0.3581),
    (nom: 'Dédougou', lat: 12.4631, lng: -3.4606),
    (nom: 'Houndé', lat: 11.5000, lng: -3.5167),
    (nom: 'Gaoua', lat: 10.2992, lng: -3.2508),
    (nom: 'Dori', lat: 14.0354, lng: -0.0345),
    (nom: 'Manga', lat: 11.6650, lng: -1.0750),
    (nom: 'Ziniaré', lat: 12.5822, lng: -1.2972),
  ];

  /// Rayon max (km) pour rattacher un point à une ville.
  static const rayonMaxKm = 45.0;

  static String depuisCoordonnees(double latitude, double longitude) {
    ({String nom, double lat, double lng})? meilleure;
    var meilleureDistance = double.infinity;

    for (final v in _villes) {
      final d = _distanceKm(latitude, longitude, v.lat, v.lng);
      if (d < meilleureDistance) {
        meilleureDistance = d;
        meilleure = v;
      }
    }

    if (meilleure == null) return 'Burkina Faso';
    if (meilleureDistance <= rayonMaxKm) return meilleure.nom;
    return meilleure.nom; // ville la plus proche même hors rayon
  }

  static double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
