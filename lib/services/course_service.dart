import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../models/course.dart';
import '../models/course_historique.dart';
import 'push_notification_service.dart';

/// Opérations sur le cycle de vie des courses.
class CourseService {
  CourseService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Charge une course par son identifiant.
  Future<Course> getCourse(String courseId) async {
    try {
      final data = await _supabase
          .from('courses')
          .select()
          .eq('id', courseId)
          .single();
      return Course.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Course introuvable : ${e.message}');
    } catch (e) {
      throw AppException('Erreur chargement course : $e');
    }
  }

  /// Côté demandeur : propose un livreur (statut → `propose`).
  Future<Course> proposerLivreur({
    required String courseId,
    required String livreurId,
  }) async {
    try {
      final raw = await _supabase.rpc(
        'proposer_livreur',
        params: {
          'p_course_id': courseId,
          'p_livreur_id': livreurId,
        },
      );

      return _parseCourseRpc(raw);
    } on PostgrestException catch (e) {
      throw AppException('Impossible de proposer ce livreur : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Erreur proposition livreur : $e');
    }
  }

  /// Côté livreur : valide la livraison avec le code OTP à 4 chiffres.
  ///
  /// En cas de succès : statut → `livre`, commission débitée du portefeuille.
  Future<Course> validerLivraisonOtp({
    required String courseId,
    required String codeOtp,
  }) async {
    final code = codeOtp.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      throw AppException('Le code OTP doit contenir exactement 4 chiffres.');
    }

    try {
      final raw = await _supabase.rpc(
        'valider_livraison_otp',
        params: {
          'p_course_id': courseId,
          'p_code_otp': code,
        },
      );

      return _parseCourseRpc(raw);
    } on PostgrestException catch (e) {
      if (e.message.contains('CODE_OTP_INVALIDE')) {
        throw CodeOtpInvalideException();
      }
      if (e.message.contains('SOLDE_INSUFFISANT')) {
        throw AppException(
          'Solde insuffisant pour débiter la commission. Rechargez votre compte.',
          code: 'SOLDE_INSUFFISANT',
        );
      }
      throw AppException('Validation échouée : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Erreur validation OTP : $e');
    }
  }

  /// Marque la course comme payée.
  Future<Course> marquerPayee(String courseId) async {
    try {
      final raw = await _supabase.rpc(
        'marquer_course_payee',
        params: {'p_course_id': courseId},
      );
      return _parseCourseRpc(raw);
    } on PostgrestException catch (e) {
      throw AppException('Paiement : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Erreur paiement : $e');
    }
  }

  /// Crée une course et assigne le livreur → débloque téléphone + chat.
  Future<Course> demarrerAvecLivreur({
    required String livreurId,
    required double latitude,
    required double longitude,
    String? description,
  }) async {
    try {
      final raw = await _supabase.rpc(
        'demarrer_course_avec_livreur',
        params: {
          'p_livreur_id': livreurId,
          'p_lat': latitude,
          'p_lng': longitude,
          if (description != null && description.trim().isNotEmpty)
            'p_description': description.trim(),
        },
      );
      final course = _parseCourseRpc(raw);
      // Push hors-app (Edge Function FCM) — non bloquant
      unawaited(
        PushNotificationService().notifierLivreurChoisi(
          courseId: course.id,
          livreurId: livreurId,
        ),
      );
      return course;
    } on PostgrestException catch (e) {
      throw AppException('Impossible de contacter ce livreur : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Erreur démarrage course : $e');
    }
  }

  /// Note le livreur (1–5 étoiles) pour une course.
  Future<void> noterLivreur({
    required String courseId,
    required int note,
    String? commentaire,
  }) async {
    if (note < 1 || note > 5) {
      throw AppException('Choisissez une note entre 1 et 5.');
    }
    try {
      await _supabase.rpc(
        'noter_livreur',
        params: {
          'p_course_id': courseId,
          'p_note': note,
          'p_commentaire': commentaire,
        },
      );
    } on PostgrestException catch (e) {
      throw AppException('Notation : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Impossible d\'enregistrer la note : $e');
    }
  }

  /// Livreur : En route (`accepte`) ou Sur place (`recupere`) + message chat.
  Future<Course> avancerStatut({
    required String courseId,
    required String nouveauStatut,
  }) async {
    try {
      final raw = await _supabase.rpc(
        'avancer_statut_course',
        params: {
          'p_course_id': courseId,
          'p_nouveau_statut': nouveauStatut,
        },
      );
      return _parseCourseRpc(raw);
    } on PostgrestException catch (e) {
      throw AppException('Statut : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Impossible de mettre à jour le statut : $e');
    }
  }

  /// Historique des courses de l'utilisateur connecté.
  Future<List<CourseHistorique>> mesCoursesHistorique() async {
    try {
      final raw = await _supabase.rpc('mes_courses_historique');
      if (raw is! List) return [];
      return raw
          .map((e) => CourseHistorique.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Historique : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Impossible de charger l\'historique : $e');
    }
  }

  Course _parseCourseRpc(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      return Course.fromJson(Map<String, dynamic>.from(raw.first as Map));
    }
    if (raw is Map) {
      return Course.fromJson(Map<String, dynamic>.from(raw));
    }
    throw AppException('Réponse serveur inattendue.');
  }
}
