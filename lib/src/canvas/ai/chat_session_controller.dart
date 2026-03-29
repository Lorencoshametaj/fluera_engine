import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../ai/ai_provider.dart';
import '../../ai/chat_context_builder.dart';
import '../../utils/safe_path_provider.dart';
import 'chat_session_model.dart';

/// 💬 CHAT WITH NOTES — Session controller.
///
/// Manages multi-turn AI conversations grounded in the user's canvas notes.
///
/// Responsibilities:
/// - Multi-turn conversation with context window management
/// - Streaming AI responses via [AiProvider.askChatStream]
/// - Context building from clusters, audio, PDF
/// - Session history persistence (JSON in app documents dir)
/// - Quick actions: summarize, generate quiz prompt, flashcards
class ChatSessionController extends ChangeNotifier {
  final AiProvider _provider;

  ChatSession? _session;
  ChatSession? get session => _session;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  String? _error;
  String? get error => _error;

  // Context data — set externally by the canvas wiring
  Map<String, String> clusterTexts = {};
  Map<String, String> clusterTitles = {};
  Map<String, String> audioTranscripts = {};
  Map<String, String> pdfTexts = {};
  Set<String> visibleClusterIds = {};
  Set<String> selectedClusterIds = {};

  // History
  List<ChatHistoryRecord> _history = [];
  List<ChatHistoryRecord> get history => List.unmodifiable(_history);

  ChatSessionController({
    required AiProvider provider,
  }) : _provider = provider {
    _loadHistory();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Start a new chat session with the given context scope.
  void startSession({ChatContextScope scope = ChatContextScope.allCanvas}) {
    _session = ChatSession(
      sessionId: 'chat_${DateTime.now().millisecondsSinceEpoch}',
      scope: scope,
    );
    _error = null;
    notifyListeners();
  }

  /// Change the context scope mid-conversation.
  void switchScope(ChatContextScope scope) {
    _session?.scope = scope;
    notifyListeners();
  }

  /// Resume an existing session (e.g. from history).
  void resumeSession(ChatSession session) {
    _session = session;
    _error = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Message sending
  // ─────────────────────────────────────────────────────────────────────────

  /// Send a user message and stream the AI response.
  Future<void> sendMessage(String text) async {
    if (_session == null || _isStreaming) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _error = null;

    // 1. Add user message
    final userMsg = ChatMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      role: ChatMessageRole.user,
      text: trimmed,
    );
    _session!.messages.add(userMsg);

    // Auto-set title from first message
    _session!.title ??= trimmed.length > 50
        ? '${trimmed.substring(0, 47)}...'
        : trimmed;

    // 2. Create placeholder for atlas response
    final atlasMsg = ChatMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch + 1}',
      role: ChatMessageRole.atlas,
      text: '',
      isStreaming: true,
    );
    _session!.messages.add(atlasMsg);
    _isStreaming = true;
    notifyListeners();

    // 3. Build context
    final scope = _session!.scope;
    final canvasContext = ChatContextBuilder.buildContext(
      clusterTexts: clusterTexts,
      clusterTitles: clusterTitles,
      audioTranscripts: audioTranscripts,
      pdfTexts: pdfTexts,
      scope: scope,
      visibleClusterIds: visibleClusterIds,
      selectedClusterIds: selectedClusterIds,
    );

    final conversationHistory = ChatContextBuilder.buildConversationHistory(
      _session!.contextWindow(maxMessages: 18),
    );

