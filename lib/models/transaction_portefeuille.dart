/// Type d'opération portefeuille / Mobile Money.
enum TypeTransaction {
  recharge,
  commission,
  gain;

  static TypeTransaction fromString(String value) {
    return TypeTransaction.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TypeTransaction.recharge,
    );
  }
}

enum StatutTransaction {
  enAttente('en_attente'),
  reussi('reussi'),
  echec('echec'),
  annule('annule');

  const StatutTransaction(this.valeurDb);
  final String valeurDb;

  static StatutTransaction fromString(String value) {
    return StatutTransaction.values.firstWhere(
      (e) => e.valeurDb == value || e.name == value,
      orElse: () => StatutTransaction.enAttente,
    );
  }
}

/// Ligne d'historique financier.
class TransactionPortefeuille {
  const TransactionPortefeuille({
    required this.id,
    required this.userId,
    required this.montant,
    required this.type,
    this.referenceMobileMoney,
    required this.statut,
    this.courseId,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final double montant;
  final TypeTransaction type;
  final String? referenceMobileMoney;
  final StatutTransaction statut;
  final String? courseId;
  final DateTime createdAt;

  factory TransactionPortefeuille.fromJson(Map<String, dynamic> json) {
    return TransactionPortefeuille(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      montant: _toDouble(json['montant']),
      type: TypeTransaction.fromString(json['type'] as String? ?? 'recharge'),
      referenceMobileMoney: json['reference_mobile_money'] as String?,
      statut: StatutTransaction.fromString(
        json['statut'] as String? ?? 'en_attente',
      ),
      courseId: json['course_id'] as String?,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
