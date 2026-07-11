import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../core/utils/phone_auth_id.dart';
import '../core/utils/session_prefs.dart';
import '../models/profile.dart';
import 'cnib_storage_service.dart';

/// Authentification — les comptes sont surtout pour les livreurs.
/// Les clients peuvent utiliser l'app en invité (sans compte).
class AuthService {
  AuthService({
    SupabaseClient? client,
    CnibStorageService? cnibStorage,
  })  : _supabase = client ?? Supabase.instance.client,
        _cnib = cnibStorage ?? CnibStorageService();

  final SupabaseClient _supabase;
  final CnibStorageService _cnib;

  User? get currentUser => _supabase.auth.currentUser;
  Session? get currentSession => _supabase.auth.currentSession;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Rafraîchit la session locale si elle existe (persistance SharedPreferences).
  Future<Session?> recupererSession() async {
    final locale = _supabase.auth.currentSession;
    if (locale == null) return null;
    try {
      final res = await _supabase.auth.refreshSession();
      return res.session ?? locale;
    } catch (_) {
      // Token encore valide localement
      return locale;
    }
  }

  Future<Profile?> getProfilCourant() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data == null) return null;
      return Profile.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Profil introuvable : ${e.message}');
    }
  }

  /// Connexion classique : numéro de téléphone + mot de passe.
  Future<AuthResponse> connexion({
    required String telephone,
    required String password,
  }) async {
    try {
      final email = PhoneAuthId.emailTechnique(telephone);
      return await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      throw AppException(e.message);
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Connexion impossible : $e');
    }
  }

  /// Inscription livreur (identifiant = téléphone).
  Future<AuthResponse> inscriptionLivreur({
    required String password,
    required String nom,
    required String prenom,
    required String telephone,
    required TypeVehicule typeVehicule,
    required XFile cnibRecto,
    required XFile cnibVerso,
    String? numeroPlaque,
    String? ville,
    bool telephoneVerifie = false,
  }) async {
    try {
      final phone = PhoneAuthId.normaliser(telephone);
      final email = PhoneAuthId.emailTechnique(phone);

      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'nom': nom.trim(),
          'prenom': prenom.trim(),
          'telephone': phone,
          'type_utilisateur': TypeUtilisateur.livreur.name,
          'type_vehicule': typeVehicule.name,
          if (numeroPlaque != null) 'numero_plaque': numeroPlaque.trim(),
          if (ville != null) 'ville': ville,
          'telephone_verifie': telephoneVerifie,
        },
      );

      final userId = response.user?.id;
      if (userId == null) {
        throw AppException(
          'Compte créé — reconnectez-vous avec votre numéro.',
        );
      }

      // Session parfois absente si "Confirm email" est ON
      if (_supabase.auth.currentSession == null) {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      final urls = await _cnib.uploaderRectoVerso(
        userId: userId,
        recto: cnibRecto,
        verso: cnibVerso,
      );

      await _enregistrerProfilLivreur(
        userId: userId,
        nom: nom.trim(),
        prenom: prenom.trim(),
        telephone: phone,
        typeVehicule: typeVehicule,
        numeroPlaque: numeroPlaque,
        ville: ville,
        cnibRecto: urls.rectoUrl,
        cnibVerso: urls.versoUrl,
        telephoneVerifie: telephoneVerifie,
      );

      return response;
    } on AuthException catch (e) {
      throw AppException(e.message);
    } on PostgrestException catch (e) {
      throw AppException('Profil : ${e.message}');
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Inscription impossible : $e');
    }
  }

  Future<void> _enregistrerProfilLivreur({
    required String userId,
    required String nom,
    required String prenom,
    required String telephone,
    required TypeVehicule typeVehicule,
    String? numeroPlaque,
    String? ville,
    required String cnibRecto,
    required String cnibVerso,
    required bool telephoneVerifie,
  }) async {
    final payload = <String, dynamic>{
      'id': userId,
      'nom': nom,
      'prenom': prenom,
      'telephone': telephone,
      'type_utilisateur': TypeUtilisateur.livreur.name,
      'type_vehicule': typeVehicule.name,
      if (ville != null && ville.isNotEmpty) 'ville': ville,
      if (numeroPlaque != null && numeroPlaque.trim().isNotEmpty)
        'numero_plaque': numeroPlaque.trim(),
      'cnib_recto_url': cnibRecto,
      'cnib_verso_url': cnibVerso,
      'telephone_verifie': telephoneVerifie,
    };

    await _supabase.from('profiles').upsert(payload);
  }

  /// Re-téléverse ou rattache les photos CNIB au profil connecté.
  Future<Profile> completerCnib({
    required XFile recto,
    required XFile verso,
  }) async {
    final user = currentUser;
    if (user == null) throw AppException('Non authentifié');

    try {
      final urls = await _cnib.uploaderRectoVerso(
        userId: user.id,
        recto: recto,
        verso: verso,
      );
      await _supabase.from('profiles').update({
        'cnib_recto_url': urls.rectoUrl,
        'cnib_verso_url': urls.versoUrl,
      }).eq('id', user.id);

      final profil = await getProfilCourant();
      if (profil == null) throw AppException('Profil introuvable');
      return profil;
    } on PostgrestException catch (e) {
      throw AppException('CNIB : ${e.message}');
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Impossible d\'enregistrer la CNIB : $e');
    }
  }

  /// Relie au profil des fichiers déjà présents dans Storage.
  Future<Profile?> rattacherCnibDepuisStorage() async {
    final user = currentUser;
    if (user == null) return null;

    final profil = await getProfilCourant();
    if (profil == null || profil.cnibComplete) return profil;

    final existants = await _cnib.recupererCheminsExistants(user.id);
    if (existants.recto == null || existants.verso == null) return profil;

    await _supabase.from('profiles').update({
      'cnib_recto_url': existants.recto,
      'cnib_verso_url': existants.verso,
    }).eq('id', user.id);

    return getProfilCourant();
  }

  Future<void> mettreAJourVille(String ville) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await _supabase.from('profiles').update({
        'ville': ville,
      }).eq('id', user.id);
    } catch (_) {}
  }

  /// Compte client léger (prénom seul — pas de numéro demandé).
  Future<Profile> assurerCompteClient({
    required String prenom,
  }) async {
    final existant = await getProfilCourant();
    if (existant != null) {
      if (existant.estLivreur) {
        throw AppException(
          'Déconnectez le compte livreur pour commander en tant que client.',
        );
      }
      // Met à jour le prénom si besoin
      final p = prenom.trim();
      if (p.isNotEmpty && existant.prenom != p) {
        await _supabase.from('profiles').update({'prenom': p}).eq('id', existant.id);
        final maj = await getProfilCourant();
        if (maj != null) return maj;
      }
      return existant;
    }

    final deviceId = await SessionPrefs.assurerIdClientLocal();
    final phone = PhoneAuthId.telephoneTechniqueClient(deviceId);
    final email = PhoneAuthId.emailTechnique(phone);
    final password = _motDePasseClient(phone);

    try {
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'prenom': prenom.trim(),
          'nom': '',
          'telephone': phone,
          'type_utilisateur': TypeUtilisateur.demandeur.name,
        },
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('registered') ||
          msg.contains('already') ||
          msg.contains('exists')) {
        try {
          await _supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
        } on AuthException catch (e2) {
          throw AppException(
            'Impossible de reprendre la discussion. '
            'Réessayez. (${e2.message})',
          );
        }
      } else {
        throw AppException(e.message);
      }
    }

    if (_supabase.auth.currentSession == null) {
      await _supabase.auth.signInWithPassword(email: email, password: password);
    }

    final userId = currentUser?.id;
    if (userId == null) {
      throw AppException('Compte client non créé.');
    }

    await _supabase.from('profiles').upsert({
      'id': userId,
      'prenom': prenom.trim(),
      'nom': '',
      'telephone': phone,
      'type_utilisateur': TypeUtilisateur.demandeur.name,
    });

    final profil = await getProfilCourant();
    if (profil == null) throw AppException('Profil client introuvable.');
    return profil;
  }

  static String _motDePasseClient(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return 'Client-$digits-Fasoliv!';
  }

  Future<void> deconnexion() => _supabase.auth.signOut();
}
