import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../models/livreur_proche.dart';
import '../models/profile.dart';

/// Recherche de livreurs selon localisation et critères (véhicule, rayon).
class LivreurService {
  LivreurService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<LivreurProche>> getLivreursProches({
    required double latitude,
    required double longitude,
    double rayonKm = 5.0,
    TypeVehicule? typeVehicule,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_lat': latitude,
        'p_lng': longitude,
        'p_rayon_km': rayonKm,
      };
      if (typeVehicule != null) {
        params['p_type_vehicule'] = typeVehicule.name;
      }

      final raw = await _supabase.rpc(
        'get_livreurs_proches',
        params: params,
      );

      if (raw == null) return [];
      final list = raw as List<dynamic>;
      return list
          .map((e) => LivreurProche.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Impossible de charger les livreurs proches : ${e.message}',
      );
    } catch (e) {
      throw AppException('Erreur recherche livreurs : $e');
    }
  }

  Future<void> publierPosition({
    required double latitude,
    required double longitude,
    bool disponible = true,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw AppException('Livreur non authentifié.');

    try {
      await _supabase.rpc(
        'upsert_livreur_position',
        params: {
          'p_lat': latitude,
          'p_lng': longitude,
          'p_disponible': disponible,
        },
      );
    } on PostgrestException catch (e) {
      throw AppException('Échec publication position : ${e.message}');
    } catch (e) {
      throw AppException('Erreur position : $e');
    }
  }
}
