import '../models/profile.dart';

/// Livreur disponible à proximité (résultat de recherche géolocalisée).
class LivreurProche {
  const LivreurProche({
    required this.livreurId,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.distanceKm,
    required this.updatedAt,
    this.ville,
    this.typeVehicule,
    this.noteMoyenne = 5.0,
    this.estVerifie = false,
    this.photoUrl,
    this.localisationActive = true,
  });

  final String livreurId;
  final String nom;
  final String prenom;
  final String telephone;
  final double distanceKm;
  final DateTime updatedAt;
  final String? ville;
  final TypeVehicule? typeVehicule;
  final double noteMoyenne;
  final bool estVerifie;
  final String? photoUrl;
  final bool localisationActive;

  String get nomComplet => '$prenom $nom';
  String get initiales {
    final p = prenom.isNotEmpty ? prenom[0] : '';
    final n = nom.isNotEmpty ? nom[0] : '';
    return ('$p$n').toUpperCase();
  }

  String get distanceFormatee {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  factory LivreurProche.fromJson(Map<String, dynamic> json) {
    return LivreurProche(
      livreurId: json['livreur_id']?.toString() ?? '',
      nom: json['nom']?.toString() ?? '',
      prenom: json['prenom']?.toString() ?? '',
      telephone: json['telephone']?.toString() ?? '',
      distanceKm: _toDouble(json['distance_km']),
      updatedAt: DateTime.tryParse(
            json['updated_at']?.toString() ?? '',
          ) ??
          DateTime.now(),
      ville: json['ville']?.toString(),
      typeVehicule: TypeVehicule.fromString(json['type_vehicule']?.toString()),
      noteMoyenne: _toDouble(json['note_moyenne'], fallback: 5),
      estVerifie: json['est_verifie'] == true,
      photoUrl: json['photo_url']?.toString(),
      localisationActive: json['localisation_active'] != false,
    );
  }

  /// Données d'aperçu UI (sans backend).
  static List<LivreurProche> mockListe() {
    final now = DateTime.now();
    return [
      LivreurProche(
        livreurId: '1',
        nom: 'Ouédraogo',
        prenom: 'Amadou',
        telephone: '+226 70 00 11 22',
        distanceKm: 0.8,
        updatedAt: now,
        ville: 'Ouagadougou',
        typeVehicule: TypeVehicule.moto,
        noteMoyenne: 4.9,
        estVerifie: true,
      ),
      LivreurProche(
        livreurId: '2',
        nom: 'Kaboré',
        prenom: 'Fatim',
        telephone: '+226 76 55 44 33',
        distanceKm: 1.4,
        updatedAt: now.subtract(const Duration(minutes: 1)),
        ville: 'Ouagadougou',
        typeVehicule: TypeVehicule.tricycle,
        noteMoyenne: 4.7,
        estVerifie: true,
      ),
      LivreurProche(
        livreurId: '3',
        nom: 'Sawadogo',
        prenom: 'Ibrahim',
        telephone: '+226 61 22 33 44',
        distanceKm: 2.6,
        updatedAt: now.subtract(const Duration(minutes: 3)),
        ville: 'Ouagadougou',
        typeVehicule: TypeVehicule.moto,
        noteMoyenne: 4.5,
        estVerifie: false,
      ),
    ];
  }

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }
}
