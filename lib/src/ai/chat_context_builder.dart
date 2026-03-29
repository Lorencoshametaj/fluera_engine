import 'dart:ui';
import '../canvas/ai/chat_session_model.dart';
import '../reflow/content_cluster.dart';

/// 📦 CHAT CONTEXT BUILDER
///
/// Collects and formats canvas context (OCR text, semantic titles,
/// audio transcripts, PDF content) for the chat AI prompt.
///
/// Stateless — operates on snapshots of the canvas state.
class ChatContextBuilder {
  /// Max characters for the combined context block.
  static const int maxContextChars = 12000; // ~3000 tokens

  /// Build a formatted context string from cluster data.
  ///
  /// [clusterTexts] — map of clusterId → OCR recognized text.
  /// [clusterTitles] — map of clusterId → AI-generated semantic title.
  /// [audioTranscripts] — map of clusterId → audio transcript text.
  /// [pdfTexts] — optional map of pageIndex → PDF page text.
  /// [scope] — which context scope to apply.
  /// [visibleClusterIds] — cluster IDs visible in viewport (for viewport scope).
  /// [selectedClusterIds] — cluster IDs currently selected.
  static String buildContext({
    required Map<String, String> clusterTexts,
    Map<String, String> clusterTitles = const {},
    Map<String, String> audioTranscripts = const {},
    Map<String, String> pdfTexts = const {},
    required ChatContextScope scope,
    Set<String> visibleClusterIds = const {},
    Set<String> selectedClusterIds = const {},
  }) {
    // 1. Filter clusters by scope
    final relevantIds = _filterByScope(
      allIds: clusterTexts.keys.toSet(),
      scope: scope,
      visibleClusterIds: visibleClusterIds,
      selectedClusterIds: selectedClusterIds,
    );

    if (relevantIds.isEmpty && pdfTexts.isEmpty) {
      return '(No notes available in the current scope)';
    }

    final buffer = StringBuffer();

    // 2. Build cluster sections
    if (relevantIds.isNotEmpty) {
      buffer.writeln('═══ STUDENT NOTES ═══');
      int clusterIndex = 0;
      int totalChars = 0;

      for (final id in relevantIds) {
        if (totalChars >= maxContextChars) break;

        final title = clusterTitles[id];
        final text = clusterTexts[id] ?? '';
        final audio = audioTranscripts[id];

        if (text.trim().isEmpty && (audio == null || audio.trim().isEmpty)) {
          continue;
        }

        clusterIndex++;
        buffer.writeln('');
        buffer.writeln('── Note $clusterIndex${title != null ? ': $title' : ''} ──');

        // OCR text
        if (text.trim().isNotEmpty) {
          final truncated = _truncate(text.trim(), maxContextChars - totalChars);
          buffer.writeln(truncated);
          totalChars += truncated.length;
        }

        // Audio transcript
        if (audio != null && audio.trim().isNotEmpty) {
          final truncated = _truncate(audio.trim(), maxContextChars - totalChars);
          buffer.writeln('[Audio transcript]: $truncated');
          totalChars += truncated.length;
        }
      }
    }

    // 3. PDF content (if scope is activePdf or allCanvas)
    if (pdfTexts.isNotEmpty &&
        (scope == ChatContextScope.activePdf ||
            scope == ChatContextScope.allCanvas)) {
      buffer.writeln('');
      buffer.writeln('═══ PDF CONTENT ═══');
      int totalChars = 0;
      for (final entry in pdfTexts.entries) {
        if (totalChars >= maxContextChars ~/ 2) break; // PDF gets half the budget
        final truncated = _truncate(entry.value.trim(), 2000);
        buffer.writeln('Page ${entry.key}: $truncated');
        totalChars += truncated.length;
      }
    }

    return buffer.toString();
  }

  /// Build the conversation history portion of the prompt.
  static String buildConversationHistory(List<ChatMessage> messages,
      {int maxMessages = 20}) {
    if (messages.isEmpty) return '';

    final recent = messages.length <= maxMessages
        ? messages
        : messages.sublist(messages.length - maxMessages);

    final buffer = StringBuffer();
    buffer.writeln('═══ CONVERSATION HISTORY ═══');
    for (final msg in recent) {
      if (msg.role == ChatMessageRole.system) continue;
      final role = msg.role == ChatMessageRole.user ? 'STUDENT' : 'ATLAS';
      buffer.writeln('$role: ${msg.text}');
    }
    return buffer.toString();
  }

  /// Determine the scope label for display.
  static String scopeLabel(
    ChatContextScope scope, {
    int selectedCount = 0,
    String? pdfName,
  }) {
    return switch (scope) {
      ChatContextScope.allCanvas => '🗂 Tutto il canvas',
      ChatContextScope.selectedClusters =>
        '📝 $selectedCount cluster selezionati',
      ChatContextScope.currentViewport => '👁 Vista corrente',
      ChatContextScope.activePdf => '📄 ${pdfName ?? 'PDF attivo'}',
    };
  }

  // ─── Private ──────────────────────────────────────────────────────────

  static Set<String> _filterByScope({
    required Set<String> allIds,
    required ChatContextScope scope,
    required Set<String> visibleClusterIds,
    required Set<String> selectedClusterIds,
  }) {
    return switch (scope) {
      ChatContextScope.allCanvas => allIds,
      ChatContextScope.selectedClusters =>
        allIds.intersection(selectedClusterIds),
      ChatContextScope.currentViewport =>
        allIds.intersection(visibleClusterIds),
      ChatContextScope.activePdf => const {}, // PDF handled separately
    };
  }

  static String _truncate(String text, int maxLength) {
    if (maxLength <= 0) return '';
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}…';
  }
}
