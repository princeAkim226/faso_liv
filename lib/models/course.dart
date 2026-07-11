enum StatutCourse {
  disponible,
  propose,
  accepte,
  recupere,
  livre,
  annule;

  static StatutCourse fromString(String value) {
    return StatutCourse.values.firstWhere(
      (e) => e.name == value,
      orElse: () => StatutCourse.disponible,
    );
  }

  String get labelFr {
    switch (this) {
      case StatutCourse.disponible:
        return 'Disponible';
      case StatutCourse.propose:
        return 'Proposée';
      case StatutCourse.accepte:
        return 'Acceptée';
      case StatutCourse.recupere:
        return 'Récupérée';
      case StatutCourse.livre:
        return 'Livrée';
      case StatutCourse.annule:
        return 'Annulée';
    }
  }
}

enum StatutPaiement {
  nonPaye('non_paye'),
  enAttente('en_attente'),
  paye('paye'),
  rembourse('rembourse');

  const StatutPaiement(this.valeurDb);
  final String valeurDb;

  static StatutPaiement fromString(String value) {
    return StatutPaiement.values.firstWhere(
      (e) => e.valeurDb == value || e.name == value,
      orElse: () => StatutPaiement.nonPaye,
    );
  }

  bool get estPaye => this == StatutPaiement.paye;
}

class Course {
  const Course({
    required this.id,
    required this.demandeurId,
    this.livreurId,
    required this.statut,
    required this.prixTotal,
    required this.commission,
    required this.adresseRamassageGps,
    required this.adresseLivraisonGps,
    required this.codeOtpValidation,
    required this.createdAt,
    this.statutPaiement = StatutPaiement.nonPaye,
    this.descriptionColis,
    this.payeAt,
  });

  final String id;
  final String demandeurId;
  final String? livreurId;
  final StatutCourse statut;
  final double prixTotal;
  final double commission;
  final String adresseRamassageGps;
  final String adresseLivraisonGps;
  final String codeOtpValidation;
  final DateTime createdAt;
  final StatutPaiement statutPaiement;
  final String? descriptionColis;
  final DateTime? payeAt;

  bool get messagerieDebloquee =>
      livreurId != null && statut != StatutCourse.annule;

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      demandeurId: json['demandeur_id'] as String,
      livreurId: json['livreur_id'] as String?,
      statut: StatutCourse.fromString(json['statut'] as String? ?? 'disponible'),
      prixTotal: _toDouble(json['prix_total']),
      commission: _toDouble(json['commission']),
      adresseRamassageGps: json['adresse_ramassage_gps'] as String? ?? '',
      adresseLivraisonGps: json['adresse_livraison_gps'] as String? ?? '',
      codeOtpValidation: json['code_otp_validation'] as String? ?? '',
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      statutPaiement: StatutPaiement.fromString(
        json['statut_paiement'] as String? ?? 'non_paye',
      ),
      descriptionColis: json['description_colis'] as String?,
      payeAt: json['paye_at'] != null
          ? DateTime.tryParse(json['paye_at'] as String)
          : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
