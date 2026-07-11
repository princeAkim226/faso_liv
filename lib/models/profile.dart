/// Types d'utilisateur FasoLiv.
enum TypeUtilisateur {
  demandeur,
  livreur;

  static TypeUtilisateur fromString(String value) {
    return TypeUtilisateur.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TypeUtilisateur.demandeur,
    );
  }

  String get label => this == TypeUtilisateur.livreur ? 'Livreur' : 'Client';
}

enum TypeVehicule {
  moto,
  tricycle,
  voiture,
  velo;

  static TypeVehicule? fromString(String? value) {
    if (value == null) return null;
    for (final v in TypeVehicule.values) {
      if (v.name == value) return v;
    }
    return null;
  }

  String get label {
    switch (this) {
      case TypeVehicule.moto:
        return 'Moto';
      case TypeVehicule.tricycle:
        return 'Tricycle';
      case TypeVehicule.voiture:
        return 'Voiture';
      case TypeVehicule.velo:
        return 'Vélo';
    }
  }
}

/// Profil utilisateur enrichi (CNIB, véhicule, géoloc…).
class Profile {
  const Profile({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.typeUtilisateur,
    this.soldePortefeuille = 0,
    this.cnib,
    this.photoUrl,
    this.ville = 'Ouagadougou',
    this.typeVehicule,
    this.numeroPlaque,
    this.noteMoyenne = 5.0,
    this.estVerifie = false,
    this.localisationActive = false,
    this.cnibRectoUrl,
    this.cnibVersoUrl,
    this.telephoneVerifie = false,
    this.abonnementExpireAt,
  });

  final String id;
  final String nom;
  final String prenom;
  final String telephone;
  final TypeUtilisateur typeUtilisateur;
  final double soldePortefeuille;
  final String? cnib;
  final String? photoUrl;
  final String ville;
  final TypeVehicule? typeVehicule;
  final String? numeroPlaque;
  final double noteMoyenne;
  final bool estVerifie;
  final bool localisationActive;
  final String? cnibRectoUrl;
  final String? cnibVersoUrl;
  final bool telephoneVerifie;
  final DateTime? abonnementExpireAt;

  String get nomComplet => '$prenom $nom';
  String get initiales {
    final p = prenom.isNotEmpty ? prenom[0] : '';
    final n = nom.isNotEmpty ? nom[0] : '';
    return ('$p$n').toUpperCase();
  }

  bool get estLivreur => typeUtilisateur == TypeUtilisateur.livreur;
  bool get cnibComplete =>
      cnibRectoUrl != null &&
      cnibRectoUrl!.isNotEmpty &&
      cnibVersoUrl != null &&
      cnibVersoUrl!.isNotEmpty;

  /// Compte livreur utilisable (En ligne) si abonnement encore valide.
  bool get abonnementActif =>
      abonnementExpireAt != null &&
      abonnementExpireAt!.isAfter(DateTime.now());

  factory Profile.fromJson(Map<String, dynamic> json) {
    DateTime? abo;
    final rawAbo = json['abonnement_expire_at'];
    if (rawAbo != null) {
      abo = DateTime.tryParse(rawAbo.toString());
    }

    return Profile(
      id: json['id'] as String,
      nom: json['nom'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      telephone: json['telephone'] as String? ?? '',
      typeUtilisateur: TypeUtilisateur.fromString(
        json['type_utilisateur'] as String? ?? 'demandeur',
      ),
      soldePortefeuille: _toDouble(json['solde_portefeuille']),
      cnib: json['cnib'] as String?,
      photoUrl: json['photo_url'] as String?,
      ville: json['ville'] as String? ?? 'Ouagadougou',
      typeVehicule: TypeVehicule.fromString(json['type_vehicule'] as String?),
      numeroPlaque: json['numero_plaque'] as String?,
      noteMoyenne: _toDouble(json['note_moyenne'], fallback: 5),
      estVerifie: json['est_verifie'] as bool? ?? false,
      localisationActive: json['localisation_active'] as bool? ?? false,
      cnibRectoUrl: json['cnib_recto_url'] as String?,
      cnibVersoUrl: json['cnib_verso_url'] as String?,
      telephoneVerifie: json['telephone_verifie'] as bool? ?? false,
      abonnementExpireAt: abo,
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'nom': nom,
        'prenom': prenom,
        'telephone': telephone,
        'type_utilisateur': typeUtilisateur.name,
        if (cnib != null) 'cnib': cnib,
        if (ville.isNotEmpty) 'ville': ville,
        if (typeVehicule != null) 'type_vehicule': typeVehicule!.name,
        if (numeroPlaque != null) 'numero_plaque': numeroPlaque,
      };

  Profile copyWith({
    double? soldePortefeuille,
    bool? localisationActive,
    bool? estVerifie,
    String? ville,
    String? cnibRectoUrl,
    String? cnibVersoUrl,
    DateTime? abonnementExpireAt,
  }) {
    return Profile(
      id: id,
      nom: nom,
      prenom: prenom,
      telephone: telephone,
      typeUtilisateur: typeUtilisateur,
      soldePortefeuille: soldePortefeuille ?? this.soldePortefeuille,
      cnib: cnib,
      photoUrl: photoUrl,
      ville: ville ?? this.ville,
      typeVehicule: typeVehicule,
      numeroPlaque: numeroPlaque,
      noteMoyenne: noteMoyenne,
      estVerifie: estVerifie ?? this.estVerifie,
      localisationActive: localisationActive ?? this.localisationActive,
      cnibRectoUrl: cnibRectoUrl ?? this.cnibRectoUrl,
      cnibVersoUrl: cnibVersoUrl ?? this.cnibVersoUrl,
      telephoneVerifie: telephoneVerifie,
      abonnementExpireAt: abonnementExpireAt ?? this.abonnementExpireAt,
    );
  }

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }
}
