// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io' show File, ProcessInfo;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fluera_engine/fluera_engine.dart';
import 'package:fluera_engine/src/drawing/utils/stroke_generator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// 🏎️ END-TO-END DEVICE BENCHMARK v3 — REAL STRESS TESTS
///
/// Uses real pointer event simulation → full rendering pipeline:
///   Touch → GestureDetector → InfiniteCanvasController → shouldRepaint
///   → paint() → R-Tree query → viewport culling → GPU rasterization
///
/// Scenarios:
///   1. PAN:  Continuous drag across dense stroke regions
///   2. ZOOM: Pinch zoom in/out (scale change → LOD + tile cache)
///   3. IDLE: Stationary viewport (cache-hit best case)
///
/// Run with: flutter run --profile (from example/)
/// ═══════════════════════════════════════════════════════════════════════════

// ─── Config ────────────────────────────────────────────────────────────────

class _BenchmarkScale {
  final String label;
  final int strokeCount;
  final Size canvasSize;
  final bool paged;
  const _BenchmarkScale(
    this.label,
    this.strokeCount,
    this.canvasSize, {
    this.paged = false,
  });
}

class _ScenarioResult {
  final String scenario;
  final int frames;
  final double p50BuildMs, p90BuildMs, p99BuildMs;
  final double p50RasterMs, p90RasterMs, p99RasterMs;
  final double avgFps;
  final double worstFrameMs;
  final double jankPct;

  _ScenarioResult({
    required this.scenario,
    required this.frames,
    required this.p50BuildMs,
    required this.p90BuildMs,
    required this.p99BuildMs,
    required this.p50RasterMs,
    required this.p90RasterMs,
    required this.p99RasterMs,
    required this.avgFps,
    required this.worstFrameMs,
    required this.jankPct,
  });

  bool get passes120Hz {
    // Build and Raster threads run in PARALLEL — each must be under budget
    return p99BuildMs < 8.33 && p99RasterMs < 8.33;
  }

  bool get passes60Hz {
    return p99BuildMs < 16.67 && p99RasterMs < 16.67;
  }
}

class _ScaleResult {
  final String label;
  final int strokeCount;
  final bool paged;
  final int generateMs;
  final double memoryMB;
  final _ScenarioResult panResult;
  final _ScenarioResult zoomResult;
  final _ScenarioResult idleResult;

  _ScaleResult({
    required this.label,
    required this.strokeCount,
    required this.paged,
    required this.generateMs,
    required this.memoryMB,
    required this.panResult,
    required this.zoomResult,
    required this.idleResult,
  });
}

// ─── Page ──────────────────────────────────────────────────────────────────

class BenchmarkPage extends StatefulWidget {
  final SqliteStorageAdapter? storage;
  const BenchmarkPage({super.key, this.storage});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage>
    with TickerProviderStateMixin {
  bool _running = false;
  bool _done = false;
  String _status = 'Ready to benchmark';
  final List<_ScaleResult> _results = [];

  LayerController? _layerController;
  SqliteStorageAdapter? _benchmarkStorage;
  final GlobalKey _canvasKey = GlobalKey();

  final List<int> _buildTimesUs = [];
  final List<int> _rasterTimesUs = [];

  static const _scales = [
    _BenchmarkScale('1K', 1000, Size(5000, 5000)),
    _BenchmarkScale('10K', 10000, Size(16000, 16000)),
    _BenchmarkScale('100K', 100000, Size(50000, 50000)),
    _BenchmarkScale('1M', 1000000, Size(160000, 160000), paged: true),
  ];

  @override
  void dispose() {
    _layerController?.dispose();
    _benchmarkStorage?.close();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FRAME TIMING
  // ═══════════════════════════════════════════════════════════════════════

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _buildTimesUs.add(t.buildDuration.inMicroseconds);
      _rasterTimesUs.add(t.rasterDuration.inMicroseconds);
    }
  }

  void _startCollecting() {
    _buildTimesUs.clear();
    _rasterTimesUs.clear();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _stopCollecting() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
  }

  double _percentile(List<int> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final idx = ((sorted.length * p).floor()).clamp(0, sorted.length - 1);
    return sorted[idx] / 1000.0;
  }

