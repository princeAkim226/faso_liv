import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../models/profile.dart';
import 'mobile_money_service.dart';

/// Abonnement mensuel livreur — 2 000 FCFA / mois.
class AbonnementService {
  AbonnementService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const double prixMensuelFcfa = 2000;

  /// Paiement Mobile Money (simulé) puis activation d'1 mois.
  Future<Profile> souscrire({
    required String telephone,
    required OperateurMobileMoney operateur,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw AppException('Connectez-vous pour souscrire.');
    }

    final digits = telephone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      throw MobileMoneyException('Numéro Mobile Money invalide.');
    }

    // Simulation agrégateur (prod : Edge Function + webhook)
    await Future<void>.delayed(const Duration(seconds: 2));

    final reference =
        'ABO-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

    try {
      final raw = await _supabase.rpc(
        'activer_abonnement_mensuel',
        params: {'p_reference': '$reference-${operateur.codeApi}'},
      );

      final Map<String, dynamic> json;
      if (raw is Map) {
        json = Map<String, dynamic>.from(raw);
      } else if (raw is List && raw.isNotEmpty) {
        json = Map<String, dynamic>.from(raw.first as Map);
      } else {
        throw AppException('Activation abonnement : réponse inattendue');
      }
      return Profile.fromJson(json);
    } on PostgrestException catch (e) {
      throw AppException('Abonnement : ${e.message}');
    }
  }
}
