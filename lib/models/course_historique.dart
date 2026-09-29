import '../models/course.dart';

/// Ligne d'historique (course passée ou en cours).
class CourseHistorique {
  const CourseHistorique({
    required this.courseId,
    required this.statut,
    required this.livreurId,
    required this.demandeurId,
    required this.interlocuteurNom,
    required this.interlocuteurPrenom,
    required this.interlocuteurTelephone,
    this.adresseRamassageGps,
    required this.createdAt,
    required this.prixTotal,
  });

  final String courseId;
  final StatutCourse statut;
  final String? livreurId;
  final String demandeurId;
  final String interlocuteurNom;
  final String interlocuteurPrenom;
  final String interlocuteurTelephone;
  final String? adresseRamassageGps;
  final DateTime createdAt;
  final double prixTotal;

  String get titre {
    final p = interlocuteurPrenom.trim();
    final n = interlocuteurNom.trim();
    if (p.isEmpty && n.isEmpty) return 'Course';
    if (p.isEmpty) return n;
    if (n.isEmpty) return p;
    return '$p $n';
  }

  factory CourseHistorique.fromJson(Map<String, dynamic> json) {
    return CourseHistorique(
      courseId: json['course_id']?.toString() ?? '',
      statut: StatutCourse.fromString(json['statut']?.toString() ?? 'propose'),
      livreurId: json['livreur_id']?.toString(),
      demandeurId: json['demandeur_id']?.toString() ?? '',
      interlocuteurNom: json['interlocuteur_nom']?.toString() ?? '',
      interlocuteurPrenom: json['interlocuteur_prenom']?.toString() ?? '',
      interlocuteurTelephone:
          json['interlocuteur_telephone']?.toString() ?? '',
      adresseRamassageGps: json['adresse_ramassage_gps']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      prixTotal: _toDouble(json['prix_total']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
