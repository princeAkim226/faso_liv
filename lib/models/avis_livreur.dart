/// Avis reçu par un livreur.
class AvisLivreur {
  const AvisLivreur({
    required this.id,
    required this.courseId,
    required this.note,
    required this.luParLivreur,
    required this.createdAt,
    required this.clientPrenom,
    required this.clientNom,
    this.commentaire,
    this.clientTelephone,
  });

  final String id;
  final String courseId;
  final int note;
  final bool luParLivreur;
  final DateTime createdAt;
  final String clientPrenom;
  final String clientNom;
  final String? commentaire;
  final String? clientTelephone;

  String get clientLabel {
    final p = clientPrenom.trim();
    final n = clientNom.trim();
    if (p.isEmpty && n.isEmpty) return 'Client';
    if (n.isEmpty) return p;
    if (p.isEmpty) return n;
    return '$p $n';
  }

  factory AvisLivreur.fromJson(Map<String, dynamic> json) {
    return AvisLivreur(
      id: json['avis_id']?.toString() ?? json['id']?.toString() ?? '',
      courseId: json['course_id']?.toString() ?? '',
      note: (json['note'] is num)
          ? (json['note'] as num).toInt()
          : int.tryParse(json['note']?.toString() ?? '') ?? 0,
      luParLivreur: json['lu_par_livreur'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      clientPrenom: json['client_prenom']?.toString() ?? '',
      clientNom: json['client_nom']?.toString() ?? '',
      commentaire: json['commentaire']?.toString(),
      clientTelephone: json['client_telephone']?.toString(),
    );
  }
}
