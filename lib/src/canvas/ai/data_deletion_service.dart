// ============================================================================
// 🗑️ DATA DELETION SERVICE — Right to be forgotten (Art. 17)
//
// Specifica: A16-06 → A16-10
//
// GDPR Art. 17 requires the ability to delete ALL personal data
// upon request. This service defines the complete deletion pipeline.
//
// DELETION SCOPE:
//   1. Handwriting strokes + ink data
//   2. OCR / HTR index (handwriting_index_service)
//   3. SRS card data + review history
//   4. AI conversation history (Socratic sessions)
//   5. Canvas metadata + zone names
//   6. Audio recordings (lecture sync)
//   7. Ghost Map / FoW diagnostic data
//   8. User preferences + consent records
//   9. Telemetry data (if any)
//   10. Cached embeddings + concept maps
//
// RULES:
//   - Deletion is IRREVERSIBLE (no soft-delete for Art. 17)
//   - Must complete within 30 days (Art. 12(3))
//   - Must notify all processors (Firebase, analytics, etc.)
//   - Audit log of the deletion itself is RETAINED (legal basis: Art. 17(3)(e))
//
// ARCHITECTURE:
//   Pure model defining the deletion pipeline.
//   The host app implements the actual database operations.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 🗑️ Categories of data to delete.
enum DeletionCategory {
  /// Handwriting strokes, ink data, rendered images.
  inkData,

  /// OCR/HTR index, FTS5 tables, text recognition results.
  ocrIndex,

  /// SRS card data, review history, FSRS weights.
  srsData,

  /// AI conversation history (Socratic sessions, chat logs).
  aiHistory,

  /// Canvas metadata, zone names, page configurations.
  canvasMetadata,

  /// Audio recordings (lecture sync).
  audioRecordings,

  /// Ghost Map data, Fog of War sessions, diagnostic results.
  diagnosticData,

  /// User preferences, consent records, tier state.
  preferences,

  /// Telemetry data, anonymous usage stats.
  telemetry,

  /// Cached embeddings, concept maps, AI-generated content.
  cachedAiData,
}

/// 🗑️ Status of a deletion operation.
enum DeletionStatus {
  /// Not started.
  pending,

  /// Currently deleting.
  inProgress,

  /// Successfully deleted.
  completed,

  /// Failed (with error).
  failed,
}

/// 🗑️ Result of a deletion step.
class DeletionStepResult {
  final DeletionCategory category;
  final DeletionStatus status;
  final int itemsDeleted;
  final String? error;
  final DateTime timestamp;

