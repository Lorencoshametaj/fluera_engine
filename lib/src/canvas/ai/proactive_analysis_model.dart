/// 💡 Proactive Knowledge Gap Analysis — data models.
/// Importable by both the part file and the ProactiveClusterDot widget.
library;

enum ProactiveStatus { idle, pending, ready, seen, dueForReview }

class ProactiveAnalysisEntry {
  final String clusterId;
  ProactiveStatus status;
  String scanText;
  List<String> gaps;
  final DateTime createdAt;

  ProactiveAnalysisEntry({
    required this.clusterId,
    this.status = ProactiveStatus.idle,
    this.scanText = '',
    this.gaps = const [],
  }) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt).inMinutes > 10;
}
