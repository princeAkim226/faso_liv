import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../models/transaction_portefeuille.dart';

/// Opérateurs Mobile Money supportés au Burkina Faso.
enum OperateurMobileMoney {
  orangeMoney('Orange Money', 'orange'),
  moovMoney('Moov Money', 'moov'),
  wave('Wave', 'wave');

  const OperateurMobileMoney(this.label, this.codeApi);
  final String label;
  final String codeApi;
}

/// Résultat d'une tentative de paiement Mobile Money.
class ResultatPaiementMobileMoney {
  const ResultatPaiementMobileMoney({
    required this.succes,
    required this.reference,
    required this.message,
  });

  final bool succes;
  final String reference;
  final String message;
}

/// Service simulant un appel vers un agrégateur local
/// (ex. PayDunya, CinetPay, Hub2, ou API Orange/Moov).
///
/// En production :
/// 1. Le client crée une transaction `en_attente` côté Supabase.
/// 2. Cet appel part vers votre Edge Function / backend.
/// 3. Le webhook de l'agrégateur appelle `crediter_portefeuille` (service_role).
class MobileMoneyService {
  MobileMoneyService({
    SupabaseClient? client,
    http.Client? httpClient,
    this.baseUrlAgregeur = 'https://api.exemple-agregateur.bf/v1',
  })  : _supabase = client ?? Supabase.instance.client,
        _http = httpClient ?? http.Client();

  final SupabaseClient _supabase;
  final http.Client _http;
  final String baseUrlAgregeur;

  /// Initie une recharge portefeuille via Mobile Money.
  ///
  /// [montant] en FCFA, [telephone] au format international (+226…).
  Future<ResultatPaiementMobileMoney> initierRecharge({
    required double montant,
    required String telephone,
    required OperateurMobileMoney operateur,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw AppException('Vous devez être connecté pour recharger.');
    }

    if (montant < 100) {
      throw MobileMoneyException('Montant minimum : 100 FCFA.');
    }

    // Référence unique côté app (idempotence côté agrégateur)
    final reference =
        'FL-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

    try {
      // 1. Enregistre la transaction en attente
      await _supabase.from('transactions').insert({
        'user_id': userId,
        'montant': montant,
        'type': TypeTransaction.recharge.name,
        'reference_mobile_money': reference,
        'statut': StatutTransaction.enAttente.valeurDb,
      });

      // 2. Appel simulé vers l'agrégateur
      final resultat = await _appelerAgregeur(
        montant: montant,
        telephone: telephone,
        operateur: operateur,
        reference: reference,
      );

      if (!resultat.succes) {
        await _supabase
            .from('transactions')
            .update({'statut': StatutTransaction.echec.valeurDb})
            .eq('reference_mobile_money', reference);
        throw MobileMoneyException(resultat.message);
      }

      // 3. En prod : le crédit est fait par webhook.
      // Ici on simule le succès immédiat via Edge Function / RPC service.
      // Ne PAS appeler crediter_portefeuille depuis le client en production.
      // Pour la démo locale, on met à jour le statut ; le webhook créditera.
      return resultat;
    } on MobileMoneyException {
      rethrow;
    } on PostgrestException catch (e) {
      throw AppException('Erreur base de données : ${e.message}');
    } catch (e) {
      throw AppException('Échec de la recharge : $e');
    }
  }

  /// Simule (ou appelle réellement) l'API de l'agrégateur.
  ///
  /// Remplacez le corps par un vrai `http.post` vers votre endpoint.
  Future<ResultatPaiementMobileMoney> _appelerAgregeur({
    required double montant,
    required String telephone,
    required OperateurMobileMoney operateur,
    required String reference,
  }) async {
    try {
      // --- Mode simulation (développement) ---
      // En production, décommentez l'appel HTTP réel ci-dessous.
      await Future<void>.delayed(const Duration(seconds: 2));

      // Simule un refus si le numéro est trop court
      if (telephone.replaceAll(RegExp(r'\D'), '').length < 8) {
        return ResultatPaiementMobileMoney(
          succes: false,
          reference: reference,
          message: 'Numéro Mobile Money invalide.',
        );
      }

      return ResultatPaiementMobileMoney(
        succes: true,
        reference: reference,
        message:
            'Paiement ${operateur.label} initié. '
            'Confirmez sur votre téléphone ($telephone) '
            'pour créditer ${montant.toStringAsFixed(0)} FCFA.',
      );

      // --- Mode production (exemple) ---
      // final response = await _http.post(
      //   Uri.parse('$baseUrlAgregeur/payments'),
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'Authorization': 'Bearer VOTRE_CLE_API',
      //   },
      //   body: jsonEncode({
      //     'amount': montant,
      //     'currency': 'XOF',
      //     'phone': telephone,
      //     'operator': operateur.codeApi,
      //     'external_id': reference,
      //     'callback_url': 'https://VOTRE_PROJET.supabase.co/functions/v1/mm-webhook',
      //   }),
      // );
      // if (response.statusCode >= 200 && response.statusCode < 300) {
      //   final body = jsonDecode(response.body) as Map<String, dynamic>;
      //   return ResultatPaiementMobileMoney(
      //     succes: true,
      //     reference: reference,
      //     message: body['message'] as String? ?? 'Paiement initié',
      //   );
      // }
      // return ResultatPaiementMobileMoney(
      //   succes: false,
      //   reference: reference,
      //   message: 'Erreur agrégateur (${response.statusCode})',
      // );
    } catch (e) {
      throw MobileMoneyException('Impossible de joindre l\'agrégateur : $e');
    }
  }

  void dispose() => _http.close();
}