  _ScenarioResult _collectScenarioResult(String scenario) {
    final buildSorted = List<int>.from(_buildTimesUs)..sort();
    final rasterSorted = List<int>.from(_rasterTimesUs)..sort();
    final n = buildSorted.length;

    // Worst combined frame
    double worstMs = 0;
    int jank = 0;
    for (int i = 0; i < n; i++) {
      final combined =
          buildSorted[i] + (i < rasterSorted.length ? rasterSorted[i] : 0);
      final ms = combined / 1000.0;
      if (ms > worstMs) worstMs = ms;
      if (combined > 8330) jank++; // > 8.33ms = missed 120Hz
    }

    // FPS from median frame time
    final medianBuild = n > 0 ? buildSorted[n ~/ 2] : 8000;
    final medianRaster =
        rasterSorted.isNotEmpty ? rasterSorted[rasterSorted.length ~/ 2] : 8000;
    final medianFrameMs = (medianBuild + medianRaster) / 1000.0;
    final fps = medianFrameMs > 0 ? 1000.0 / medianFrameMs : 0.0;

    return _ScenarioResult(
      scenario: scenario,
      frames: n,
      p50BuildMs: _percentile(buildSorted, 0.5),
      p90BuildMs: _percentile(buildSorted, 0.9),
      p99BuildMs: _percentile(buildSorted, 0.99),
      p50RasterMs: _percentile(rasterSorted, 0.5),
      p90RasterMs: _percentile(rasterSorted, 0.9),
      p99RasterMs: _percentile(rasterSorted, 0.99),
      avgFps: fps,
      worstFrameMs: worstMs,
      jankPct: n > 0 ? jank / n * 100 : 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // POINTER SIMULATION — Real touch events through Flutter gesture pipeline
  // ═══════════════════════════════════════════════════════════════════════

  int _nextPointerId = 100;

  /// Simulate a single-finger drag (pan) across the canvas.
  /// This triggers the FULL rendering pipeline:
  ///   PointerDown → GestureDetector → InfiniteCanvasController.setOffset
  ///   → ChangeNotifier → shouldRepaint=true → paint() → R-Tree + GPU
  Future<void> _simulatePan({
    required Offset startScreen,
    required Offset endScreen,
    int steps = 60,
    Duration stepDelay = const Duration(milliseconds: 16),
  }) async {
    final pointer = _nextPointerId++;
    final dx = (endScreen.dx - startScreen.dx) / steps;
    final dy = (endScreen.dy - startScreen.dy) / steps;

    // Down
    final down = PointerDownEvent(
      pointer: pointer,
      position: startScreen,
      kind: PointerDeviceKind.touch,
    );
    WidgetsBinding.instance.handlePointerEvent(down);
    await Future.delayed(stepDelay);

    // Move
    for (int i = 1; i <= steps; i++) {
      final pos = Offset(startScreen.dx + dx * i, startScreen.dy + dy * i);
      final move = PointerMoveEvent(
        pointer: pointer,
        position: pos,
        delta: Offset(dx, dy),
        kind: PointerDeviceKind.touch,
      );
      WidgetsBinding.instance.handlePointerEvent(move);
      await Future.delayed(stepDelay);
    }

    // Up
    final up = PointerUpEvent(
      pointer: pointer,
      position: endScreen,
      kind: PointerDeviceKind.touch,
    );
    WidgetsBinding.instance.handlePointerEvent(up);
    await Future.delayed(stepDelay);
  }

  /// Simulate a two-finger pinch zoom.
  Future<void> _simulateZoom({
    required Offset center,
    required double startSpread,
    required double endSpread,
    int steps = 40,
    Duration stepDelay = const Duration(milliseconds: 16),
  }) async {
    final p1 = _nextPointerId++;
    final p2 = _nextPointerId++;
    final dSpread = (endSpread - startSpread) / steps;

    // Both fingers down
    WidgetsBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: p1,
        position: Offset(center.dx - startSpread / 2, center.dy),
        kind: PointerDeviceKind.touch,
      ),
    );
    await Future.delayed(const Duration(milliseconds: 5));
    WidgetsBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: p2,
        position: Offset(center.dx + startSpread / 2, center.dy),
        kind: PointerDeviceKind.touch,
      ),
    );
    await Future.delayed(stepDelay);

    // Move both fingers (spread apart or together)
    for (int i = 1; i <= steps; i++) {
      final spread = startSpread + dSpread * i;
      final half = spread / 2;

      WidgetsBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          pointer: p1,
          position: Offset(center.dx - half, center.dy),
          delta: Offset(-dSpread / 2, 0),
          kind: PointerDeviceKind.touch,
        ),
      );
      WidgetsBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          pointer: p2,
          position: Offset(center.dx + half, center.dy),
          delta: Offset(dSpread / 2, 0),
          kind: PointerDeviceKind.touch,
        ),
      );
      await Future.delayed(stepDelay);
    }

    // Both fingers up
    WidgetsBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: p1,
        position: Offset(center.dx - endSpread / 2, center.dy),
        kind: PointerDeviceKind.touch,
      ),
    );
    WidgetsBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: p2,
        position: Offset(center.dx + endSpread / 2, center.dy),
        kind: PointerDeviceKind.touch,
      ),
    );
    await Future.delayed(stepDelay);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DB SEEDING
  // ═══════════════════════════════════════════════════════════════════════

  Future<SqliteStorageAdapter> _seedPagedDb(
    _BenchmarkScale scale,
    String canvasId,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/benchmark_${scale.label}.db';

    final file = File(dbPath);
    if (await file.exists()) await file.delete();

    final adapter = SqliteStorageAdapter(databasePath: dbPath);
    await adapter.initialize();

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(singleInstance: false),
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stroke_pages (
        stroke_id TEXT PRIMARY KEY, canvas_id TEXT NOT NULL,
        layer_id TEXT NOT NULL DEFAULT '', stroke_json TEXT NOT NULL,
        bounds_l REAL NOT NULL, bounds_t REAL NOT NULL,
        bounds_r REAL NOT NULL, bounds_b REAL NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sp_c ON stroke_pages(canvas_id)',
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('canvases', {
      'canvas_id': canvasId,
      'title': 'Bench ${scale.label}',
      'paper_type': 'blank',
      'schema_version': 1,
      'layer_count': 1,
      'stroke_count': scale.strokeCount,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final rng = math.Random(42);
    const batchSize = 10000;
    int gen = 0;
    while (gen < scale.strokeCount) {
      final cnt = math.min(batchSize, scale.strokeCount - gen);
      final batch = db.batch();
      for (int j = 0; j < cnt; j++) {
        final x = rng.nextDouble() * scale.canvasSize.width;
        final y = rng.nextDouble() * scale.canvasSize.height;
        batch.insert('stroke_pages', {
          'stroke_id': 'stroke_${gen + j}',
          'canvas_id': canvasId,
          'layer_id': '',
          'stroke_json': '{}',
          'bounds_l': x,
          'bounds_t': y,
          'bounds_r': x + 50 + rng.nextDouble() * 200,
          'bounds_b': y + 50 + rng.nextDouble() * 150,
        });
      }
      await batch.commit(noResult: true);
      gen += cnt;
      setState(
        () => _status = '${scale.label}: Seeding DB $gen/${scale.strokeCount}',
      );
      await Future.delayed(const Duration(milliseconds: 1));
    }

    await db.close();
    return adapter;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BENCHMARK ENGINE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _runBenchmark() async {
    setState(() {
      _running = true;
      _done = false;
      _results.clear();
    });

    final screenSize = MediaQuery.of(context).size;
    final center = Offset(screenSize.width / 2, screenSize.height / 2);

    for (final scale in _scales) {
      final canvasId = 'benchmark_${scale.label}';
      final genSw = Stopwatch()..start();

      _layerController?.dispose();
      _benchmarkStorage?.close();
      _layerController = LayerController();
      _benchmarkStorage = null;

      if (scale.paged) {
        setState(() => _status = '${scale.label}: Seeding SQLite DB...');
        _benchmarkStorage = await _seedPagedDb(scale, canvasId);
      } else {
        setState(() => _status = '${scale.label}: Generating strokes...');
        await Future.delayed(const Duration(milliseconds: 100));
        _layerController!.enableDeltaTracking = false;
        int generated = 0;
        final batchSize = math.min(5000, scale.strokeCount);
        while (generated < scale.strokeCount) {
          final cnt = math.min(batchSize, scale.strokeCount - generated);
          await _layerController!.addStrokesBatch(
            StrokeGenerator.generateRandomStrokes(
              cnt,
              canvasSize: scale.canvasSize,
              avgPointsPerStroke: 30,
            ),
          );
          generated += cnt;
          setState(
            () =>
                _status = '${scale.label}: Gen $generated/${scale.strokeCount}',
          );
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
      genSw.stop();
      print(
        '📦 ${scale.label}: ${scale.paged ? "Seeded" : "Generated"} '
        '${scale.strokeCount} in ${genSw.elapsedMilliseconds}ms',
      );

      // Mount canvas and wait for initial render
      setState(() => _status = '${scale.label}: Mounting canvas...');
      await Future.delayed(const Duration(seconds: 3));

      // ─── SCENARIO 1: PAN ──────────────────────────────────────────
      setState(() => _status = '${scale.label}: 🖐️ PAN stress test...');
      await Future.delayed(const Duration(milliseconds: 500));
      _startCollecting();

      // 3 rapid pans in different directions
      await _simulatePan(
        startScreen: Offset(center.dx - 100, center.dy),
        endScreen: Offset(center.dx + 200, center.dy),
        steps: 60,
        stepDelay: const Duration(milliseconds: 16),
      );
      await _simulatePan(
        startScreen: Offset(center.dx, center.dy - 100),
        endScreen: Offset(center.dx - 200, center.dy + 200),
        steps: 60,
        stepDelay: const Duration(milliseconds: 16),
      );
      await _simulatePan(
        startScreen: Offset(center.dx + 100, center.dy + 100),
        endScreen: Offset(center.dx - 300, center.dy - 100),
        steps: 60,
        stepDelay: const Duration(milliseconds: 16),
      );

      _stopCollecting();
      final panResult = _collectScenarioResult('PAN');

      // ─── SCENARIO 2: ZOOM ─────────────────────────────────────────
      setState(() => _status = '${scale.label}: 🔍 ZOOM stress test...');
      await Future.delayed(const Duration(milliseconds: 500));
      _startCollecting();

      // Zoom in then zoom out
      await _simulateZoom(
        center: center,
        startSpread: 100,
        endSpread: 400,
        steps: 40,
        stepDelay: const Duration(milliseconds: 16),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      await _simulateZoom(
        center: center,
        startSpread: 400,
        endSpread: 80,
        steps: 40,
        stepDelay: const Duration(milliseconds: 16),
      );

      _stopCollecting();
      final zoomResult = _collectScenarioResult('ZOOM');

      // ─── SCENARIO 3: IDLE ─────────────────────────────────────────
      setState(() => _status = '${scale.label}: 😴 IDLE measurement...');
      await Future.delayed(const Duration(milliseconds: 500));
      _startCollecting();
      await Future.delayed(const Duration(seconds: 3));
      _stopCollecting();
      final idleResult = _collectScenarioResult('IDLE');

      // ─── Collect memory ────────────────────────────────────────────
      double memMB = 0;
      try {
        memMB = ProcessInfo.currentRss / 1024 / 1024;
      } catch (_) {}

      final result = _ScaleResult(
        label: scale.label,
        strokeCount: scale.strokeCount,
        paged: scale.paged,
        generateMs: genSw.elapsedMilliseconds,
        memoryMB: memMB,
        panResult: panResult,
        zoomResult: zoomResult,
        idleResult: idleResult,
      );
      _results.add(result);
      _printResult(result);
    }

    _benchmarkStorage?.close();
    _benchmarkStorage = null;
    _printSummary();
    setState(() {
      _running = false;
      _done = true;
      _status = 'Complete!';
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRINT
  // ═══════════════════════════════════════════════════════════════════════

  void _printResult(_ScaleResult r) {
    print('');
    print('═══════════════════════════════════════════════════');
    print(
      '🏎️ ${r.label} (${r.strokeCount} strokes${r.paged ? ", PAGED" : ""})  Mem: ${r.memoryMB.toStringAsFixed(0)}MB',
    );
    print('═══════════════════════════════════════════════════');
    for (final s in [r.panResult, r.zoomResult, r.idleResult]) {
      final tag60 = s.passes60Hz ? '✅' : '❌';
      final tag120 = s.passes120Hz ? '✅' : '❌';
      print(
        '  ${s.scenario.padRight(5)} │ Build P99=${s.p99BuildMs.toStringAsFixed(2)}ms  '
        'Raster P99=${s.p99RasterMs.toStringAsFixed(2)}ms  '
        'Worst=${s.worstFrameMs.toStringAsFixed(1)}ms  '
        '60Hz:$tag60 120Hz:$tag120',
      );
    }
  }

  void _printSummary() {
    print('');
    print(
      '════════════════════════════════════════════════════════════════════════',
    );
    print('📊 FLUERA ENGINE — STRESS TEST RESULTS');
    print(
      '════════════════════════════════════════════════════════════════════════',
    );
    print(
      'Scale  │ Test │ Build P99│ Raster P99│ Worst  │  Mem  │ 60Hz │120Hz',
    );
    print(
      '───────┼──────┼──────────┼───────────┼────────┼───────┼──────┼──────',
    );
    for (final r in _results) {
      for (final s in [r.panResult, r.zoomResult, r.idleResult]) {
        print(
          '${r.label.padRight(6)} │ '
          '${s.scenario.padRight(4)} │ '
          '${s.p99BuildMs.toStringAsFixed(2).padLeft(6)}ms │ '
          '${s.p99RasterMs.toStringAsFixed(2).padLeft(7)}ms │ '
          '${s.worstFrameMs.toStringAsFixed(1).padLeft(5)}ms │ '
          '${r.memoryMB.toStringAsFixed(0).padLeft(4)}MB │ '
          '${s.passes60Hz ? "  ✅" : "  ❌"} │ '
          '${s.passes120Hz ? "  ✅" : "  ❌"}',
        );
      }
      if (r != _results.last) {
        print(
          '───────┼──────┼──────────┼───────────┼────────┼───────┼──────┼──────',
        );
      }
    }
    print(
      '───────┴──────┴──────────┴───────────┴────────┴───────┴──────┴──────',
    );
    print(
      '60Hz budget: P99 each < 16.67ms │ 120Hz: P99 each < 8.33ms (parallel)',
    );
    print('');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          '🏎️ Stress Test',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!_running)
            TextButton.icon(
              onPressed: _runBenchmark,
              icon: const Icon(Icons.play_arrow, color: Colors.greenAccent),
              label: const Text(
                'RUN',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_running)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.amber,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1C2128),
            child: Text(
              _status,
              style: TextStyle(
                color: _running ? Colors.amber : Colors.white70,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (_layerController != null && _running)
            Expanded(
              child: FlueraCanvasScreen(
                key: _canvasKey,
                config: FlueraCanvasConfig(
                  layerController: _layerController!,
                  storageAdapter: _benchmarkStorage ?? widget.storage,
                ),
              ),
            ),
          if (_done && _results.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildResultsUI(),
              ),
            ),
          if (!_running && !_done)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed, size: 64, color: Colors.white24),
                    SizedBox(height: 16),
                    Text(
                      'Tap RUN to start stress tests',
                      style: TextStyle(color: Colors.white38, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'PAN + ZOOM + IDLE at 1K → 1M strokes\nReal pointer events → full rendering pipeline',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white24, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 STRESS TEST RESULTS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        for (final r in _results) ...[
          _buildScaleCard(r),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildScaleCard(_ScaleResult r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${r.label}  ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${r.strokeCount} strokes',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              if (r.paged) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PAGED',
                    style: TextStyle(
                      color: Colors.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              _statChip(
                'Mem',
                '${r.memoryMB.toStringAsFixed(0)}MB',
                r.memoryMB < 300 ? Colors.cyan : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final s in [r.panResult, r.zoomResult, r.idleResult]) ...[
            _scenarioRow(s),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _scenarioRow(_ScenarioResult s) {
    final icon =
        s.scenario == 'PAN'
            ? '🖐️'
            : s.scenario == 'ZOOM'
            ? '🔍'
            : '😴';
    final color = s.passes120Hz ? Colors.greenAccent : Colors.redAccent;
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            '$icon ${s.scenario}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        _percentileChip('B99', s.p99BuildMs),
        const SizedBox(width: 4),
        _percentileChip('R99', s.p99RasterMs),
        const SizedBox(width: 4),
        _percentileChip('Worst', s.worstFrameMs),
        const Spacer(),
        Text(
          s.passes120Hz ? '✅' : '❌',
          style: TextStyle(color: color, fontSize: 14),
        ),
      ],
    );
  }

  Widget _percentileChip(String label, double ms) {
    final color =
        ms < 4.0
            ? Colors.greenAccent
            : ms < 8.33
            ? Colors.amber
            : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label:${ms.toStringAsFixed(1)}ms',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace'),
      ),
    );
  }
}
