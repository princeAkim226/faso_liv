import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exceptions.dart';
import '../models/livreur_proche.dart';
import 'service_providers.dart';

/// Paramètres de recherche géographique.
class RechercheLivreursParams {
  const RechercheLivreursParams({
    required this.latitude,
    required this.longitude,
    this.rayonKm = 5.0,
    required this.courseId,
  });

  final double latitude;
  final double longitude;
  final double rayonKm;
  final String courseId;
}

/// État de la sélection Peer-to-Peer des livreurs.
class LivreursProchesState {
  const LivreursProchesState({
    this.livreurs = const [],
    this.chargement = false,
    this.selectionEnCours = false,
    this.erreur,
    this.messageSucces,
  });

  final List<LivreurProche> livreurs;
  final bool chargement;
  final bool selectionEnCours;
  final String? erreur;
  final String? messageSucces;

  LivreursProchesState copyWith({
    List<LivreurProche>? livreurs,
    bool? chargement,
    bool? selectionEnCours,
    String? erreur,
    String? messageSucces,
    bool clearErreur = false,
    bool clearSucces = false,
  }) {
    return LivreursProchesState(
      livreurs: livreurs ?? this.livreurs,
      chargement: chargement ?? this.chargement,
      selectionEnCours: selectionEnCours ?? this.selectionEnCours,
      erreur: clearErreur ? null : (erreur ?? this.erreur),
      messageSucces: clearSucces ? null : (messageSucces ?? this.messageSucces),
    );
  }
}

class LivreursProchesNotifier extends StateNotifier<LivreursProchesState> {
  LivreursProchesNotifier(this._ref) : super(const LivreursProchesState());

  final Ref _ref;

  Future<void> charger(RechercheLivreursParams params) async {
    state = state.copyWith(chargement: true, clearErreur: true, clearSucces: true);
    try {
      final liste = await _ref.read(livreurServiceProvider).getLivreursProches(
            latitude: params.latitude,
            longitude: params.longitude,
            rayonKm: params.rayonKm,
          );
      state = state.copyWith(livreurs: liste, chargement: false);
    } on AppException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
    } catch (e) {
      state = state.copyWith(chargement: false, erreur: 'Erreur : $e');
    }
  }

  /// Attribue le livreur à la course (statut → `propose`).
  Future<bool> choisirLivreur({
    required String courseId,
    required LivreurProche livreur,
  }) async {
    state = state.copyWith(
      selectionEnCours: true,
      clearErreur: true,
      clearSucces: true,
    );
    try {
      await _ref.read(courseServiceProvider).proposerLivreur(
            courseId: courseId,
            livreurId: livreur.livreurId,
          );
      state = state.copyWith(
        selectionEnCours: false,
        messageSucces:
            '${livreur.nomComplet} a été notifié. En attente d\'acceptation.',
      );
      return true;
    } on AppException catch (e) {
      state = state.copyWith(selectionEnCours: false, erreur: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(selectionEnCours: false, erreur: 'Erreur : $e');
      return false;
    }
  }
}

final livreursProchesProvider =
    StateNotifierProvider.autoDispose<LivreursProchesNotifier, LivreursProchesState>(
  (ref) => LivreursProchesNotifier(ref),
);
