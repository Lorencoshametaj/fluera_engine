import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/latex_table_parser.dart';

void main() {
  late LatexTableParser parser;

  setUp(() => parser = LatexTableParser());

  group('LatexTableParser — tabular', () {
    test('parses basic tabular', () {
      const latex = r'''
\begin{tabular}{lcr}
\hline
Name & Age & Score \\
Alice & 30 & 95 \\
Bob & 25 & 88 \\
\hline
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.environment, 'tabular');
      expect(result.alignment, 'lcr');
      expect(result.allRows.length, 3); // 3 rows
      expect(result.allRows[0], ['Name', 'Age', 'Score']);
      expect(result.allRows[1], ['Alice', '30', '95']);
      expect(result.allRows[2], ['Bob', '25', '88']);
    });

    test('strips \\textbf formatting', () {
      const latex = r'''
\begin{tabular}{lc}
\textbf{Name} & \textbf{Value} \\
X & 42 \\
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.allRows[0], ['Name', 'Value']);
    });

    test('handles \\multicolumn', () {
      const latex = r'''
\begin{tabular}{lcc}
\multicolumn{2}{|c|}{Header} & Other \\
A & B & C \\
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.allRows[0][0], 'Header');
    });

    test('ignores \\hline, \\toprule, \\midrule, \\bottomrule', () {
      const latex = r'''
\begin{tabular}{ll}
\toprule
Name & Value \\
\midrule
A & 1 \\
\bottomrule
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.allRows.length, 2);
    });

    test('handles alignment with pipe separators', () {
      const latex = r'''
\begin{tabular}{|l|c|r|}
\hline
A & B & C \\
\hline
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.alignment, 'lcr');
    });
  });

  group('LatexTableParser — matrices', () {
    test('parses bmatrix', () {
      const latex = r'''
\begin{bmatrix}
1 & 2 & 3 \\
4 & 5 & 6 \\
7 & 8 & 9
\end{bmatrix}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.environment, 'bmatrix');
      expect(result.data.length, 3);
      expect(result.data[0], ['1', '2', '3']);
      expect(result.data[2], ['7', '8', '9']);
    });

    test('parses pmatrix', () {
      const latex = r'''
\begin{pmatrix}
a & b \\
c & d
\end{pmatrix}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.environment, 'pmatrix');
      expect(result.data.length, 2);
    });

    test('parses vmatrix (determinant)', () {
      const latex = r'''
\begin{vmatrix}
1 & 0 \\
0 & 1
\end{vmatrix}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.environment, 'vmatrix');
    });
  });

  group('LatexTableParser — parseAll', () {
    test('finds multiple tables in a document', () {
      const latex = r'''
\begin{tabular}{ll}
A & B \\
\end{tabular}

Some text in between.

\begin{bmatrix}
1 & 2 \\
3 & 4
\end{bmatrix}
''';
      final results = parser.parseAll(latex);
      expect(results.length, 2);
      expect(results[0].environment, 'tabular');
      expect(results[1].environment, 'bmatrix');
    });
  });

  group('LatexTableParser — edge cases', () {
    test('returns null for non-table content', () {
      const latex = r'Hello, this is just text with no tables.';
      expect(parser.parse(latex), isNull);
    });

    test('handles empty tabular', () {
      const latex = r'''
\begin{tabular}{l}
\hline
\hline
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNull); // No data rows
    });

    test('columnCount returns widest row', () {
      const latex = r'''
\begin{tabular}{lcr}
A & B & C \\
D & E \\
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.columnCount, 3);
    });

    test('totalRows includes all parsed rows', () {
      const latex = r'''
\begin{bmatrix}
1 & 2 \\
3 & 4 \\
5 & 6
\end{bmatrix}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.totalRows, 3);
    });

    test('strips math mode delimiters', () {
      const latex = r'''
\begin{tabular}{cc}
$x$ & $y$ \\
$1$ & $2$ \\
\end{tabular}
''';
      final result = parser.parse(latex);
      expect(result, isNotNull);
      expect(result!.allRows[0], ['x', 'y']);
    });
  });
}
