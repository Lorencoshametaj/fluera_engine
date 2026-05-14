import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../ai/ai_provider.dart';
import '../../ai/chat_context_builder.dart';
import '../../ai/telemetry_recorder.dart';
import '../../utils/safe_path_provider.dart';
import 'chat_session_model.dart';

/// Bridge from the chat surface to the cognitive feature controllers
/// (Ghost Map, Exam Session, Socratic V2, source compare).
///
/// The quick-action chips in [ChatOverlay] used to send hard-coded prompts
/// like "Summarize my notes" — a pattern that violates the product's
/// teoria_cognitiva_apprendimento.md (Generation Effect §3, Productive
/// Failure T4). Instead, the chips now invoke these callbacks so that
/// the right cognitive feature opens directly, bypassing the LLM.
///
/// Any null callback is treated as "feature not available in this context"
/// — the chip will surface a graceful no-op (snackbar) at the UI layer.
class ChatActionRouter {
  /// Open the Ghost Map gap-analysis overlay. Closes the chat first.
  final VoidCallback? onTriggerGhostMap;

  /// Open the Exam Session configuration. Closes the chat first.
  final VoidCallback? onTriggerExam;

  /// Start a Socratic V2 mini-session. [clusterId] is the preselected
  /// cluster if any; if null, the canvas decides UX (picker or full scope).
  final void Function(String? clusterId)? onTriggerSocraticOnCluster;

  /// Open split-view PDF/source compare. [clusterId] is the cluster the
  /// student wants to verify against the source.
  final void Function(String? clusterId)? onTriggerSourceCompare;

  const ChatActionRouter({
    this.onTriggerGhostMap,
    this.onTriggerExam,
    this.onTriggerSocraticOnCluster,
    this.onTriggerSourceCompare,
  });
}

/// 💬 CHAT WITH NOTES — Session controller.
///
/// Manages multi-turn AI conversations grounded in the user's canvas notes.
///
/// Responsibilities:
/// - Multi-turn conversation with context window management
/// - Streaming AI responses via [AiProvider.askChatStream]
/// - Context building from clusters, audio, PDF
/// - Session history persistence (JSON in app documents dir)
/// - Quick actions: route to cognitive features (Ghost Map, Exam, Socratic)
class ChatSessionController extends ChangeNotifier {
  final AiProvider _provider;
  final ChatActionRouter _router;
  final TelemetryRecorder _telemetry;

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
    ChatActionRouter? router,
    TelemetryRecorder? telemetry,
  })  : _provider = provider,
        _router = router ?? const ChatActionRouter(),
        _telemetry = telemetry ?? TelemetryRecorder.noop {
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

    // 💬 Sprint Chat-F telemetry: first message → step_12_chat_started.
    // (Step numbering after Exam step_11; chat is post-V1 cognitive
    // feature ordering.)
    final isFirstMessage = _session!.messages.isEmpty;
    if (isFirstMessage) {
      _telemetry.logEvent('step_12_chat_started', properties: {
        'session_id': _session!.sessionId,
        'scope': _session!.scope.name,
      });
    }

    // 1. Add user message
    final userMsg = ChatMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      role: ChatMessageRole.user,
      text: trimmed,
    );
    _session!.messages.add(userMsg);

    // 💬 Per-message telemetry. Properties capped to avoid PII leak.
    _telemetry.logEvent('step_12_chat_message_sent', properties: {
      'session_id': _session!.sessionId,
      'message_id': userMsg.id,
      'message_index': _session!.messages.length,
      'message_length': trimmed.length,
    });

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
  // Quick actions — route to cognitive features, not to the LLM
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Rationale: the previous quick actions (summarize / generateFlashcards /
  // explainConcept) trained the student in the exact pattern the product
  // is supposed to break — passive consumption of LLM output. The new
  // actions hand the student off to the matching cognitive feature where
  // the AI asks and the student writes.

  /// 🗺 Find my gaps → Ghost Map. Returns `true` if a handler was wired.
  bool findGaps() {
    if (_router.onTriggerGhostMap == null) return false;
    _router.onTriggerGhostMap!();
    return true;
  }

  /// 🎯 Quiz me → Exam Session. Returns `true` if a handler was wired.
  bool startQuiz() {
    if (_router.onTriggerExam == null) return false;
    _router.onTriggerExam!();
    return true;
  }

  /// 🤺 Challenge me → Socratic V2 mini-session. If a single cluster is
  /// selected it becomes the scope; otherwise the canvas decides UX.
  /// Returns `true` if a handler was wired.
  bool startSocratic() {
    if (_router.onTriggerSocraticOnCluster == null) return false;
    final preselected =
        selectedClusterIds.length == 1 ? selectedClusterIds.first : null;
    _router.onTriggerSocraticOnCluster!(preselected);
    return true;
  }

  /// 🔍 Compare with source → split-view PDF reader. The cluster is the
  /// student's elaboration to verify against the source (§32). Returns
  /// `true` if a handler was wired.
  bool compareWithSource() {
    if (_router.onTriggerSourceCompare == null) return false;
    final preselected =
        selectedClusterIds.length == 1 ? selectedClusterIds.first : null;
    _router.onTriggerSourceCompare!(preselected);
    return true;
  }

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

  /// 🚩 Sprint Chat-F — user reports a chat message as poorly translated /
  /// not natural / fake-AI. Available only when the active
  /// `AiLanguagePreference` is in `aiBootstrap` tier (per
  /// `docs/socratic_native_validation_protocol.md`). Pure telemetry —
  /// no state mutation, no LLM call.
  ///
  /// Reason is optional free-text (cap 500 chars to fit Sentry tags).
  void reportMessage(ChatMessage m, String langCode, {String? reason}) {
    _telemetry.logEvent('chat_message_reported', properties: {
      'message_id': m.id,
      'message_text':
          m.text.length > 500 ? m.text.substring(0, 500) : m.text,
      'role': m.role.name,
      'session_id': _session?.sessionId ?? 'unknown',
      'lang_code': langCode,
      'reason': (reason == null || reason.isEmpty)
          ? 'unspecified'
          : (reason.length > 500 ? reason.substring(0, 500) : reason),
    });
  }

  /// Clear the current session and start fresh.
  void clearSession() {
    // 💬 Sprint Chat-F telemetry: emit session-ended on a session that
    // had at least 1 message (else it's a noop clear, no value to log).
    final s = _session;
    if (s != null && s.messages.isNotEmpty) {
      _telemetry.logEvent('step_12_chat_session_ended', properties: {
        'session_id': s.sessionId,
        'message_count': s.messages.length,
        'scope': s.scope.name,
      });
    }
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
