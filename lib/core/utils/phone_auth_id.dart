import 'app_exceptions.dart';

/// Identifiant technique Supabase dérivé du numéro (login téléphone + mot de passe).
class PhoneAuthId {
  PhoneAuthId._();

  /// Normalise vers +226XXXXXXXX
  static String normaliser(String brut) {
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

  /// Email technique interne — jamais affiché à l'utilisateur.
  static String emailTechnique(String telephone) {
    final phone = normaliser(telephone);
    final digits = phone.replaceAll(RegExp(r'\D'), ''); // 226XXXXXXXX
    return '$digits@users.fasoliv.bf';
  }

  /// Numéro technique unique pour un client sans téléphone saisi.
  /// Format valide +226… (jamais affiché comme vrai contact).
  static String telephoneTechniqueClient(String deviceId) {
    var acc = 0;
    for (final u in deviceId.codeUnits) {
      acc = (acc * 31 + u) & 0x7fffffff;
    }
    final eight = (10000000 + (acc % 90000000)).toString();
    return '+226$eight';
  }
}
