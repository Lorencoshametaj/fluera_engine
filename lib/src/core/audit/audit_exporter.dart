import 'dart:convert';

import 'audit_entry.dart';

/// Supported audit export formats.
enum AuditExportFormat {
  /// Standard JSON array of entry objects.
  json,

  /// Comma-separated values with header row.
  csv,

  /// Newline-delimited JSON (one JSON object per line).
  ///
  /// Ideal for streaming processors, log aggregators, and
  /// append-to-file workflows.
  jsonLines,
}

/// 🔒 AUDIT EXPORTER — Compliance-grade export for audit trails.
///
/// Converts [AuditEntry] lists into structured formats suitable for:
/// - **GDPR data access requests** — full history of operations on user data
/// - **SOC2 / ISO 27001 audits** — structured event logs with timestamps
/// - **Legal discovery** — immutable, timestamped operation records
/// - **Analytics pipelines** — JSONL for streaming ingestion
///
/// ```dart
/// final entries = auditLog.query(AuditQuery(limit: 1000));
///
/// // JSON export
/// final json = AuditExporter.export(entries);
///
/// // CSV export
/// final csv = AuditExporter.export(entries, format: AuditExportFormat.csv);
///
/// // Compliance report with metadata
/// final report = AuditExporter.generateComplianceReport(
///   entries,
///   documentId: 'doc-2024-001',
///   generatedBy: 'admin@company.com',
/// );
/// ```
class AuditExporter {
  // Prevent instantiation — all methods are static.
  AuditExporter._();

  /// Export audit entries in the specified [format].
  ///
  /// Returns a string representation suitable for file storage or
  /// network transmission.
  static String export(
    List<AuditEntry> entries, {
    AuditExportFormat format = AuditExportFormat.json,
  }) {
    switch (format) {
      case AuditExportFormat.json:
        return _exportJson(entries);
      case AuditExportFormat.csv:
        return _exportCsv(entries);
      case AuditExportFormat.jsonLines:
        return _exportJsonLines(entries);
    }
  }

  /// Generate a structured compliance report.
  ///
  /// Returns a JSON-serializable map containing:
  /// - Report metadata (document ID, generator, timestamp, version)
  /// - Summary statistics (total entries, action breakdown, severity breakdown)
  /// - Full audit trail entries
  ///
  /// The report format is designed for regulatory submission and long-term
  /// archival.
  static Map<String, dynamic> generateComplianceReport(
    List<AuditEntry> entries, {
    required String documentId,
    required String generatedBy,
    String reportVersion = '1.0.0',
  }) {
    // Action breakdown
    final actionCounts = <String, int>{};
    for (final entry in entries) {
      final key = entry.action.name;
      actionCounts[key] = (actionCounts[key] ?? 0) + 1;
    }

    // Severity breakdown
    final severityCounts = <String, int>{};
    for (final entry in entries) {
      final key = entry.severity.name;
      severityCounts[key] = (severityCounts[key] ?? 0) + 1;
    }

    // Unique actors
    final actors = entries.map((e) => e.actor).toSet().toList()..sort();

    // Time range
    DateTime? earliest;
    DateTime? latest;
    for (final entry in entries) {
      if (earliest == null || entry.timestamp.isBefore(earliest)) {
        earliest = entry.timestamp;
      }
      if (latest == null || entry.timestamp.isAfter(latest)) {
        latest = entry.timestamp;
      }
    }

    return {
      'report': {
        'version': reportVersion,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'generatedBy': generatedBy,
        'documentId': documentId,
        'format': 'fluera-audit-report',
      },
      'summary': {
        'totalEntries': entries.length,
        'timeRange': {
          if (earliest != null) 'start': earliest.toIso8601String(),
          if (latest != null) 'end': latest.toIso8601String(),
        },
        'actors': actors,
        'actionBreakdown': actionCounts,
        'severityBreakdown': severityCounts,
      },
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FORMAT IMPLEMENTATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export as a pretty-printed JSON array.
  static String _exportJson(List<AuditEntry> entries) {
    final jsonList = entries.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(jsonList);
  }

  /// Export as CSV with header row.
  ///
  /// Fields containing commas, quotes, or newlines are properly escaped
  /// per RFC 4180.
  static String _exportCsv(List<AuditEntry> entries) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln(
      'id,timestamp,action,severity,actor,source,'
      'targetId,targetType,description',
    );

    // Rows
    for (final entry in entries) {
      buffer.writeln(
        '${_csvEscape(entry.id)},'
        '${_csvEscape(entry.timestamp.toIso8601String())},'
        '${_csvEscape(entry.action.name)},'
        '${_csvEscape(entry.severity.name)},'
        '${_csvEscape(entry.actor)},'
        '${_csvEscape(entry.source)},'
        '${_csvEscape(entry.targetId ?? '')},'
        '${_csvEscape(entry.targetType ?? '')},'
        '${_csvEscape(entry.description ?? '')}',
      );
    }

    return buffer.toString();
  }

  /// Export as newline-delimited JSON (JSONL).
  static String _exportJsonLines(List<AuditEntry> entries) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer.writeln(jsonEncode(entry.toJson()));
    }
    return buffer.toString();
  }

  /// Escape a field value for CSV per RFC 4180.
  ///
  /// Wraps in quotes if the value contains commas, double-quotes,
  /// or newlines. Escapes internal quotes by doubling them.
  static String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
