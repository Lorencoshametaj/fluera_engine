import 'dart:math' as math;

/// 🧠 Cost-transparency tracker for "Chiedi a Fluera AI" responses.
///
/// Goal: surface — non-judgmentally — the cognitive cost of passive reading
/// versus active retrieval, so the student can self-calibrate which mode is
/// actually serving them. Aligns with teoria_cognitiva_apprendimento.md §4
/// (Hypercorrection) and §11 (Illusion of Fluency).
///
/// Tracks per-message read time and exposes a retention estimate. The
/// retention curve is intentionally a back-of-envelope approximation — it
/// is NOT a clinical predictor. The point is to render the cost *visible*,
/// not to claim accuracy that doesn't exist (see feedback_completion_honesty).
class ChatReadTracker {
  final Map<String, DateTime> _firstSeenAt = {};

  /// Mark a message as first visible to the reader. Subsequent calls for
  /// the same id are ignored — the first read window is what counts.
  void markVisible(String messageId, {DateTime? now}) {
    _firstSeenAt.putIfAbsent(messageId, () => now ?? DateTime.now());
  }

  /// Seconds elapsed since [markVisible]. Returns 0 if never marked.
  int secondsRead(String messageId, {DateTime? now}) {
    final start = _firstSeenAt[messageId];
    if (start == null) return 0;
    final dt = (now ?? DateTime.now()).difference(start);
    return dt.inSeconds;
  }

  /// Forget tracking state for a message (e.g. when the chat closes).
  void forget(String messageId) => _firstSeenAt.remove(messageId);

  /// Clear all tracked state.
  void clear() => _firstSeenAt.clear();

  /// Estimated 7-day retention as an integer percentage in [5, 85].
  ///
  /// Heuristic shape: passive reading retention decays roughly exponentially
  /// with the ratio of words/seconds (Ebbinghaus 1885, inverted), scaled to
  /// stay in a plausible band. Tuned conservatively so the badge does NOT
  /// understate retention for short reads.
  ///
  /// Floor 5%: even brief exposure leaves something. Ceiling 85%: passive
  /// reading alone never reaches the >90% bands that retrieval practice
  /// (Roediger & Karpicke 2006) routinely produces.
  static int retention7d({required int readSeconds, required int wordCount}) {
    if (wordCount <= 0) return 5;
    final seconds = math.max(readSeconds, 1);
    final ratio = wordCount / 30.0 / seconds;
    final raw = 0.85 * math.exp(-ratio);
    final clamped = raw.clamp(0.05, 0.85);
    return (clamped * 100).round();
  }

  /// Roughly count words in a chat message body. Whitespace split with
  /// punctuation stripped. Good enough for the cost badge.
  static int countWords(String text) {
    if (text.isEmpty) return 0;
    final cleaned = text.replaceAll(RegExp(r'[^\w\s]'), ' ');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
  }
}
