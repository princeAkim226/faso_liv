import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Initialise Firebase + récupère le token FCM.
/// Retourne null si Firebase n'est pas configuré (pas de google-services.json).
class PushFirebaseImpl {
  PushFirebaseImpl._();

  static bool _initAttempted = false;
  static bool _ok = false;

  static Future<bool> assurerInit() async {
    if (_initAttempted) return _ok;
    _initAttempted = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      // Afficher les notifs aussi en foreground (Android 13+)
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _ok = true;
    } catch (e) {
      debugPrint('FasoLiv: Firebase non prêt ($e)');
      _ok = false;
    }
    return _ok;
  }

  static Future<String?> obtenirToken() async {
    if (!await assurerInit()) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FasoLiv: getToken FCM ($e)');
      return null;
    }
  }

  /// Écoute les messages FCM (app ouverte / arrière-plan).
  static Future<void> ecouterMessages({
    required void Function(String titre, String corps) onMessage,
  }) async {
    if (!await assurerInit()) return;

    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      final titre = n?.title ?? message.data['title']?.toString() ?? 'FasoLiv';
      final corps = n?.body ?? message.data['body']?.toString() ?? '';
      onMessage(titre, corps);
    });

    // Token refresh → l'appelant doit ré-enregistrer
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      // géré côté service via ré-appel activerPourLivreur
    });
  }
}

/// Handler top-level requis par firebase_messaging (app en arrière-plan).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // La notif système est affichée automatiquement par FCM si "notification" payload.
}
