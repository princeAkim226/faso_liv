import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/course_service.dart';
import '../services/livreur_service.dart';
import '../services/mobile_money_service.dart';
import '../services/portefeuille_service.dart';
import '../services/push_notification_service.dart';

/// Providers des services métier (singletons légers).
final mobileMoneyServiceProvider = Provider<MobileMoneyService>((ref) {
  final service = MobileMoneyService();
  ref.onDispose(service.dispose);
  return service;
});

final portefeuilleServiceProvider = Provider<PortefeuilleService>((ref) {
  return PortefeuilleService(
    mobileMoneyService: ref.watch(mobileMoneyServiceProvider),
  );
});

final livreurServiceProvider = Provider<LivreurService>((ref) {
  return LivreurService();
});

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService();
});

final courseServiceProvider = Provider<CourseService>((ref) {
  return CourseService();
});