  DeletionStepResult({
    required this.category,
    required this.status,
    this.itemsDeleted = 0,
    this.error,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'status': status.name,
        'itemsDeleted': itemsDeleted,
        'error': error,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// 🗑️ Complete deletion request.
class DeletionRequest {
  /// Unique request ID.
  final String requestId;

  /// When the request was created.
  final DateTime requestedAt;

  /// Categories to delete (default: ALL).
  final Set<DeletionCategory> categories;

  /// Reason for deletion (optional, for audit).
  final String? reason;

  /// Results per category.
  final Map<DeletionCategory, DeletionStepResult> results;

  /// Overall status.
  DeletionStatus get overallStatus {
    if (results.isEmpty) return DeletionStatus.pending;
    if (results.values.any((r) => r.status == DeletionStatus.failed)) {
      return DeletionStatus.failed;
    }
    if (results.values.every((r) => r.status == DeletionStatus.completed)) {
      return DeletionStatus.completed;
    }
    return DeletionStatus.inProgress;
  }

  /// Total items deleted across all categories.
  int get totalItemsDeleted =>
      results.values.fold(0, (sum, r) => sum + r.itemsDeleted);

  DeletionRequest({
    required this.requestId,
    Set<DeletionCategory>? categories,
    this.reason,
  })  : requestedAt = DateTime.now(),
        categories = categories ?? DeletionCategory.values.toSet(),
        results = {};

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'requestedAt': requestedAt.toIso8601String(),
        'categories': categories.map((c) => c.name).toList(),
        'reason': reason,
        'results': results.map((k, v) => MapEntry(k.name, v.toJson())),
        'overallStatus': overallStatus.name,
        'totalItemsDeleted': totalItemsDeleted,
      };
}

/// 🗑️ Data Deletion Service (A16, Art. 17).
///
/// Orchestrates the complete deletion pipeline. The host app registers
/// deletion handlers for each category, and this service coordinates them.
///
/// Usage:
/// ```dart
/// final service = DataDeletionService();
///
/// // Register handlers (host app provides actual DB operations)
/// service.registerHandler(DeletionCategory.inkData, (req) async {
///   final count = await db.delete('strokes');
///   return DeletionStepResult(
///     category: DeletionCategory.inkData,
///     status: DeletionStatus.completed,
///     itemsDeleted: count,
///   );
/// });
///
/// // Execute deletion
/// final request = await service.requestFullDeletion(reason: 'User request');
/// ```
class DataDeletionService extends ChangeNotifier {
  /// Registered deletion handlers.
  final Map<DeletionCategory, Future<DeletionStepResult> Function(DeletionRequest)>
      _handlers = {};

  /// History of deletion requests (for Art. 17(3)(e) audit).
  final List<DeletionRequest> _requestHistory = [];

  /// Whether a deletion is in progress.
  bool _isDeleting = false;
  bool get isDeleting => _isDeleting;

  /// Most recent deletion request.
  DeletionRequest? get lastRequest =>
      _requestHistory.isNotEmpty ? _requestHistory.last : null;

  /// Full request history.
  List<DeletionRequest> get requestHistory =>
      List.unmodifiable(_requestHistory);

  /// Register a deletion handler for a category.
  void registerHandler(
    DeletionCategory category,
    Future<DeletionStepResult> Function(DeletionRequest) handler,
  ) {
    _handlers[category] = handler;
  }

  /// Request complete deletion of all data (Art. 17).
  ///
  /// Executes all registered handlers in sequence.
  /// Returns the [DeletionRequest] with results.
  Future<DeletionRequest> requestFullDeletion({String? reason}) async {
    return requestDeletion(
      categories: DeletionCategory.values.toSet(),
      reason: reason ?? 'Richiesta di cancellazione completa (Art. 17 GDPR)',
    );
  }

  /// Request deletion of specific categories.
  Future<DeletionRequest> requestDeletion({
    required Set<DeletionCategory> categories,
    String? reason,
  }) async {
    if (_isDeleting) {
      throw StateError('A deletion is already in progress');
    }

    _isDeleting = true;
    notifyListeners();

    final request = DeletionRequest(
      requestId: 'del_${DateTime.now().millisecondsSinceEpoch}',
      categories: categories,
      reason: reason,
    );

    try {
      // Use ordered pipeline to respect data dependencies
      // (cached → derived → source → metadata).
      final ordered = orderedPipeline.where(categories.contains);
      for (final category in ordered) {
        final handler = _handlers[category];
        if (handler != null) {
          try {
            final result = await handler(request);
            request.results[category] = result;
          } catch (e) {
            request.results[category] = DeletionStepResult(
              category: category,
              status: DeletionStatus.failed,
              error: e.toString(),
            );
          }
        } else {
          // No handler registered — mark as completed (nothing to delete).
          request.results[category] = DeletionStepResult(
            category: category,
            status: DeletionStatus.completed,
            itemsDeleted: 0,
          );
        }
      }
    } finally {
      _isDeleting = false;
      _requestHistory.add(request);
      notifyListeners();
    }

    return request;
  }

  /// Get ordered deletion pipeline (dependencies respected).
  ///
  /// Deletion order matters: cached data first, then derived data,
  /// then source data, then metadata.
  static List<DeletionCategory> get orderedPipeline => const [
        DeletionCategory.cachedAiData,    // 1. Cached/derived first
        DeletionCategory.telemetry,       // 2. Analytics
        DeletionCategory.diagnosticData,  // 3. Diagnostic sessions
        DeletionCategory.aiHistory,       // 4. AI conversation logs
        DeletionCategory.srsData,         // 5. SRS scheduling
        DeletionCategory.ocrIndex,        // 6. Search index
        DeletionCategory.audioRecordings, // 7. Audio files
        DeletionCategory.inkData,         // 8. Source ink data
        DeletionCategory.canvasMetadata,  // 9. Canvas structure
        DeletionCategory.preferences,     // 10. User prefs (last)
      ];
}
