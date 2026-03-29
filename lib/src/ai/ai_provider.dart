import 'atlas_action.dart';

/// Abstract contract for AI providers (Gemini, Claude, GPT, local models).
///
/// Fluera's canvas communicates with any LLM through this single interface.
/// To swap the underlying AI engine, implement this class and inject it
/// into [EngineScope].
///
/// ```dart
/// // Today: Gemini
/// AiProvider atlas = GeminiProvider();
///
/// // Tomorrow: Claude
/// AiProvider atlas = ClaudeProvider();
/// ```
abstract class AiProvider {
  /// Human-readable name of this provider (e.g. "Gemini Flash", "Claude Sonnet").
  String get name;

  /// Initialize the provider (load API keys, warm up connections).
  Future<void> initialize();

  /// Whether the provider is ready to accept requests.
  bool get isInitialized;

  /// Send a user prompt together with the spatial canvas context
  /// and receive structured [AtlasAction]s to execute on the canvas.
  ///
  /// [userPrompt] — natural language request (voice or text).
  /// [canvasContext] — structured JSON list of nodes in the area of interest
  ///   (selected via Lasso, viewport, or proximity).
  ///
  /// Returns an [AtlasResponse] containing parsed actions and optional
  /// text explanation.
  Future<AtlasResponse> askAtlas(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  );

  /// Streaming variant of [askAtlas] — yields partial text chunks
  /// as they arrive from the AI model.
  ///
  /// Used by "Analizza" to show real-time response rendering.
  /// Default implementation falls back to non-streaming [askAtlas].
  Stream<String> askAtlasStream(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async* {
    final response = await askAtlas(userPrompt, canvasContext);
    if (response.explanation != null) {
      yield response.explanation!;
    }
  }

  /// Multi-turn chat streaming — yields partial text chunks for
  /// conversational Q&A grounded in the user's notes.
  ///
  /// [conversationHistory] — previous messages formatted as role: text pairs.
  /// [userMessage] — the new question from the user.
  /// [canvasContext] — structured note context (OCR, titles, transcripts).
  ///
  /// Default implementation falls back to [askAtlasStream].
  Stream<String> askChatStream(
    String conversationHistory,
    String userMessage,
    String canvasContext,
  ) async* {
    yield* askAtlasStream(
      '$conversationHistory\n\nSTUDENT: $userMessage',
      const [],
    );
  }

  /// Release resources held by this provider.
  void dispose();
}

/// Structured response from Atlas AI.
class AtlasResponse {
  /// Parsed actions to execute on the canvas (create nodes, connect, etc.).
  final List<AtlasAction> actions;

  /// Optional text explanation from the AI (shown in a toast or overlay).
  final String? explanation;

  /// Raw JSON response (for debugging).
  final Map<String, dynamic>? rawJson;

  const AtlasResponse({
    required this.actions,
    this.explanation,
    this.rawJson,
  });

  /// Empty response (no actions).
  const AtlasResponse.empty()
      : actions = const [],
        explanation = null,
        rawJson = null;

  @override
  String toString() =>
      'AtlasResponse(actions: ${actions.length}, explanation: ${explanation != null ? "yes" : "no"})';
}
