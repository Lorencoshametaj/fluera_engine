// ============================================================================
// 🖋️ EXAM STROKE STORAGE — Persistence layer tests.
//
// Covers the contract `MiniCanvasScratchpad` + `ExamReviewScreen` rely on:
// roundtrip fidelity, atomic write (`.tmp` → rename), `.bak` fallback,
// per-session listing, and clean delete. The storage runs against a real
// temp directory wired through path_provider mocks.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/overlays/components/exam_stroke_storage.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

ProStroke _makeStroke({
  required String id,
  int pointCount = 5,
  Color color = const Color(0xFF00FFCC),
}) {
  return ProStroke(
    id: id,
    points: List.generate(
      pointCount,
      (i) => ProDrawingPoint(
        position: Offset(i * 4.0, i * 3.0),
        pressure: 0.7 + (i * 0.05),
        timestamp: 1700000000000 + i,
      ),
    ),
    color: color,
    baseWidth: 2.5,
    penType: ProPenType.ballpoint,
    createdAt: DateTime.utc(2026, 5, 8, 12, 0),
  );
}

/// Wires path_provider to a disposable temp directory so the storage's
/// `getApplicationDocumentsDirectory()` resolves to a sandbox.
Directory _installTempPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('fluera_strokes_test_');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getTemporaryDirectory':
        return tempDir.path;
    }
    return null;
  });
  return tempDir;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = _installTempPathProvider();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ExamStrokeStorage — roundtrip', () {
    test('save → load returns equivalent strokes', () async {
      final original = [
        _makeStroke(id: 's1', pointCount: 4),
        _makeStroke(id: 's2', pointCount: 7, color: const Color(0xFFFFAB40)),
      ];

      await ExamStrokeStorage.save('sess1__q1__answer', original);
      final loaded = await ExamStrokeStorage.load('sess1__q1__answer');

      expect(loaded, isNotNull);
      expect(loaded!.length, 2);
      expect(loaded[0].id, 's1');
      expect(loaded[1].id, 's2');
      expect(loaded[0].points.length, 4);
      expect(loaded[1].points.length, 7);
      expect(loaded[1].color.toARGB32(), const Color(0xFFFFAB40).toARGB32());
    });

    test('load returns null when no file exists', () async {
      final loaded = await ExamStrokeStorage.load('sess_missing__qX__answer');
      expect(loaded, isNull);
    });

    test('save with empty list deletes any prior file', () async {
      await ExamStrokeStorage.save(
        'sess1__q1__answer',
        [_makeStroke(id: 's1')],
      );
      // Sanity: file exists.
      var keys = await ExamStrokeStorage.listKeysForSession('sess1');
      expect(keys, contains('sess1__q1__answer'));

      // Replace with empty → cleanup.
      await ExamStrokeStorage.save('sess1__q1__answer', const []);
      final loaded = await ExamStrokeStorage.load('sess1__q1__answer');
      expect(loaded, isNull);
      keys = await ExamStrokeStorage.listKeysForSession('sess1');
      expect(keys, isEmpty);
    });
  });

  group('ExamStrokeStorage — atomic write', () {
    test('Writes happen via rename — never a stray .tmp', () async {
      await ExamStrokeStorage.save(
        'sess1__q1__answer',
        [_makeStroke(id: 's1')],
      );
      // Locate the storage dir.
      final dir = Directory('${tempDir.path}/fluera_exam_strokes');
      expect(dir.existsSync(), isTrue);
      final entries = dir.listSync();
      // Must have exactly one .json file. No leftover .tmp.
      final jsons = entries.whereType<File>().where((f) => f.path.endsWith('.json')).toList();
      final tmps = entries.whereType<File>().where((f) => f.path.endsWith('.tmp')).toList();
      expect(jsons.length, 1);
      expect(tmps, isEmpty);
    });

    test('Second save promotes the previous canonical to .bak', () async {
      // First save — only canonical exists.
      await ExamStrokeStorage.save(
        'sess1__q1__answer',
        [_makeStroke(id: 'first', pointCount: 3)],
      );
      // Second save — previous → .bak, new → canonical.
      await ExamStrokeStorage.save(
        'sess1__q1__answer',
        [_makeStroke(id: 'second', pointCount: 9)],
      );

      final dir = Directory('${tempDir.path}/fluera_exam_strokes');
      final files = dir.listSync().whereType<File>().toList();
      final hasBak = files.any((f) => f.path.endsWith('.json.bak'));
      final hasJson = files.any((f) =>
          f.path.endsWith('.json') && !f.path.endsWith('.json.bak'));
      expect(hasBak, isTrue, reason: 'previous canonical must be retained as .bak');
      expect(hasJson, isTrue);

      // Canonical reflects the second save.
      final loaded = await ExamStrokeStorage.load('sess1__q1__answer');
      expect(loaded!.first.id, 'second');
      expect(loaded.first.points.length, 9);
    });
  });

  group('ExamStrokeStorage — .bak fallback on corruption', () {
    test('Corrupt canonical → returns strokes from .bak', () async {
      final key = 'sess1__q1__answer';
      // Seed a valid .bak directly.
      final docs = Directory('${tempDir.path}/fluera_exam_strokes');
      docs.createSync(recursive: true);
      // The sanitized filename for `sess1__q1__answer` keeps underscores
      // and dashes — the prefix replacement only kills disallowed chars.
      final canonical = File('${docs.path}/sess1__q1__answer.json');
      final bak = File('${docs.path}/sess1__q1__answer.json.bak');

      // Corrupt canonical.
      canonical.writeAsStringSync('{not valid json[');

      // Valid backup with a sentinel stroke.
      final goodStroke = _makeStroke(id: 'recovered', pointCount: 6);
      bak.writeAsStringSync(jsonEncode([goodStroke.toJson()]));

      final loaded = await ExamStrokeStorage.load(key);
      expect(loaded, isNotNull);
      expect(loaded!.first.id, 'recovered');
      expect(loaded.first.points.length, 6);
    });

    test('Both files corrupt → null (no exception bubbles up)', () async {
      final key = 'sess1__q1__answer';
      final docs = Directory('${tempDir.path}/fluera_exam_strokes');
      docs.createSync(recursive: true);
      File('${docs.path}/sess1__q1__answer.json')
          .writeAsStringSync('garbage[');
      File('${docs.path}/sess1__q1__answer.json.bak')
          .writeAsStringSync('also garbage');

      final loaded = await ExamStrokeStorage.load(key);
      expect(loaded, isNull);
    });

    test('Empty file is treated as "no data" (returns null, no crash)', () async {
      final key = 'sess1__q1__answer';
      final docs = Directory('${tempDir.path}/fluera_exam_strokes');
      docs.createSync(recursive: true);
      File('${docs.path}/sess1__q1__answer.json').writeAsStringSync('');
      final loaded = await ExamStrokeStorage.load(key);
      expect(loaded, isNull);
    });
  });

  group('ExamStrokeStorage — listKeysForSession', () {
    test('Returns only keys belonging to the given session', () async {
      await ExamStrokeStorage.save('sessA__q1__answer', [_makeStroke(id: 'a1')]);
      await ExamStrokeStorage.save('sessA__q2__answer', [_makeStroke(id: 'a2')]);
      await ExamStrokeStorage.save(
        'sessA__q2__elaboration',
        [_makeStroke(id: 'a2e')],
      );
      await ExamStrokeStorage.save('sessB__q1__answer', [_makeStroke(id: 'b1')]);

      final aKeys = await ExamStrokeStorage.listKeysForSession('sessA');
      expect(aKeys, hasLength(3));
      expect(
        aKeys.toSet(),
        {'sessA__q1__answer', 'sessA__q2__answer', 'sessA__q2__elaboration'},
      );

      final bKeys = await ExamStrokeStorage.listKeysForSession('sessB');
      expect(bKeys, ['sessB__q1__answer']);
    });

    test('Empty when nothing is persisted for the session', () async {
      final keys = await ExamStrokeStorage.listKeysForSession('nope');
      expect(keys, isEmpty);
    });

    test('Excludes .bak shadow files from the listing', () async {
      // Two saves on the same key creates a .bak — listing must not double-count.
      await ExamStrokeStorage.save('sessA__q1__answer', [_makeStroke(id: 'v1')]);
      await ExamStrokeStorage.save('sessA__q1__answer', [_makeStroke(id: 'v2')]);

      final keys = await ExamStrokeStorage.listKeysForSession('sessA');
      expect(keys, ['sessA__q1__answer']);
    });
  });

  group('ExamStrokeStorage — delete', () {
    test('Removes both canonical + .bak shadow', () async {
      // Two saves to create both files.
      await ExamStrokeStorage.save('sessA__q1__answer', [_makeStroke(id: 'a1')]);
      await ExamStrokeStorage.save('sessA__q1__answer', [_makeStroke(id: 'a2')]);

      final dir = Directory('${tempDir.path}/fluera_exam_strokes');
      expect(
        dir.listSync().whereType<File>().any((f) => f.path.endsWith('.bak')),
        isTrue,
        reason: 'precondition: .bak should exist after second save',
      );

      await ExamStrokeStorage.delete('sessA__q1__answer');

      final remaining = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.contains('sessA__q1__answer'))
          .toList();
      expect(remaining, isEmpty);
    });

    test('Silent no-op when the key was never saved', () async {
      // Should not throw.
      await ExamStrokeStorage.delete('does_not_exist__q__answer');
    });
  });

  group('ExamStrokeStorage — sanitisation', () {
    test('Disallowed characters in key are replaced + still loadable', () async {
      // session id with slashes/colons (a UUID-like string with junk).
      final dirtyKey = 'sess/1:weird??__q1__answer';
      await ExamStrokeStorage.save(dirtyKey, [_makeStroke(id: 'x')]);

      // listKeysForSession sanitises the prefix — must still find it.
      final keys = await ExamStrokeStorage.listKeysForSession('sess/1:weird??');
      expect(keys, hasLength(1));

      // Loading via the dirty key must round-trip.
      final loaded = await ExamStrokeStorage.load(dirtyKey);
      expect(loaded, isNotNull);
      expect(loaded!.first.id, 'x');
    });
  });
}
