/// Message de chat entre demandeur et livreur.
class MessageChat {
  const MessageChat({
    required this.id,
    required this.courseId,
    required this.senderId,
    required this.contenu,
    required this.createdAt,
    this.lu = false,
  });

  final String id;
  final String courseId;
  final String senderId;
  final String contenu;
  final DateTime createdAt;
  final bool lu;

  factory MessageChat.fromJson(Map<String, dynamic> json) {
    return MessageChat(
      id: json['id']?.toString() ?? '',
      courseId: json['course_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      contenu: json['contenu']?.toString() ?? '',
      lu: json['lu'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
