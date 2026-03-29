/// 💬 CHAT WITH NOTES — Data models.
///
/// Defines the structured types for multi-turn AI chat sessions
/// grounded in the user's canvas notes, clusters, and transcripts.
library;

/// The scope of canvas context provided to the AI during a chat session.
enum ChatContextScope {
  /// All clusters and content on the entire canvas.
  allCanvas,

  /// Only the clusters currently selected by the user.
  selectedClusters,

  /// Only the clusters visible in the current viewport.
  currentViewport,

  /// The active PDF document (if any).
  activePdf,
}

/// The role of a message in the conversation.
enum ChatMessageRole {
  /// Message sent by the user.
  user,

  /// Response from Atlas AI.
  atlas,

  /// System-level context message (not displayed, but included in prompt).
  system,
}

/// A single message in a chat conversation.
class ChatMessage {
  final String id;
  final ChatMessageRole role;
  String text;
  final DateTime timestamp;

  /// Cluster IDs referenced or cited in this message.
  final List<String> referencedClusterIds;

  /// Whether the message is still being streamed.
  bool isStreaming;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.referencedClusterIds = const [],
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'referencedClusterIds': referencedClusterIds,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        role: ChatMessageRole.values.firstWhere(
          (r) => r.name == (json['role'] as String? ?? 'user'),
          orElse: () => ChatMessageRole.user,
        ),
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        referencedClusterIds:
            (json['referencedClusterIds'] as List<dynamic>?)?.cast<String>() ??
                const [],
      );

  @override
  String toString() => 'ChatMessage(${role.name}: ${text.length > 40 ? '${text.substring(0, 40)}...' : text})';
}

/// A full chat session with conversation history and context scope.
class ChatSession {
  final String sessionId;
  final List<ChatMessage> messages;
  ChatContextScope scope;
  final DateTime startedAt;

  /// Optional title generated from first user message.
  String? title;

  ChatSession({
    required this.sessionId,
    List<ChatMessage>? messages,
    this.scope = ChatContextScope.allCanvas,
    DateTime? startedAt,
    this.title,
  })  : messages = messages ?? [],
        startedAt = startedAt ?? DateTime.now();

  /// The last N messages for the AI context window.
  List<ChatMessage> contextWindow({int maxMessages = 20}) {
    if (messages.length <= maxMessages) return messages;
    return messages.sublist(messages.length - maxMessages);
  }

  /// Whether the session has any user messages.
  bool get hasUserMessages =>
      messages.any((m) => m.role == ChatMessageRole.user);

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'scope': scope.name,
        'startedAt': startedAt.toIso8601String(),
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        sessionId: json['sessionId'] as String? ?? '',
        scope: ChatContextScope.values.firstWhere(
          (s) => s.name == (json['scope'] as String? ?? 'allCanvas'),
          orElse: () => ChatContextScope.allCanvas,
        ),
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
                DateTime.now(),
        title: json['title'] as String?,
        messages: (json['messages'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(ChatMessage.fromJson)
                .toList() ??
            [],
      );
}

/// A lightweight record for persisted chat history listing.
class ChatHistoryRecord {
  final String sessionId;
  final DateTime date;
  final String? title;
  final int messageCount;

  const ChatHistoryRecord({
    required this.sessionId,
    required this.date,
    this.title,
    required this.messageCount,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'date': date.toIso8601String(),
        'title': title,
        'messageCount': messageCount,
      };

  factory ChatHistoryRecord.fromJson(Map<String, dynamic> json) =>
      ChatHistoryRecord(
        sessionId: json['sessionId'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        title: json['title'] as String?,
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      );
}
