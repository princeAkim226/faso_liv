/// Conversation (course avec messagerie active).
class ConversationCourse {
  const ConversationCourse({
    required this.courseId,
    required this.statut,
    required this.livreurId,
    required this.demandeurId,
    required this.interlocuteurNom,
    required this.interlocuteurPrenom,
    required this.interlocuteurTelephone,
    this.dernierMessage,
    this.dernierAt,
    required this.createdAt,
  });

  final String courseId;
  final String statut;
  final String livreurId;
  final String demandeurId;
  final String interlocuteurNom;
  final String interlocuteurPrenom;
  final String interlocuteurTelephone;
  final String? dernierMessage;
  final DateTime? dernierAt;
  final DateTime createdAt;

  String get titre {
    final p = interlocuteurPrenom.trim();
    final n = interlocuteurNom.trim();
    if (p.isEmpty && n.isEmpty) return 'Conversation';
    if (p.isEmpty) return n;
    if (n.isEmpty) return p;
    return '$p $n';
  }

  factory ConversationCourse.fromJson(Map<String, dynamic> json) {
    return ConversationCourse(
      courseId: json['course_id']?.toString() ?? '',
      statut: json['statut']?.toString() ?? '',
      livreurId: json['livreur_id']?.toString() ?? '',
      demandeurId: json['demandeur_id']?.toString() ?? '',
      interlocuteurNom: json['interlocuteur_nom']?.toString() ?? '',
      interlocuteurPrenom: json['interlocuteur_prenom']?.toString() ?? '',
      interlocuteurTelephone:
          json['interlocuteur_telephone']?.toString() ?? '',
      dernierMessage: json['dernier_message']?.toString(),
      dernierAt: json['dernier_at'] != null
          ? DateTime.tryParse(json['dernier_at'].toString())
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
