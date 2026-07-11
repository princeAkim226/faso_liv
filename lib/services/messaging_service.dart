import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';
import '../models/conversation_course.dart';
import '../models/message_chat.dart';

/// Messagerie client ↔ livreur (dès qu'un livreur est choisi).
class MessagingService {
  MessagingService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<MessageChat>> chargerMessages(String courseId) async {
    try {
      final raw = await _supabase
          .from('messages')
          .select()
          .eq('course_id', courseId)
          .order('created_at');
      return (raw as List)
          .map((e) => MessageChat.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('policy') ||
          msg.contains('permission') ||
          e.code == '42501') {
        throw AppException(
          'Messagerie indisponible pour cette course. '
          'Exécutez la migration 009/010 sur Supabase.',
          code: 'CHAT_VERROUILLE',
        );
      }
      throw AppException('Messages : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Impossible de charger les messages : $e');
    }
  }

  Future<MessageChat> envoyer({
    required String courseId,
    required String contenu,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw AppException('Non authentifié');

    final texte = contenu.trim();
    if (texte.isEmpty) throw AppException('Message vide');

    try {
      // RPC sécurisée (recommandée)
      final raw = await _supabase.rpc(
        'envoyer_message',
        params: {
          'p_course_id': courseId,
          'p_contenu': texte,
        },
      );

      if (raw is Map) {
        return MessageChat.fromJson(Map<String, dynamic>.from(raw));
      }
      if (raw is List && raw.isNotEmpty) {
        return MessageChat.fromJson(Map<String, dynamic>.from(raw.first as Map));
      }

      // Fallback insert direct
      final inserted = await _supabase
          .from('messages')
          .insert({
            'course_id': courseId,
            'sender_id': userId,
            'contenu': texte,
          })
          .select()
          .single();
      return MessageChat.fromJson(Map<String, dynamic>.from(inserted));
    } on PostgrestException catch (e) {
      throw AppException(
        'Envoi impossible : ${e.message}',
        code: 'CHAT_VERROUILLE',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Erreur envoi : $e');
    }
  }

  Future<List<ConversationCourse>> mesConversations() async {
    try {
      final raw = await _supabase.rpc('mes_conversations');
      if (raw == null) return [];
      final list = raw as List<dynamic>;
      return list
          .map(
            (e) => ConversationCourse.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Conversations : ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Impossible de charger les conversations : $e');
    }
  }

  /// Écoute temps réel + polling de secours (si Realtime non activé).
  RealtimeChannel souscrire({
    required String courseId,
    required void Function(MessageChat message) onInsert,
  }) {
    return _supabase
        .channel('messages-$courseId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'course_id',
            value: courseId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            onInsert(MessageChat.fromJson(Map<String, dynamic>.from(row)));
          },
        )
        .subscribe();
  }

  /// Polling si Realtime n'est pas disponible sur le projet.
  Timer demarrerPolling({
    required String courseId,
    required Set<String> idsConnus,
    required void Function(MessageChat message) onNouveau,
    Duration interval = const Duration(seconds: 3),
  }) {
    return Timer.periodic(interval, (_) async {
      try {
        final msgs = await chargerMessages(courseId);
        for (final m in msgs) {
          if (idsConnus.add(m.id)) {
            onNouveau(m);
          }
        }
      } catch (_) {}
    });
  }
}
