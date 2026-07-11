import 'package:image_picker/image_picker.dart';

import 'profile.dart';

/// Données d'inscription livreur en attente de validation SMS.
class InscriptionLivreurDraft {
  const InscriptionLivreurDraft({
    required this.password,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.typeVehicule,
    required this.cnibRecto,
    required this.cnibVerso,
    this.numeroPlaque,
  });

  final String password;
  final String nom;
  final String prenom;
  final String telephone;
  final TypeVehicule typeVehicule;
  final XFile cnibRecto;
  final XFile cnibVerso;
  final String? numeroPlaque;
}
