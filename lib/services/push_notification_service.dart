import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_firebase_impl.dart';

/// Notifications hors-app (FCM) + alertes locales via Realtime.
///
/// - **App en mémoire** (ouverte / arrière-plan) : Realtime → notif locale.
/// - **App tuée** : nécessite Firebase (`google-services.json` + Edge Function
///   `notify-livreur` + secret `FCM_SERVER_KEY`). Voir SUPABASE_SETUP.md.
class PushNotificationService {
  PushNotificationService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  RealtimeChannel? _channel;
  bool _ready = false;
  bool _firebaseOk = false;

  static const _channelId = 'fasoliv_courses';
  static const _channelName = 'Courses FasoLiv';

  Future<void> initialiser() async {
    if (_ready) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      await Permission.notification.request();
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Alertes quand un client vous choisit',
          importance: Importance.high,
        ),
      );
    }

    try {
      _firebaseOk = await PushFirebaseImpl.assurerInit();
      if (_firebaseOk) {
        await PushFirebaseImpl.ecouterMessages(
          onMessage: (titre, corps) =>
              afficherLocale(titre: titre, corps: corps),
        );
      }
    } catch (e) {
      debugPrint('FasoLiv push: Firebase non configuré ($e)');
      _firebaseOk = false;
    }

    _ready = true;
  }

  /// À appeler quand le livreur est connecté.
  Future<void> activerPourLivreur() async {
    await initialiser();
    await _enregistrerTokenSiPossible();
    await _ecouterNotificationsRealtime();
  }

  Future<void> _enregistrerTokenSiPossible() async {
    final token = await PushFirebaseImpl.obtenirToken();
    if (token == null || token.isEmpty) return;
    try {
      await _supabase.rpc('enregistrer_fcm_token', params: {'p_token': token});
      _firebaseOk = true;
      debugPrint('FasoLiv push: token FCM enregistré');
    } catch (e) {
      debugPrint('FasoLiv push: enregistrement token échoué ($e)');
    }
  }

  Future<void> _ecouterNotificationsRealtime() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _channel?.unsubscribe();
    _channel = _supabase
        .channel('notif-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final titre = row['titre']?.toString() ?? 'FasoLiv';
            final corps = row['corps']?.toString() ?? '';
            afficherLocale(titre: titre, corps: corps);
          },
        )
        .subscribe();
  }

  Future<void> afficherLocale({
    required String titre,
    required String corps,
  }) async {
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      titre,
      corps,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Alertes courses FasoLiv',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Déclenche l'Edge Function FCM après choix d'un livreur.
  Future<void> notifierLivreurChoisi({
    required String courseId,
    required String livreurId,
  }) async {
    try {
      await _supabase.functions.invoke(
        'notify-livreur',
        body: {
          'course_id': courseId,
          'livreur_id': livreurId,
        },
      );
    } catch (e) {
      debugPrint('FasoLiv push: invoke notify-livreur ($e)');
    }
  }

  Future<void> desactiver() async {
    await _channel?.unsubscribe();
    _channel = null;
  }

  bool get firebaseConfigure => _firebaseOk;
}
