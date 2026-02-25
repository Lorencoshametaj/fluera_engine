import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/export/latex_file_exporter.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/latex_node.dart';

import '../helpers/test_helpers.dart';

void main() {
  late LatexFileExporter exporter;

  setUp(() {
    exporter = LatexFileExporter();
  });

  tearDown(() {
    exporter.dispose();
  });

  // ===========================================================================
  // Empty scene graph
  // ===========================================================================

  group('empty scene graph', () {
    test('exports document with no-content comment', () {
      final sg = SceneGraph();
      final doc = exporter.exportDocument(sg);

      expect(doc, contains('\\documentclass'));
      expect(doc, contains('\\begin{document}'));
      expect(doc, contains('\\end{document}'));
      expect(doc, contains('No LaTeX content'));
    });
  });

  // ===========================================================================
  // Document structure
  // ===========================================================================

  group('document structure', () {
    test('includes documentclass and document environment', () {
      final sg = SceneGraph();
      final doc = exporter.exportDocument(sg);

      expect(doc, contains('\\documentclass'));
      expect(doc, contains('\\begin{document}'));
      expect(doc, contains('\\end{document}'));
    });

    test('uses custom options', () {
      final sg = SceneGraph();
      final doc = exporter.exportDocument(
        sg,
        options: const TexExportOptions(
          documentClass: 'report',
          fontSize: '14pt',
          title: 'My Report',
          author: 'Test Author',
          date: '2024-01-01',
        ),
      );

      expect(doc, contains('\\documentclass[14pt]{report}'));
      expect(doc, contains('\\title{My Report}'));
      expect(doc, contains('\\author{Test Author}'));
      expect(doc, contains('\\date{2024-01-01}'));
      expect(doc, contains('\\maketitle'));
    });

    test('includes \\today when no date specified', () {
      final sg = SceneGraph();
      final doc = exporter.exportDocument(
        sg,
        options: const TexExportOptions(),
      );
      expect(doc, contains('\\date{\\today}'));
    });
  });

  // ===========================================================================
  // Package detection
  // ===========================================================================

  group('package detection', () {
    test('always includes inputenc and fontenc', () {
      final sg = SceneGraph();
      final doc = exporter.exportDocument(sg);
      expect(doc, contains('inputenc'));
      expect(doc, contains('fontenc'));
    });

    test('extra packages are included', () {
      final sg = SceneGraph();
      final doc = exporter.exportDocument(
        sg,
        options: const TexExportOptions(
          extraPackages: ['geometry', 'graphicx'],
        ),
      );
      expect(doc, contains('geometry'));
      expect(doc, contains('graphicx'));
    });
  });

  // ===========================================================================
  // TexExportOptions
  // ===========================================================================

  group('TexExportOptions', () {
    test('defaults are reasonable', () {
      const opts = TexExportOptions();
      expect(opts.documentClass, 'article');
      expect(opts.fontSize, '12pt');
      expect(opts.title, isNull);
      expect(opts.author, isNull);
      expect(opts.addComments, true);
      expect(opts.extraPackages, isEmpty);
    });
  });

  // ===========================================================================
  // Dispose
  // ===========================================================================

  group('dispose', () {
    test('dispose can be called multiple times safely', () {
      exporter.dispose();
      exporter.dispose(); // Should not throw
    });
  });
}
