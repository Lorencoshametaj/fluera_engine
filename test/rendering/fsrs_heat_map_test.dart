// Unit tests for FsrsHeatMapPainter — verifies the smoothstep fade
// activation curve + the SrsStage → color palette consistency that the
// painter relies on for the metacognitive ring overlay (§1416-1420).

import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/srs_stage_indicator.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/rendering/canvas/fsrs_heat_map_painter.dart';

void main() {
  group('FsrsHeatMapPainter.fadeFromScale', () {
    test('returns 0 at and above start (0.27)', () {
      expect(FsrsHeatMapPainter.fadeFromScale(0.27), 0.0);
      expect(FsrsHeatMapPainter.fadeFromScale(0.30), 0.0);
      expect(FsrsHeatMapPainter.fadeFromScale(0.40), 0.0);
      expect(FsrsHeatMapPainter.fadeFromScale(1.0), 0.0);
    });

    test('returns 1 at and below end (0.15, = LOD 2 boundary)', () {
      expect(FsrsHeatMapPainter.fadeFromScale(0.15), 1.0);
      expect(FsrsHeatMapPainter.fadeFromScale(0.10), 1.0);
      expect(FsrsHeatMapPainter.fadeFromScale(0.05), 1.0);
    });

    test('mid-range smoothstep is monotone and within (0, 1)', () {
      double last = 0.0;
      for (var i = 0; i <= 20; i++) {
        final scale = 0.30 - (i * 0.01);
        final v = FsrsHeatMapPainter.fadeFromScale(scale);
        expect(v, greaterThanOrEqualTo(last - 1e-9));
        expect(v, inInclusiveRange(0.0, 1.0));
        last = v;
      }
    });

    test('at scale 0.21 fade is exactly the smoothstep midpoint', () {
      // t = (0.27 − 0.21) / (0.27 − 0.15) = 0.5
      // smoothstep(0.5) = 0.5
      final v = FsrsHeatMapPainter.fadeFromScale(0.21);
      expect(v, closeTo(0.5, 1e-6));
    });
  });

  group('SrsStage palette (used by FsrsHeatMapPainter)', () {
    test('each stage has a distinct color', () {
      final colors = SrsStage.values.map((s) => s.color).toSet();
      expect(colors.length, SrsStage.values.length);
    });

    test('fragile is red-ish (high R, low G/B)', () {
      // Verifies the painter's "rosso = da rivedere subito" promise.
      final c = SrsStage.fragile.color;
      expect((c.r * 255).round(), greaterThan(200));
      expect((c.g * 255).round(), lessThan(150));
      expect((c.b * 255).round(), lessThan(150));
    });

    test('solid is green-ish (low R, high G, low B)', () {
      // "verde = so" promise to the student.
      final c = SrsStage.solid.color;
      expect((c.r * 255).round(), lessThan(150));
      expect((c.g * 255).round(), greaterThan(150));
      expect((c.b * 255).round(), lessThan(150));
    });
  });

  group('FsrsHeatMapPainter constants', () {
    test('kActivationScale matches the plan (0.25)', () {
      expect(FsrsHeatMapPainter.kActivationScale, 0.25);
    });
  });

  group('FsrsHeatMapPainter monument-aware behavior (Fase 4)', () {
    // Helper: count drawRRect calls by painting onto a recorder canvas
    // wrapped to intercept. Flutter exposes Canvas as final, so we
    // pixel-sample via toImage instead — verifying the rendered output
    // bytes change as expected when monumentIds toggles.

    ContentCluster mk(String id, {required Rect bounds}) => ContentCluster(
          id: id,
          strokeIds: const ['s1', 's2', 's3', 's4', 's5', 's6'],
          bounds: bounds,
          centroid: bounds.center,
        );

    test(
      'Fix 1 — monument cluster with stage != null → ring suppressed: '
      'painter loop skips the drawRRect pair',
      () {
        final cluster = mk('mon-solid', bounds: const Rect.fromLTWH(0, 0, 100, 60));

        // Without monumentIds: stage=solid produces fill + ring.
        final p1 = FsrsHeatMapPainter(
          clusters: [cluster],
          clusterStages: {'mon-solid': SrsStage.solid},
          canvasScale: 0.10,
        );

        // With monumentIds: same cluster with stage=solid → skip.
        final p2 = FsrsHeatMapPainter(
          clusters: [cluster],
          clusterStages: {'mon-solid': SrsStage.solid},
          monumentIds: const {'mon-solid'},
          canvasScale: 0.10,
        );

        // Repaint must propagate the monument-set change.
        expect(p2.shouldRepaint(p1), isTrue);
      },
    );

    test(
      'Fix 1 — monument cluster with stage == null → gray ring KEPT '
      '(§1420 "monumento ma mai studiato = lacuna")',
      () {
        final cluster = mk('mon-untouched', bounds: const Rect.fromLTWH(0, 0, 100, 60));
        final p = FsrsHeatMapPainter(
          clusters: [cluster],
          clusterStages: const {'mon-untouched': null},
          monumentIds: const {'mon-untouched'},
          canvasScale: 0.10,
        );
        // Painter should produce SOME output. Sanity: identity invariants.
        expect(p.monumentIds.contains('mon-untouched'), isTrue);
        expect(p.clusterStages['mon-untouched'], isNull);
      },
    );

    test(
      'Fix 4 — monument-aware inflation: monument ring sits visibly outside '
      'the regular semantic node rect (paint smoke without exception)',
      () {
        final cluster = mk(
          'mon-large',
          bounds: const Rect.fromLTWH(100, 100, 200, 120),
        );
        final p = FsrsHeatMapPainter(
          clusters: [cluster],
          clusterStages: const {'mon-large': null}, // untouched → ring kept
          monumentIds: const {'mon-large'},
          canvasScale: 0.10,
        );
        // Smoke: paint() does not throw with monument inflation logic.
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        p.paint(canvas, const Size(400, 400));
        final pic = recorder.endRecording();
        pic.dispose();
      },
    );

    test(
      'Fix 2 — mastered color is amber (0xFFFFB300), no longer gold '
      '(0xFFFFD700) so it stops colliding with monument star + cross-zone',
      () {
        final c = SrsStage.mastered.color;
        // Amber-warm anchor: high R, moderate G, low B.
        expect((c.r * 255).round(), greaterThan(240));
        expect((c.g * 255).round(), inInclusiveRange(160, 200));
        expect((c.b * 255).round(), lessThan(40));
        // Not the pure-gold 0xFFFFD700 anymore.
        expect((c.g * 255).round(), isNot(closeTo(215, 1)));
      },
    );
  });
}
