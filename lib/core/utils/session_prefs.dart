import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Préférences locales : session / dernier numéro.
class SessionPrefs {
  SessionPrefs._();

  static const _kTelephone = 'fasoliv_dernier_telephone';
  static const _kResterConnecte = 'fasoliv_rester_connecte';
  static const _kClientDeviceId = 'fasoliv_client_device_id';

  static Future<void> sauverTelephone(String telephone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTelephone, telephone.trim());
  }

  static Future<String?> lireTelephone() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kTelephone);
  }

  static Future<void> setResterConnecte(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kResterConnecte, value);
  }

  /// Par défaut : true (reconnexion auto sans ressaisir).
  static Future<bool> resterConnecte() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kResterConnecte) ?? true;
  }

  /// Identifiant stable du téléphone (compte client sans numéro saisi).
  static Future<String> assurerIdClientLocal() async {
    final p = await SharedPreferences.getInstance();
    final existant = p.getString(_kClientDeviceId);
    if (existant != null && existant.isNotEmpty) return existant;
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    await p.setString(_kClientDeviceId, id);
    return id;
  }
}
