import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../models/course.dart';
import '../models/profile.dart';
import 'mobile_money_service.dart';

/// Gestion du portefeuille virtuel et contrôle financier avant acceptation.
class PortefeuilleService {
  PortefeuilleService({
    SupabaseClient? client,
    MobileMoneyService? mobileMoneyService,
  })  : _supabase = client ?? Supabase.instance.client,
        _mobileMoney = mobileMoneyService ?? MobileMoneyService();

  final SupabaseClient _supabase;
  final MobileMoneyService _mobileMoney;

  /// Récupère le profil (et donc le solde) de l'utilisateur connecté.
  Future<Profile> getProfilCourant() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw AppException('Utilisateur non authentifié.');
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return Profile.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Impossible de charger le profil : ${e.message}');
    } catch (e) {
      throw AppException('Erreur inattendue : $e');
    }
  }

  /// Vérifie si le solde couvre la commission de [course].
  ///
  /// Retourne `true` si OK, sinon lève [SoldeInsuffisantException].
  Future<bool> verifierSoldePourCourse(Course course) async {
    final profil = await getProfilCourant();

    if (profil.soldePortefeuille < course.commission) {
      throw SoldeInsuffisantException(
        solde: profil.soldePortefeuille,
        commission: course.commission,
      );
    }
    return true;
  }

  /// Tente d'accepter une course après contrôle du solde.
  ///
  /// La validation définitive du solde est aussi faite côté SQL
  /// (`accepter_course`) pour éviter les race conditions.
  Future<Course> accepterCourseSiSoldeSuffisant(Course course) async {
    try {
      await verifierSoldePourCourse(course);

      final raw = await _supabase.rpc(
        'accepter_course',
        params: {'p_course_id': course.id},
      );

      // rpc peut renvoyer un Map ou une List selon la config PostgREST
      final Map<String, dynamic> json;
      if (raw is List && raw.isNotEmpty) {
        json = Map<String, dynamic>.from(raw.first as Map);
      } else if (raw is Map) {
        json = Map<String, dynamic>.from(raw);
      } else {
        throw AppException('Réponse inattendue du serveur.');
      }

      return Course.fromJson(json);
    } on SoldeInsuffisantException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.message.contains('SOLDE_INSUFFISANT')) {
        final profil = await getProfilCourant();
        throw SoldeInsuffisantException(
          solde: profil.soldePortefeuille,
          commission: course.commission,
        );
      }
      throw AppException('Acceptation refusée : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Erreur lors de l\'acceptation : $e');
    }
  }

  /// Lance une recharge Mobile Money (simulation agrégateur).
  Future<ResultatPaiementMobileMoney> rechargerPortefeuille({
    required double montant,
    required String telephone,
    required OperateurMobileMoney operateur,
  }) {
    return _mobileMoney.initierRecharge(
      montant: montant,
      telephone: telephone,
      operateur: operateur,
    );
  }
}