    // 4. Stream response
    try {
      if (!_provider.isInitialized) await _provider.initialize();

      final stream = _provider.askChatStream(
        conversationHistory,
        trimmed,
        canvasContext,
      );

      await for (final chunk in stream) {
        atlasMsg.text += chunk;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString().length > 150
          ? '${e.toString().substring(0, 150)}...'
          : e.toString();
      if (atlasMsg.text.isEmpty) {
        atlasMsg.text = '⚠️ Connection error. Please try again.';
      }
    } finally {
      atlasMsg.isStreaming = false;
      _isStreaming = false;
      notifyListeners();
      _saveCurrentSession();
      _saveSessionMessages();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Quick actions
  // ─────────────────────────────────────────────────────────────────────────

  /// Send a "summarize my notes" quick action.
  Future<void> summarize() =>
      sendMessage('Summarize all my notes concisely, highlighting key concepts and connections.');

  /// Send a "generate quiz" quick action.
  Future<void> generateQuizPrompt() =>
      sendMessage('Generate 3 study questions based on my notes. Include the answers.');

  /// Send a "generate flashcards" quick action.
  Future<void> generateFlashcards() =>
      sendMessage('Create 5 flashcards (front/back) from the key concepts in my notes.');

  /// Send an "explain this" quick action for a specific concept.
  Future<void> explainConcept(String concept) =>
      sendMessage('Explain "$concept" in detail, using my notes as context.');

  // ─────────────────────────────────────────────────────────────────────────
  // History persistence
  // ─────────────────────────────────────────────────────────────────────────

  Future<File?> _historyFile() async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      return File('${dir.path}/fluera_chat_history.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _historyFile();
      if (file == null || !await file.exists()) return;
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _history = list
          .whereType<Map<String, dynamic>>()
          .map(ChatHistoryRecord.fromJson)
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ ChatHistory load error: $e');
    }
  }

  Future<void> _saveCurrentSession() async {
    final s = _session;
    if (s == null || !s.hasUserMessages) return;

    // Update or add history record
    final existingIdx = _history.indexWhere((h) => h.sessionId == s.sessionId);
    final record = ChatHistoryRecord(
      sessionId: s.sessionId,
      date: s.startedAt,
      title: s.title,
      messageCount: s.messages.length,
    );

    if (existingIdx >= 0) {
      _history[existingIdx] = record;
    } else {
      _history.insert(0, record);
    }

    // Keep last 30 sessions
    if (_history.length > 30) _history = _history.take(30).toList();

    try {
      final file = await _historyFile();
      if (file == null) return;
      await file.writeAsString(
        jsonEncode(_history.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ ChatHistory save error: $e');
    }
  }

  /// Clear the current session and start fresh.
  void clearSession() {
    _session = null;
    _error = null;
    _isStreaming = false;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History access (for UI)
  // ─────────────────────────────────────────────────────────────────────────

  /// Async accessor for the history panel.
  Future<List<ChatHistoryRecord>> getHistory() async {
    if (_history.isEmpty) await _loadHistory();
    return List.unmodifiable(_history);
  }

  /// Delete a single session from history.
  Future<void> deleteHistory(String sessionId) async {
    _history.removeWhere((h) => h.sessionId == sessionId);
    notifyListeners();

    // Remove session messages file
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir != null) {
        final msgFile = File('${dir.path}/fluera_chat_$sessionId.json');
        if (await msgFile.exists()) await msgFile.delete();
      }
    } catch (_) {}

    // Persist updated history list
    try {
      final file = await _historyFile();
      if (file != null) {
        await file.writeAsString(
          jsonEncode(_history.map((r) => r.toJson()).toList()),
        );
      }
    } catch (e) {
      debugPrint('⚠️ ChatHistory delete error: $e');
    }
  }

  /// Load a full session from persisted messages.
  Future<void> loadSession(String sessionId) async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return;

      final msgFile = File('${dir.path}/fluera_chat_$sessionId.json');
      if (!await msgFile.exists()) return;

      final raw = await msgFile.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _session = ChatSession.fromJson(json);
      _error = null;
      _isStreaming = false;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ ChatSession load error: $e');
    }
  }

  /// Save full session messages to a separate file.
  Future<void> _saveSessionMessages() async {
    final s = _session;
    if (s == null || !s.hasUserMessages) return;

    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return;

      final msgFile = File('${dir.path}/fluera_chat_${s.sessionId}.json');
      await msgFile.writeAsString(jsonEncode(s.toJson()));
    } catch (e) {
      debugPrint('⚠️ ChatSession message save error: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
