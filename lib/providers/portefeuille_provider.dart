import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exceptions.dart';
import '../models/course.dart';
import '../models/profile.dart';
import '../services/mobile_money_service.dart';
import 'service_providers.dart';

/// État du portefeuille virtuel.
class PortefeuilleState {
  const PortefeuilleState({
    this.profil,
    this.chargement = false,
    this.erreur,
    this.messageSucces,
  });

  final Profile? profil;
  final bool chargement;
  final String? erreur;
  final String? messageSucces;

  double get solde => profil?.soldePortefeuille ?? 0;

  PortefeuilleState copyWith({
    Profile? profil,
    bool? chargement,
    String? erreur,
    String? messageSucces,
    bool clearErreur = false,
    bool clearSucces = false,
  }) {
    return PortefeuilleState(
      profil: profil ?? this.profil,
      chargement: chargement ?? this.chargement,
      erreur: clearErreur ? null : (erreur ?? this.erreur),
      messageSucces: clearSucces ? null : (messageSucces ?? this.messageSucces),
    );
  }
}

class PortefeuilleNotifier extends StateNotifier<PortefeuilleState> {
  PortefeuilleNotifier(this._ref) : super(const PortefeuilleState());

  final Ref _ref;

  /// Charge le solde depuis Supabase.
  Future<void> chargerProfil() async {
    state = state.copyWith(chargement: true, clearErreur: true, clearSucces: true);
    try {
      final profil =
          await _ref.read(portefeuilleServiceProvider).getProfilCourant();
      state = state.copyWith(profil: profil, chargement: false);
    } on AppException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
    } catch (e) {
      state = state.copyWith(chargement: false, erreur: 'Erreur : $e');
    }
  }

  /// Accepte une course si le solde couvre la commission.
  /// Retourne la course mise à jour, ou `null` en cas d'échec.
  Future<Course?> accepterCourse(Course course) async {
    state = state.copyWith(chargement: true, clearErreur: true, clearSucces: true);
    try {
      final miseAJour = await _ref
          .read(portefeuilleServiceProvider)
          .accepterCourseSiSoldeSuffisant(course);
      await chargerProfil();
      state = state.copyWith(
        chargement: false,
        messageSucces: 'Course acceptée avec succès.',
      );
      return miseAJour;
    } on SoldeInsuffisantException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
      rethrow;
    } on AppException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(chargement: false, erreur: 'Erreur : $e');
      return null;
    }
  }

  /// Initie une recharge Mobile Money.
  Future<bool> recharger({
    required double montant,
    required String telephone,
    required OperateurMobileMoney operateur,
  }) async {
    state = state.copyWith(chargement: true, clearErreur: true, clearSucces: true);
    try {
      final resultat = await _ref
          .read(portefeuilleServiceProvider)
          .rechargerPortefeuille(
            montant: montant,
            telephone: telephone,
            operateur: operateur,
          );
      state = state.copyWith(
        chargement: false,
        messageSucces: resultat.message,
      );
      return resultat.succes;
    } on AppException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(chargement: false, erreur: 'Erreur : $e');
      return false;
    }
  }
}

final portefeuilleProvider =
    StateNotifierProvider<PortefeuilleNotifier, PortefeuilleState>((ref) {
  return PortefeuilleNotifier(ref);
});
