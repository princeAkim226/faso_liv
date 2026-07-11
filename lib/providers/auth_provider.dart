import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../core/utils/session_prefs.dart';
import '../core/utils/ville_burkina.dart';
import '../models/inscription_livreur_draft.dart';
import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/messaging_service.dart';
import '../services/sms_otp_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final locationServiceProvider =
    Provider<LocationService>((ref) => LocationService());

final messagingServiceProvider =
    Provider<MessagingService>((ref) => MessagingService());

final smsOtpServiceProvider = Provider<SmsOtpService>((ref) => SmsOtpService());

/// Mode client sans compte (invité).
final modeInviteProvider = StateProvider<bool>((ref) => false);

/// Brouillon d'inscription en attente de validation SMS.
final inscriptionDraftProvider =
    StateProvider<InscriptionLivreurDraft?>((ref) => null);

/// Session auth + profil chargé.
class AuthStateApp {
  const AuthStateApp({
    this.user,
    this.profil,
    this.chargement = true,
    this.erreur,
  });

  final User? user;
  final Profile? profil;
  final bool chargement;
  final String? erreur;

  bool get estConnecte => user != null && profil != null;
  bool get estLivreur => profil?.estLivreur ?? false;

  AuthStateApp copyWith({
    User? user,
    Profile? profil,
    bool? chargement,
    String? erreur,
    bool clearUser = false,
    bool clearProfil = false,
    bool clearErreur = false,
  }) {
    return AuthStateApp(
      user: clearUser ? null : (user ?? this.user),
      profil: clearUser || clearProfil ? null : (profil ?? this.profil),
      chargement: chargement ?? this.chargement,
      erreur: clearErreur ? null : (erreur ?? this.erreur),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthStateApp> {
  AuthNotifier(this._ref) : super(const AuthStateApp()) {
    _init();
  }

  final Ref _ref;
  bool _initFait = false;

  Future<void> _init() async {
    final auth = _ref.read(authServiceProvider);

    // Écoute continue des changements de session (refresh token, login, logout)
    // Toujours silencieux : ne jamais remonter le splash AppGate en plein parcours.
    auth.authStateChanges.listen((event) async {
      final session = event.session;
      if (session == null) {
        // Ne pas écraser un chargement initial encore en cours
        if (_initFait) {
          state = const AuthStateApp(chargement: false);
        }
        return;
      }
      await rafraichirProfil(silencieux: true);
    });

    // Restaure la session persistée (SharedPreferences via supabase_flutter)
    try {
      final rester = await SessionPrefs.resterConnecte();
      var session = auth.currentSession;

      if (!rester) {
        if (session != null) {
          await auth.deconnexion();
        }
        _initFait = true;
        state = const AuthStateApp(chargement: false);
        return;
      }

      if (session != null) {
        session = await auth.recupererSession() ?? session;
        state = state.copyWith(user: session.user, chargement: true);
        await rafraichirProfil();
      } else {
        state = const AuthStateApp(chargement: false);
      }
    } catch (_) {
      state = const AuthStateApp(chargement: false);
    } finally {
      _initFait = true;
    }
  }

  Future<void> rafraichirProfil({bool silencieux = false}) async {
    final dejaAffiche = state.profil != null || state.user != null;
    if (!silencieux && !dejaAffiche) {
      state = state.copyWith(chargement: true, clearErreur: true);
    }

    final auth = _ref.read(authServiceProvider);
    final user = auth.currentUser;

    if (user == null) {
      state = const AuthStateApp(chargement: false);
      return;
    }

    try {
      await auth.rattacherCnibDepuisStorage();
      final profil = await auth.getProfilCourant();
      state = AuthStateApp(
        user: user,
        profil: profil,
        chargement: false,
      );
    } on AppException catch (e) {
      // Garder la session même si le profil échoue temporairement
      state = AuthStateApp(
        user: user,
        profil: state.profil,
        chargement: false,
        erreur: e.message,
      );
    } catch (e) {
      state = AuthStateApp(
        user: user,
        profil: state.profil,
        chargement: false,
        erreur: '$e',
      );
    }
  }

  Future<bool> completerCnib({
    required XFile recto,
    required XFile verso,
  }) async {
    try {
      final profil = await _ref.read(authServiceProvider).completerCnib(
            recto: recto,
            verso: verso,
          );
      state = state.copyWith(profil: profil, clearErreur: true);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(erreur: e.message);
      return false;
    }
  }

  Future<void> synchroniserVilleDepuisGps({
    required double latitude,
    required double longitude,
  }) async {
    final ville = VilleBurkina.depuisCoordonnees(latitude, longitude);
    await _ref.read(authServiceProvider).mettreAJourVille(ville);
    final profil = state.profil;
    if (profil != null) {
      state = state.copyWith(profil: profil.copyWith(ville: ville));
    }
  }

  void appliquerProfil(Profile profil) {
    state = state.copyWith(
      profil: profil,
      user: state.user ?? _ref.read(authServiceProvider).currentUser,
      chargement: false,
      clearErreur: true,
    );
  }

  Future<Profile?> assurerCompteClient({
    required String prenom,
  }) async {
    try {
      final profil = await _ref.read(authServiceProvider).assurerCompteClient(
            prenom: prenom,
          );
      await SessionPrefs.setResterConnecte(true);
      _ref.read(modeInviteProvider.notifier).state = false;
      state = AuthStateApp(
        user: _ref.read(authServiceProvider).currentUser,
        profil: profil,
        chargement: false,
      );
      return profil;
    } on AppException catch (e) {
      state = state.copyWith(erreur: e.message);
      return null;
    }
  }

  Future<bool> connexion({
    required String telephone,
    required String password,
  }) async {
    state = state.copyWith(chargement: true, clearErreur: true);
    try {
      await _ref.read(authServiceProvider).connexion(
            telephone: telephone,
            password: password,
          );
      await SessionPrefs.setResterConnecte(true);
      await SessionPrefs.sauverTelephone(telephone);
      _ref.read(modeInviteProvider.notifier).state = false;
      await rafraichirProfil();
      return state.estConnecte;
    } on AppException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
      return false;
    }
  }

  Future<bool> inscriptionLivreur({
    required String password,
    required String nom,
    required String prenom,
    required String telephone,
    required TypeVehicule typeVehicule,
    required XFile cnibRecto,
    required XFile cnibVerso,
    String? numeroPlaque,
  }) async {
    _ref.read(inscriptionDraftProvider.notifier).state = InscriptionLivreurDraft(
      password: password,
      nom: nom,
      prenom: prenom,
      telephone: telephone,
      typeVehicule: typeVehicule,
      cnibRecto: cnibRecto,
      cnibVerso: cnibVerso,
      numeroPlaque: numeroPlaque,
    );
    return true;
  }

  Future<bool> finaliserInscriptionApresOtp() async {
    final draft = _ref.read(inscriptionDraftProvider);
    if (draft == null) {
      state = state.copyWith(
        chargement: false,
        erreur: 'Aucune inscription en cours. Recommencez.',
      );
      return false;
    }

    state = state.copyWith(chargement: true, clearErreur: true);
    try {
      await _ref.read(authServiceProvider).inscriptionLivreur(
            password: draft.password,
            nom: draft.nom,
            prenom: draft.prenom,
            telephone: draft.telephone,
            typeVehicule: draft.typeVehicule,
            cnibRecto: draft.cnibRecto,
            cnibVerso: draft.cnibVerso,
            numeroPlaque: draft.numeroPlaque,
            telephoneVerifie: true,
          );
      await SessionPrefs.setResterConnecte(true);
      await SessionPrefs.sauverTelephone(draft.telephone);
      _ref.read(inscriptionDraftProvider.notifier).state = null;
      _ref.read(modeInviteProvider.notifier).state = false;
      await rafraichirProfil();
      return state.estConnecte;
    } on AppException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
      return false;
    }
  }

  /// Mode invité : ne déconnecte JAMAIS un compte existant.
  Future<void> entrerEnInvite() async {
    if (state.estConnecte) {
      // Déjà connecté → écran adapté via AppGate, pas de signOut
      _ref.read(modeInviteProvider.notifier).state = false;
      return;
    }
    _ref.read(modeInviteProvider.notifier).state = true;
    state = const AuthStateApp(chargement: false);
  }

  void quitterInvite() {
    _ref.read(modeInviteProvider.notifier).state = false;
  }

  Future<void> deconnexion() async {
    await _ref.read(locationServiceProvider).arreterSuivi();
    // Déconnexion explicite : la prochaine fois, login requis
    await SessionPrefs.setResterConnecte(false);
    await _ref.read(authServiceProvider).deconnexion();
    _ref.read(modeInviteProvider.notifier).state = false;
    _ref.read(inscriptionDraftProvider.notifier).state = null;
    state = const AuthStateApp(chargement: false);
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthStateApp>((ref) => AuthNotifier(ref));
