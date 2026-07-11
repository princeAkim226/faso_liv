import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../models/avis_livreur.dart';

/// Notation des livreurs (avis clients).
class AvisService {
  AvisService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<AvisLivreur>> mesAvisRecus() async {
    try {
      final raw = await _supabase.rpc('mes_avis_recus');
      if (raw == null) return [];
      return (raw as List)
          .map(
            (e) => AvisLivreur.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Avis : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Impossible de charger les avis : $e');
    }
  }

  Future<int> nombreNonLus() async {
    try {
      final raw = await _supabase.rpc('nombre_avis_non_lus');
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> marquerCommeLus() async {
    try {
      await _supabase.rpc('marquer_avis_comme_lus');
    } catch (_) {}
  }
}
