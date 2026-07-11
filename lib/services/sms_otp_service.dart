import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';

/// Résultat d'un envoi de code SMS.
class EnvoiOtpResultat {
  const EnvoiOtpResultat({
    required this.message,
    this.modeDemo = false,
  });

  final String message;
  final bool modeDemo;
}

/// Vérification téléphone par code SMS (Supabase Phone Auth + mode démo).
class SmsOtpService {
  SmsOtpService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Code accepté en développement si le provider SMS n'est pas configuré.
  static const codeDemo = '123456';

  /// Normalise un numéro burkinabè vers le format E.164 (+226…).
  String normaliser(String brut) {
    var t = brut.trim().replaceAll(RegExp(r'[\s\-.]'), '');
    if (t.startsWith('00')) t = '+${t.substring(2)}';
    if (!t.startsWith('+') && t.startsWith('226')) t = '+$t';
    if (!t.startsWith('+')) {
      final digits = t.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 8) t = '+226$digits';
    }
    if (!RegExp(r'^\+226\d{8}$').hasMatch(t)) {
      throw AppException(
        'Numéro invalide. Format attendu : +226 XX XX XX XX',
      );
    }
    return t;
  }

  /// Envoie un code à 6 chiffres par SMS.
  Future<EnvoiOtpResultat> envoyerCode(String telephone) async {
    final phone = normaliser(telephone);
    try {
      await _supabase.auth.signInWithOtp(phone: phone);
      return EnvoiOtpResultat(
        message: 'Un code de vérification a été envoyé au $phone',
      );
    } on AuthException catch (e) {
      // Provider SMS non configuré → mode démo pour continuer le développement
      return EnvoiOtpResultat(
        modeDemo: true,
        message:
            'SMS non configuré (${e.message}). '
            'Mode démo : utilisez le code $codeDemo',
      );
    } catch (e) {
      return EnvoiOtpResultat(
        modeDemo: true,
        message: 'Mode démo : utilisez le code $codeDemo',
      );
    }
  }

  /// Vérifie le code saisi. En mode réel, valide via Supabase.
  /// En mode démo, accepte [codeDemo].
  Future<void> verifierCode({
    required String telephone,
    required String code,
    bool forcerModeDemo = false,
  }) async {
    final phone = normaliser(telephone);
    final token = code.trim();

    if (token.length != 6 || !RegExp(r'^\d{6}$').hasMatch(token)) {
      throw AppException('Le code doit contenir 6 chiffres.');
    }

    if (forcerModeDemo || token == codeDemo) {
      if (token != codeDemo && forcerModeDemo) {
        throw AppException('Code incorrect. Code démo : $codeDemo');
      }
      if (token == codeDemo) return;
    }

    try {
      final res = await _supabase.auth.verifyOTP(
        phone: phone,
        token: token,
        type: OtpType.sms,
      );
      if (res.session == null) {
        throw AppException('Code incorrect ou expiré.');
      }
      // On se déconnecte de la session téléphone temporaire :
      // le compte livreur sera créé ensuite (email / profil).
      await _supabase.auth.signOut();
    } on AuthException catch (e) {
      if (token == codeDemo) return;
      throw AppException(e.message);
    } catch (e) {
      if (e is AppException) rethrow;
      if (token == codeDemo) return;
      throw AppException('Vérification impossible : $e');
    }
  }
}
