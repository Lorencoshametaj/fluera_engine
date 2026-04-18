import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/reflow/text_label_picker.dart';

void main() {
  group('TextLabelPicker.tokenize', () {
    test('strips stopwords, numerics, and short tokens', () {
      final tokens = TextLabelPicker.tokenize(
        'La fotosintesi è un processo 2024 di conversione',
      );
      expect(tokens, equals(['fotosintesi', 'processo', 'conversione']));
    });

    test('preserves accented characters', () {
      final tokens = TextLabelPicker.tokenize('caffè perché già');
      // 'è' alone would be <3 chars; 'caffè', 'perché', 'già' kept
      expect(tokens, containsAll(['caffè', 'perché']));
    });

    test('empty text returns empty list', () {
      expect(TextLabelPicker.tokenize(''), isEmpty);
    });

    test('custom stopwords override defaults', () {
      final tokens = TextLabelPicker.tokenize(
        'custom filtered kept',
        stopwords: {'filtered'},
      );
      expect(tokens, contains('kept'));
      expect(tokens, contains('custom'));
      expect(tokens, isNot(contains('filtered')));
    });
  });

  group('TextLabelPicker.pickFromSingle', () {
    test('returns title-cased first significant word joined up to maxWords',
        () {
      final label = TextLabelPicker.pickFromSingle(
        'La definizione di entropia è un concetto',
        maxWords: 2,
      );
      // First two significant: definizione, entropia
      expect(label.toLowerCase().startsWith('definizione'), isTrue);
    });

    test('filters out "la definizione di" prefix via stopword removal', () {
      // This is the historical drift bug: monument was "LA DEFINIZIONE DI"
      final label =
          TextLabelPicker.pickFromSingle('La definizione di entropia');
      expect(label.toLowerCase(), isNot(contains('la ')));
      expect(label.toLowerCase(), isNot(contains(' di ')));
      expect(label.toLowerCase(), contains('entropia'));
    });

    test('truncates with ellipsis when exceeding maxChars', () {
      final label = TextLabelPicker.pickFromSingle(
        'antidisestablishmentarianism',
        maxChars: 10,
      );
      expect(label.length, lessThanOrEqualTo(10));
      expect(label.endsWith('…'), isTrue);
    });

    test('empty input → empty output', () {
      expect(TextLabelPicker.pickFromSingle(''), isEmpty);
      expect(TextLabelPicker.pickFromSingle('   '), isEmpty);
    });

    test('all-stopwords input → empty output', () {
      expect(
        TextLabelPicker.pickFromSingle('la il di a e o un'),
        isEmpty,
      );
    });

    test('LaTeX structural macros are filtered — label surfaces content', () {
      // Simulates MyScript text-mode reading a student's math: the raw
      // text contains \begin{aligned}...\end{aligned} wrappers that the
      // tokenizer collapses to "beginaligned"/"endaligned". Those MUST
      // be filtered so the surfaced label is the subject, not markup.
      final label = TextLabelPicker.pickFromSingle(
        '\\begin{aligned} derivata = 2x \\end{aligned}',
      );
      expect(label.toLowerCase(), isNot(contains('beginaligned')));
      expect(label.toLowerCase(), isNot(contains('endaligned')));
      expect(label.toLowerCase(), contains('derivata'));
    });

    test('cdot / mathrm markup filtered, noun kept', () {
      final label = TextLabelPicker.pickFromSingle(
        'integrale \\cdot \\mathrm{const}',
      );
      expect(label.toLowerCase(), contains('integrale'));
      expect(label.toLowerCase(), isNot(contains('cdot')));
      expect(label.toLowerCase(), isNot(contains('mathrm')));
    });

    test('Greek-letter commands are NOT filtered (pedagogical content)', () {
      // "Alpha particles", "Beta decay" are legitimate labels in physics.
      // The LaTeX stopword set intentionally excludes Greek command names.
      final label = TextLabelPicker.pickFromSingle('alpha particelle');
      expect(label.toLowerCase(), contains('alpha'));
    });
  });

  group('TextLabelPicker.pickFromMany', () {
    test('picks highest-frequency token across blobs', () {
      final label = TextLabelPicker.pickFromMany([
        'fisica quantistica',
        'fisica newton',
        'fisica relatività',
      ]);
      expect(label.toLowerCase(), 'fisica');
    });

    test('tie-broken by insertion order (deterministic)', () {
      final a = TextLabelPicker.pickFromMany(['alpha beta', 'alpha beta']);
      final b = TextLabelPicker.pickFromMany(['alpha beta', 'alpha beta']);
      expect(a, b, reason: 'deterministic output');
      expect(a.toLowerCase(), 'alpha');
    });

    test('empty input → empty output', () {
      expect(TextLabelPicker.pickFromMany([]), isEmpty);
      expect(TextLabelPicker.pickFromMany(['', '']), isEmpty);
    });

    test('custom stopwords override defaults', () {
      final label = TextLabelPicker.pickFromMany(
        ['domain term', 'domain term', 'domain term'],
        stopwords: {'term'},
      );
      expect(label.toLowerCase(), 'domain');
    });
  });
}
