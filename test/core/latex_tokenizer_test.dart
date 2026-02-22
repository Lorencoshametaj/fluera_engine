import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/latex/latex_tokenizer.dart';

void main() {
  late LatexTokenizer tokenizer;

  setUp(() {
    // Build a tokenizer with the CoMER vocabulary
    tokenizer = LatexTokenizer();
    tokenizer.loadFromJson('''
{
  "vocab": {
    "0": "<pad>",
    "1": "<sos>",
    "2": "<eos>",
    "3": "!",
    "4": "(",
    "5": ")",
    "6": "+",
    "7": ",",
    "8": "-",
    "9": ".",
    "10": "/",
    "11": "0",
    "12": "1",
    "13": "2",
    "14": "3",
    "15": "4",
    "16": "5",
    "17": "6",
    "18": "7",
    "19": "8",
    "20": "9",
    "21": "<",
    "22": "=",
    "23": ">",
    "24": "A",
    "25": "B",
    "26": "C",
    "27": "E",
    "28": "F",
    "29": "G",
    "30": "H",
    "31": "I",
    "32": "L",
    "33": "M",
    "34": "N",
    "35": "P",
    "36": "R",
    "37": "S",
    "38": "T",
    "39": "V",
    "40": "X",
    "41": "Y",
    "42": "[",
    "43": "\\\\Delta",
    "44": "\\\\Pi",
    "45": "\\\\alpha",
    "46": "\\\\beta",
    "47": "\\\\cdot",
    "48": "\\\\cdots",
    "49": "\\\\cos",
    "50": "\\\\div",
    "51": "\\\\exists",
    "52": "\\\\forall",
    "53": "\\\\frac",
    "54": "\\\\gamma",
    "55": "\\\\geq",
    "56": "\\\\in",
    "57": "\\\\infty",
    "58": "\\\\int",
    "59": "\\\\lambda",
    "60": "\\\\ldots",
    "61": "\\\\leq",
    "62": "\\\\lim",
    "63": "\\\\limits",
    "64": "\\\\log",
    "65": "\\\\mu",
    "66": "\\\\neq",
    "67": "\\\\phi",
    "68": "\\\\pi",
    "69": "\\\\pm",
    "70": "\\\\prime",
    "71": "\\\\rightarrow",
    "72": "\\\\sigma",
    "73": "\\\\sin",
    "74": "\\\\sqrt",
    "75": "\\\\sum",
    "76": "\\\\tan",
    "77": "\\\\theta",
    "78": "\\\\times",
    "79": "\\\\{",
    "80": "\\\\}",
    "81": "]",
    "82": "^",
    "83": "_",
    "84": "a",
    "85": "b",
    "86": "c",
    "87": "d",
    "88": "e",
    "89": "f",
    "90": "g",
    "91": "h",
    "92": "i",
    "93": "j",
    "94": "k",
    "95": "l",
    "96": "m",
    "97": "n",
    "98": "o",
    "99": "p",
    "100": "q",
    "101": "r",
    "102": "s",
    "103": "t",
    "104": "u",
    "105": "v",
    "106": "w",
    "107": "x",
    "108": "y",
    "109": "z",
    "110": "{",
    "111": "|",
    "112": "}"
  },
  "special_tokens": {
    "pad_token_id": 0,
    "sos_token_id": 1,
    "eos_token_id": 2
  },
  "vocab_size": 113
}
''');
  });

  // ===========================================================================
  // Spacing between tokens
  // ===========================================================================

  group('LatexTokenizer — decode spacing', () {
    test('simple variable equation: v=x/t', () {
      // SOS(1) v(105) =(22) x(107) /(10) t(103) EOS(2)
      final ids = [1, 105, 22, 107, 10, 103, 2];
      final result = tokenizer.decode(ids);
      expect(result, 'v=x/t');
    });

    test('cdot between variables: a cdot b', () {
      // SOS(1) a(84) \cdot(47) b(85) EOS(2)
      final ids = [1, 84, 47, 85, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'a \cdot b');
    });

    test('frac with braces: frac{a}{b}', () {
      // SOS(1) \frac(53) {(110) a(84) }(112) {(110) b(85) }(112) EOS(2)
      final ids = [1, 53, 110, 84, 112, 110, 85, 112, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'\frac{a}{b}');
    });

    test('superscript: x^{2}', () {
      // SOS(1) x(107) ^(82) {(110) 2(13) }(112) EOS(2)
      final ids = [1, 107, 82, 110, 13, 112, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'x^{2}');
    });

    test('subscript: a_i', () {
      // SOS(1) a(84) _(83) i(92) EOS(2)
      final ids = [1, 84, 83, 92, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'a_i');
    });

    test('sum with limits: sum_{i=0}^{n}', () {
      // SOS(1) \sum(75) _(83) {(110) i(92) =(22) 0(11) }(112)
      //        ^(82) {(110) n(97) }(112) EOS(2)
      final ids = [1, 75, 83, 110, 92, 22, 11, 112, 82, 110, 97, 112, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'\sum_{i=0}^{n}');
    });

    test('alpha + beta: greek letters with space', () {
      // SOS(1) \alpha(45) +(6) \beta(46) EOS(2)
      final ids = [1, 45, 6, 46, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'\alpha+\beta');
    });

    test('two adjacent variables get spaced: a b', () {
      // SOS(1) a(84) b(85) EOS(2)
      final ids = [1, 84, 85, 2];
      final result = tokenizer.decode(ids);
      expect(result, 'a b');
    });

    test('number digits stay together: 1 4 → get spaced as separate tokens', () {
      // SOS(1) 1(12) 4(15) EOS(2) — these are tokens for "1" and "4"
      final ids = [1, 12, 15, 2];
      final result = tokenizer.decode(ids);
      // The model tokenizes each digit separately, so they are separate tokens
      // In LaTeX "14" and "1 4" are both valid but the model should produce
      // the right sequence. Here we test the spacing behavior.
      expect(result, '1 4');
    });

    test('complex: v=frac{x}{t}', () {
      // SOS(1) v(105) =(22) \frac(53) {(110) x(107) }(112) {(110) t(103) }(112) EOS(2)
      final ids = [1, 105, 22, 53, 110, 107, 112, 110, 103, 112, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'v=\frac{x}{t}');
    });

    test('sqrt{x}', () {
      // SOS(1) \sqrt(74) {(110) x(107) }(112) EOS(2)
      final ids = [1, 74, 110, 107, 112, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'\sqrt{x}');
    });

    test('int_a^b', () {
      // SOS(1) \int(58) _(83) a(84) ^(82) b(85) EOS(2)
      final ids = [1, 58, 83, 84, 82, 85, 2];
      final result = tokenizer.decode(ids);
      expect(result, r'\int_a^b');
    });
  });

  // ===========================================================================
  // Core decode behavior
  // ===========================================================================

  group('LatexTokenizer — decode basics', () {
    test('empty token list produces empty string', () {
      expect(tokenizer.decode([]), '');
    });

    test('only BOS/EOS/PAD produces empty string', () {
      expect(tokenizer.decode([0, 1, 2]), '');
    });

    test('stops at EOS', () {
      // SOS(1) a(84) EOS(2) b(85) — b should not appear
      final ids = [1, 84, 2, 85];
      final result = tokenizer.decode(ids);
      expect(result, 'a');
    });

    test('unknown token IDs are skipped', () {
      final ids = [1, 84, 999, 85, 2];
      final result = tokenizer.decode(ids);
      expect(result, 'a b');
    });
  });

  // ===========================================================================
  // Post-processing
  // ===========================================================================

  group('LatexTokenizer — post-processing', () {
    test('strips <unk> tokens', () {
      tokenizer.loadFromJson('''
{
  "vocab": {"0": "<pad>", "1": "<sos>", "2": "<eos>", "3": "<unk>", "4": "x"},
  "special_tokens": {"pad_token_id": 0, "sos_token_id": 1, "eos_token_id": 2}
}
''');
      final ids = [1, 3, 4, 2];
      final result = tokenizer.decode(ids);
      expect(result, 'x');
    });

    test('fixes unmatched braces', () {
      // Simulate a decode that produces unmatched braces
      // SOS(1) {(110) a(84) EOS(2)  — missing }
      final ids = [1, 110, 84, 2];
      final result = tokenizer.decode(ids);
      expect(result, '{a}');
    });
  });

  // ===========================================================================
  // Encode (best-effort)
  // ===========================================================================

  group('LatexTokenizer — encode', () {
    test('encodes single letter', () {
      final ids = tokenizer.encode('x');
      expect(ids.first, tokenizer.bosTokenId);
      expect(ids.last, tokenizer.eosTokenId);
      expect(ids.contains(107), true); // x = 107
    });

    test('encodes frac command', () {
      final ids = tokenizer.encode(r'\frac');
      expect(ids.contains(53), true); // \frac = 53
    });
  });
}
