import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../core/utils/ville_burkina.dart';
import '../models/profile.dart';

/// Géolocalisation temps réel du livreur + publication Supabase.
class LocationService {
  LocationService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  StreamSubscription<Position>? _subscription;

  bool get isTracking => _subscription != null;

  Future<bool> assurerPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw AppException(
        'Activez le GPS de votre téléphone pour être visible.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw AppException('Permission de localisation refusée.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw AppException(
        'Localisation bloquée. Autorisez-la dans les réglages du téléphone.',
      );
    }
    return true;
  }

  Future<Position> positionActuelle() async {
    await assurerPermissions();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Future<String> detecterVille() async {
    final pos = await positionActuelle();
    return VilleBurkina.depuisCoordonnees(pos.latitude, pos.longitude);
  }

  Future<void> _mettreAJourVilleProfil(Position pos) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final ville = VilleBurkina.depuisCoordonnees(pos.latitude, pos.longitude);
    try {
      await _supabase.from('profiles').update({'ville': ville}).eq('id', userId);
    } catch (_) {}
  }

  /// Démarre le flux GPS et pousse chaque mise à jour vers Supabase.
  Future<void> demarrerSuivi({
    required void Function(Position position) onPosition,
    void Function(Object error)? onError,
  }) async {
    await assurerPermissions();
    await arreterSuivi(desactiverProfil: false);

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw AppException('Livreur non authentifié.');
    }

    final premiere = await positionActuelle();
    await _mettreAJourVilleProfil(premiere);
    onPosition(premiere);

    // 1) Position d'abord (sinon les clients ne vous voient pas)
    await _publier(premiere);
    // 2) Flag profil
    await _supabase.rpc('set_localisation_active', params: {'p_active': true});

    // 3) Vérifie que la ligne existe bien côté serveur
    final verif = await _supabase
        .from('livreur_positions')
        .select('livreur_id, est_disponible')
        .eq('livreur_id', userId)
        .maybeSingle();
    if (verif == null || verif['est_disponible'] != true) {
      throw AppException(
        'Position non publiée sur le serveur. Réessayez En ligne.',
      );
    }

    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ).listen(
      (pos) async {
        onPosition(pos);
        try {
          await _publier(pos);
        } catch (e) {
          onError?.call(e);
        }
      },
      onError: onError,
    );
  }

  Future<void> arreterSuivi({bool desactiverProfil = true}) async {
    await _subscription?.cancel();
    _subscription = null;
    if (desactiverProfil && _supabase.auth.currentUser != null) {
      try {
        await _supabase
            .rpc('set_localisation_active', params: {'p_active': false});
      } catch (_) {}
    }
  }

  Future<void> _publier(Position pos) async {
    try {
      await _supabase.rpc(
        'upsert_livreur_position',
        params: {
          'p_lat': pos.latitude,
          'p_lng': pos.longitude,
          'p_disponible': true,
        },
      );
    } on PostgrestException catch (e) {
      throw AppException('Publication GPS : ${e.message}');
    }
  }

  Future<Profile> setLocalisationActive(bool active) async {
    try {
      final raw = await _supabase.rpc(
        'set_localisation_active',
        params: {'p_active': active},
      );
      if (raw is Map) {
        return Profile.fromJson(Map<String, dynamic>.from(raw));
      }
      if (raw is List && raw.isNotEmpty) {
        return Profile.fromJson(Map<String, dynamic>.from(raw.first as Map));
      }
      throw AppException('Réponse inattendue');
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }
}
