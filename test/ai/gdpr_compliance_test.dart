// ============================================================================
// 🧪 UNIT TESTS — GDPR Compliance Layer (A16)
//
// Consent Manager (Art. 7), Data Deletion (Art. 17),
// User Data Export (Art. 20), LLM Anonymizer (Art. 25)
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/gdpr_consent_manager.dart';
import 'package:fluera_engine/src/canvas/ai/data_deletion_service.dart';
import 'package:fluera_engine/src/canvas/ai/user_data_export_service.dart';
import 'package:fluera_engine/src/canvas/ai/llm_payload_anonymizer.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // CONSENT MANAGER (Art. 7)
  // ═══════════════════════════════════════════════════════════════════════════

  group('GdprConsentManager', () {
    late GdprConsentManager mgr;

    setUp(() => mgr = GdprConsentManager());
    tearDown(() => mgr.dispose());

    test('all consents default to false (opt-in)', () {
      for (final cat in ConsentCategory.values) {
        expect(mgr.isGranted(cat), isFalse,
            reason: '${cat.name} should default to false');
      }
    });

    test('grant sets consent to true', () {
      mgr.grant(ConsentCategory.analytics);
      expect(mgr.isGranted(ConsentCategory.analytics), isTrue);
    });

    test('revoke sets consent to false', () {
      mgr.grant(ConsentCategory.aiProcessing);
      mgr.revoke(ConsentCategory.aiProcessing);
      expect(mgr.isGranted(ConsentCategory.aiProcessing), isFalse);
    });

    test('revokeAll revokes everything', () {
      for (final cat in ConsentCategory.values) {
        mgr.grant(cat);
      }
      mgr.revokeAll();
      for (final cat in ConsentCategory.values) {
        expect(mgr.isGranted(cat), isFalse);
      }
    });

    test('areAllGranted checks multiple categories', () {
      mgr.grant(ConsentCategory.analytics);
      mgr.grant(ConsentCategory.crashReporting);
      expect(
        mgr.areAllGranted([
          ConsentCategory.analytics,
          ConsentCategory.crashReporting,
        ]),
        isTrue,
      );
      expect(
        mgr.areAllGranted([
          ConsentCategory.analytics,
          ConsentCategory.aiProcessing,
        ]),
        isFalse,
      );
    });

    test('consent changes are timestamped', () {
      mgr.grant(ConsentCategory.analytics);
      final record = mgr.getRecord(ConsentCategory.analytics);
      expect(record, isNotNull);
      expect(record!.granted, isTrue);
      expect(record.policyVersion, '1.0.0');
      expect(
        record.timestamp.difference(DateTime.now()).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('history records all changes', () {
      mgr.grant(ConsentCategory.analytics);
      mgr.revoke(ConsentCategory.analytics);
      mgr.grant(ConsentCategory.aiProcessing);
      expect(mgr.history.length, 3);
      expect(mgr.history[0].granted, isTrue);
      expect(mgr.history[1].granted, isFalse);
      expect(mgr.history[2].category, ConsentCategory.aiProcessing);
    });

    test('hasDecidedAll requires all categories', () {
      expect(mgr.hasDecidedAll, isFalse);
      for (final cat in ConsentCategory.values) {
        mgr.grant(cat);
      }
      expect(mgr.hasDecidedAll, isTrue);
    });

    test('serialization round-trip', () {
      mgr.grant(ConsentCategory.analytics);
      mgr.grant(ConsentCategory.aiProcessing);
      mgr.revoke(ConsentCategory.aiProcessing);

      final json = mgr.toJson();
      final restored = GdprConsentManager.fromJson(json);

      expect(restored.isGranted(ConsentCategory.analytics), isTrue);
      expect(restored.isGranted(ConsentCategory.aiProcessing), isFalse);
      expect(restored.history.length, 3);
      restored.dispose();
    });

    test('isConsentStale detects outdated policy version', () {
      mgr.grant(ConsentCategory.analytics);
      expect(mgr.isConsentStale(ConsentCategory.analytics), isFalse);

      // Simulate policy upgrade
      final upgraded = GdprConsentManager(
        policyVersion: '2.0.0',
        initialConsents: {
          ConsentCategory.analytics: mgr.getRecord(ConsentCategory.analytics)!,
        },
      );

      // Consent was granted under 1.0.0, but policy is now 2.0.0
      expect(upgraded.isConsentStale(ConsentCategory.analytics), isTrue);
      expect(upgraded.hasStaleConsents, isTrue);
      upgraded.dispose();
    });

    test('isConsentStale returns false for revoked consent', () {
      mgr.revoke(ConsentCategory.analytics);
      expect(mgr.isConsentStale(ConsentCategory.analytics), isFalse);
    });

    test('isConsentStale returns false for never-set consent', () {
      expect(mgr.isConsentStale(ConsentCategory.cloudSync), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA DELETION (Art. 17)
  // ═══════════════════════════════════════════════════════════════════════════

  group('DataDeletionService', () {
    late DataDeletionService service;

    setUp(() => service = DataDeletionService());
    tearDown(() => service.dispose());

    test('not deleting initially', () {
      expect(service.isDeleting, isFalse);
      expect(service.lastRequest, isNull);
    });

    test('deletion without handlers completes successfully', () async {
      final request = await service.requestFullDeletion();
      expect(request.overallStatus, DeletionStatus.completed);
      expect(service.lastRequest, isNotNull);
    });

    test('deletion with handler executes handler', () async {
      service.registerHandler(DeletionCategory.inkData, (_) async {
        return DeletionStepResult(
          category: DeletionCategory.inkData,
          status: DeletionStatus.completed,
          itemsDeleted: 42,
        );
      });

      final request = await service.requestFullDeletion();
      expect(request.results[DeletionCategory.inkData]!.itemsDeleted, 42);
      expect(request.totalItemsDeleted, 42);
    });

    test('failed handler does not block others', () async {
      service.registerHandler(DeletionCategory.inkData, (_) async {
        throw Exception('DB error');
      });
      service.registerHandler(DeletionCategory.srsData, (_) async {
        return DeletionStepResult(
          category: DeletionCategory.srsData,
          status: DeletionStatus.completed,
          itemsDeleted: 10,
        );
      });

      final request = await service.requestFullDeletion();
      expect(
        request.results[DeletionCategory.inkData]!.status,
        DeletionStatus.failed,
      );
      expect(
        request.results[DeletionCategory.srsData]!.status,
        DeletionStatus.completed,
      );
      expect(request.overallStatus, DeletionStatus.failed);
    });

    test('deletion request has audit-worthy JSON', () async {
      final request = await service.requestFullDeletion(reason: 'Test');
      final json = request.toJson();
      expect(json['requestId'], startsWith('del_'));
      expect(json['reason'], 'Test');
      expect(json['overallStatus'], 'completed');
    });

    test('ordered pipeline has 10 categories', () {
      expect(DataDeletionService.orderedPipeline.length, 10);
      // Cached data first, preferences last.
      expect(
        DataDeletionService.orderedPipeline.first,
        DeletionCategory.cachedAiData,
      );
      expect(
        DataDeletionService.orderedPipeline.last,
        DeletionCategory.preferences,
      );
    });

    test('request history is preserved', () async {
      await service.requestDeletion(
        categories: {DeletionCategory.telemetry},
        reason: 'First',
      );
      await service.requestDeletion(
        categories: {DeletionCategory.inkData},
        reason: 'Second',
      );
      expect(service.requestHistory.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // USER DATA EXPORT (Art. 20)
  // ═══════════════════════════════════════════════════════════════════════════

  group('UserDataExportService', () {
    late UserDataExportService service;

    setUp(() => service = UserDataExportService());
    tearDown(() => service.dispose());

    test('idle initially', () {
      expect(service.status, ExportStatus.idle);
      expect(service.isExporting, isFalse);
      expect(service.progress, 0.0);
    });

    test('export without gatherers produces empty manifest', () async {
      final manifest = await service.exportAll();
      expect(manifest.sections, isEmpty);
      expect(manifest.schemaVersion, kExportSchemaVersion);
      expect(service.status, ExportStatus.completed);
    });

    test('export with gatherers collects all sections', () async {
      service.registerGatherer('canvases', (_) async {
        return const ExportSection(
          name: 'canvases',
          itemCount: 5,
          sizeBytes: 1024,
        );
      });
      service.registerGatherer('srs_data', (_) async {
        return const ExportSection(
          name: 'srs_data',
          itemCount: 100,
          sizeBytes: 2048,
        );
      });

      final manifest = await service.exportAll(
        appVersion: '2.0.0',
        platform: 'ios',
      );

      expect(manifest.sections.length, 2);
      expect(manifest.totalItemCount, 105);
      expect(manifest.totalSizeBytes, 3072);
      expect(manifest.appVersion, '2.0.0');
      expect(manifest.platform, 'ios');
    });

    test('failed gatherer recorded with error', () async {
      service.registerGatherer('broken', (_) async {
        throw Exception('IO error');
      });

      final manifest = await service.exportAll();
      expect(manifest.sections.length, 1);
      expect(manifest.sections.first.success, isFalse);
      expect(manifest.sections.first.error, contains('IO error'));
    });

    test('manifest serialization round-trip', () {
      final manifest = ExportManifest(
        appVersion: '1.5.0',
        platform: 'android',
        sections: [
          const ExportSection(name: 'test', itemCount: 10, sizeBytes: 500),
        ],
      );

      final json = manifest.toJson();
      final restored = ExportManifest.fromJson(json);

      expect(restored.appVersion, '1.5.0');
      expect(restored.platform, 'android');
      expect(restored.sections.length, 1);
      expect(restored.totalItemCount, 10);
    });

    test('registeredSections lists all', () {
      service.registerGatherer('a', (_) async =>
          const ExportSection(name: 'a', itemCount: 0));
      service.registerGatherer('b', (_) async =>
          const ExportSection(name: 'b', itemCount: 0));
      expect(service.registeredSections, ['a', 'b']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LLM PAYLOAD ANONYMIZER (Art. 25)
  // ═══════════════════════════════════════════════════════════════════════════

  group('LlmPayloadAnonymizer', () {
    test('strips email addresses', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'Contatta mario.rossi@gmail.com per info',
      );
      expect(result.text, contains('[REDACTED]'));
      expect(result.text, isNot(contains('mario.rossi@gmail.com')));
      expect(result.hadPii, isTrue);
    });

    test('strips Italian phone numbers', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'Chiama il 333 123 4567 per prenotare',
      );
      expect(result.text, isNot(contains('333 123 4567')));
    });

    test('strips codice fiscale', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'CF: RSSMRA85M10H501Z',
      );
      expect(result.text, isNot(contains('RSSMRA85M10H501Z')));
    });

    test('strips titled names (Prof., Dott.)', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'Il Prof. Bianchi ha spiegato la fotosintesi',
      );
      expect(result.text, isNot(contains('Bianchi')));
      expect(result.text, contains('ha spiegato la fotosintesi'));
    });

    test('strips Dottoressa names', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'La Dottssa Verdi ha prescritto',
      );
      expect(result.text, isNot(contains('Verdi')));
    });

    test('strips street addresses', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'Indirizzo: Via Roma 42',
      );
      expect(result.text, isNot(contains('Via Roma 42')));
    });

    test('strips matricola numbers', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'Matricola: 12345678',
      );
      expect(result.text, isNot(contains('12345678')));
    });

    test('strips date of birth', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'Nato il 15/03/1995 a Milano',
      );
      expect(result.text, isNot(contains('15/03/1995')));
    });

    test('empty text returns empty', () {
      final result = LlmPayloadAnonymizer.anonymize('');
      expect(result.text, '');
      expect(result.redactionCount, 0);
      expect(result.hadPii, isFalse);
    });

    test('clean text passes through unchanged', () {
      const clean = 'La fotosintesi clorofilliana produce ossigeno';
      final result = LlmPayloadAnonymizer.anonymize(clean);
      expect(result.text, clean);
      expect(result.hadPii, isFalse);
    });

    test('containsPii detects PII without modifying', () {
      expect(LlmPayloadAnonymizer.containsPii('test@email.com'), isTrue);
      expect(LlmPayloadAnonymizer.containsPii('nessun dato'), isFalse);
    });

    test('multiple PII in same text all stripped', () {
      final result = LlmPayloadAnonymizer.anonymize(
        'Prof. Rossi (test@uni.it) tel 333 456 7890',
      );
      expect(result.redactionCount, greaterThanOrEqualTo(2));
      expect(result.text, isNot(contains('Rossi')));
      expect(result.text, isNot(contains('test@uni.it')));
    });
  });
}
