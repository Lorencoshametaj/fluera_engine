import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/models/canvas_layer.dart';
import 'package:fluera_engine/src/history/branching_manager.dart';
import 'package:fluera_engine/src/history/widgets/branch_explorer_sheet.dart';
import 'package:fluera_engine/src/l10n/generated/fluera_localizations.g.dart';
import 'package:fluera_engine/src/services/phase2_service_stubs.dart';
import 'package:fluera_engine/src/time_travel/models/time_travel_session.dart';

/// 🎯 Scope: smoke-test that the localized title renders, which is the
/// fastest regression catcher for the 2026-05-15 rebrand
/// ("Branch Explorer" → "Alternative esplorate").
///
/// Deferred (require full path_provider mock + EngineScope.reset +
/// extended async I/O ticks): row/action layout assertions, merge UX
/// gating. Backend behavior is already covered by branching_manager_test.dart
/// and version_history_test.dart (17 tests verde).

class _TestStorage implements FlueraTimeTravelStorage {
  final String basePath;
  _TestStorage(this.basePath);

  @override
  Future<String> getTimeTravelPathForCanvas(String canvasId) async =>
      '$basePath/$canvasId';

  @override
  Future<List<TimeTravelSession>> loadSessionIndex(
    String canvasId, {
    String? branchId,
  }) async => [];

  @override
  Future<List<TimeTravelEvent>> loadSessionEvents(
    TimeTravelSession session, {
    String? branchId,
  }) async => [];

  @override
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
    String canvasId,
    int targetSessionIndex, {
    String? branchId,
  }) async => null;
}

CanvasLayer _layer(String id) => CanvasLayer(
      id: id,
      name: 'L$id',
      isVisible: true,
      opacity: 1.0,
      strokes: [],
    );

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
    localizationsDelegates: FlueraLocalizations.localizationsDelegates,
    supportedLocales: FlueraLocalizations.supportedLocales,
    locale: const Locale('it'),
  );
}

void main() {
  late Directory tempDir;
  late BranchingManager manager;

  const canvasId = 'cv_test';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluera_branch_widget_');
    manager = BranchingManager(
      storage: _TestStorage(tempDir.path),
      cloudSync: BranchCloudSyncService.instance,
    );
    await manager.ensureMainBranch(
      canvasId: canvasId,
      createdBy: 'tester',
      snapshotLayers: [_layer('a')],
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
      'IT: header title is "Alternative esplorate" (not legacy "Branch Explorer")',
      (tester) async {
    await tester.pumpWidget(_harness(BranchExplorerSheet(
      canvasId: canvasId,
      branchingManager: manager,
      onSwitchBranch: (_) {},
    )));
    // First frame paints header before async _loadBranches completes — no
    // need to drain I/O for this smoke check.
    await tester.pump();

    expect(find.text('Alternative esplorate'), findsOneWidget);
    expect(find.text('Branch Explorer'), findsNothing);
  });
}
