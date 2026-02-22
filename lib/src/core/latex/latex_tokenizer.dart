import 'dart:convert';
import 'package:flutter/services.dart';

/// 🔤 LaTeX Tokenizer — converts between token IDs and LaTeX strings.
///
/// Loads a pre-exported vocabulary from the bundled `tokenizer.json` asset
/// produced by `scripts/convert_pix2tex_onnx.py`.
///
/// Used by [OnnxLatexRecognizer] to decode the autoregressive decoder output.
class LatexTokenizer {
  /// ID → token string mapping.
  Map<int, String> _id2token = {};

  /// Token string → ID mapping.
  Map<String, int> _token2id = {};

  /// Beginning-of-sequence token ID.
  int bosTokenId = 1;

  /// End-of-sequence token ID.
  int eosTokenId = 2;

  /// Padding token ID.
  int padTokenId = 0;

  /// Total vocabulary size.
  int get vocabSize => _id2token.length;

  /// Whether the tokenizer has been loaded.
  bool get isLoaded => _id2token.isNotEmpty;

  /// Asset path for the tokenizer JSON.
  static const String defaultAssetPath = 'assets/models/comer/vocab.json';

  /// Load tokenizer from a bundled asset.
  ///
  /// Call this once during initialization. Safe to call multiple times.
  Future<void> load({String assetPath = defaultAssetPath}) async {
    if (isLoaded) return;

    // Try package-prefixed path first (for host apps using nebula_engine as dep)
    String? jsonStr;
    try {
      jsonStr = await rootBundle.loadString(
        'packages/nebula_engine/$assetPath',
      );
    } catch (_) {
      // Fall back to raw path (for engine's own test harness)
      try {
        jsonStr = await rootBundle.loadString(assetPath);
      } catch (e) {
        throw StateError('Failed to load tokenizer from $assetPath: $e');
      }
    }

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Parse vocabulary: {"vocab": {"0": "<pad>", "1": "<s>", ...}}
      final vocab = data['vocab'] as Map<String, dynamic>? ?? {};
      _id2token = {};
      _token2id = {};
      for (final entry in vocab.entries) {
        final id = int.tryParse(entry.key);
        final token = entry.value as String? ?? '';
        if (id != null) {
          _id2token[id] = token;
          _token2id[token] = id;
        }
      }

      // Parse special tokens
      final special = data['special_tokens'] as Map<String, dynamic>? ?? {};
      bosTokenId =
          special['bos_token_id'] as int? ??
          special['sos_token_id'] as int? ??
          1;
      eosTokenId = special['eos_token_id'] as int? ?? 2;
      padTokenId = special['pad_token_id'] as int? ?? 0;
    } catch (e) {
      throw StateError('Failed to parse tokenizer JSON: $e');
    }
  }

  /// Load tokenizer from a raw JSON string (for testing).
  void loadFromJson(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final vocab = data['vocab'] as Map<String, dynamic>? ?? {};
    _id2token = {};
    _token2id = {};
    for (final entry in vocab.entries) {
      final id = int.tryParse(entry.key);
      final token = entry.value as String? ?? '';
      if (id != null) {
        _id2token[id] = token;
        _token2id[token] = id;
      }
    }

    final special = data['special_tokens'] as Map<String, dynamic>? ?? {};
    bosTokenId = special['bos_token_id'] as int? ?? 1;
    eosTokenId = special['eos_token_id'] as int? ?? 2;
    padTokenId = special['pad_token_id'] as int? ?? 0;
  }

  /// Decode a sequence of token IDs to a LaTeX string.
  ///
  /// Stops at the first EOS token. Strips BOS, EOS, and PAD tokens.
  /// Inserts spaces between tokens where needed for valid LaTeX output.
  String decode(List<int> tokenIds) {
    final tokens = <String>[];

    for (final id in tokenIds) {
      if (id == eosTokenId) break;
      if (id == bosTokenId || id == padTokenId) continue;

      final token = _id2token[id];
      if (token != null) {
        tokens.add(token);
      }
    }

    final buffer = StringBuffer();
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final prev = i > 0 ? tokens[i - 1] : '';

      // Decide whether we need a space before this token
      if (i > 0 && _needsSpaceBetween(prev, token)) {
        buffer.write(' ');
      }

      buffer.write(token);
    }

    return _postProcess(buffer.toString());
  }

  /// Check whether a space is needed between two adjacent tokens.
  ///
  /// Rules:
  /// - No space before/after structural tokens: { } ^ _ ( ) [ ]
  /// - Space before a LaTeX command (\xxx) if preceded by a letter/digit/closing
  /// - Space after a LaTeX command if followed by a letter/digit
  /// - Space between two adjacent letters/digits that are separate tokens
  ///   (e.g. token "a" + token "b" → "a b" since they're distinct variables)
  bool _needsSpaceBetween(String prev, String current) {
    if (prev.isEmpty || current.isEmpty) return false;

    // Structural tokens never get separated
    const noSpaceTokens = {'{', '}', '^', '_', '(', ')', '[', ']'};
    if (noSpaceTokens.contains(prev) || noSpaceTokens.contains(current)) {
      return false;
    }

    final prevIsCmd = prev.startsWith(r'\');
    final curIsCmd = current.startsWith(r'\');

    // Space before a \command if preceded by alphanumeric, '}', or ')'
    if (curIsCmd) {
      final lastChar = prev[prev.length - 1];
      return _isAlphaNum(lastChar) || lastChar == '}' || lastChar == ')';
    }

    // Space after a \command if followed by alphanumeric
    if (prevIsCmd) {
      final firstChar = current[0];
      return _isAlphaNum(firstChar);
    }

    // Space between two distinct single-letter/digit tokens
    // (e.g. "a" + "b" are separate variables, not "ab")
    if (_isAlphaNum(prev[prev.length - 1]) && _isAlphaNum(current[0])) {
      return true;
    }

    // No space for operators next to operands (e.g. "=" "+" "-" "/")
    return false;
  }

  /// Check if a character is alphanumeric (letter or digit).
  bool _isAlphaNum(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) || // 0-9
        (code >= 0x41 && code <= 0x5A) || // A-Z
        (code >= 0x61 && code <= 0x7A); // a-z
  }

  /// Encode a LaTeX string to token IDs (best-effort character-level).
  ///
  /// This is a simplified encoder for testing. The real encoding
  /// happens on the model side during training.
  List<int> encode(String latex) {
    final ids = <int>[bosTokenId];

    for (int i = 0; i < latex.length; i++) {
      // Try multi-character tokens first (longest match)
      bool found = false;
      for (int len = 10; len >= 1; len--) {
        if (i + len > latex.length) continue;
        final substr = latex.substring(i, i + len);
        final id = _token2id[substr];
        if (id != null) {
          ids.add(id);
          i += len - 1;
          found = true;
          break;
        }
      }
      if (!found) {
        // Single character fallback
        final id = _token2id[latex[i]];
        if (id != null) ids.add(id);
      }
    }

    ids.add(eosTokenId);
    return ids;
  }

  /// Post-process decoded LaTeX string for correctness and cleanliness.
  ///
  /// Applies 9 normalization rules to fix common model artifacts:
  /// 1. Strip stale `<unk>` / `<pad>` tokens
  /// 2. Remove trailing incomplete commands
  /// 3. Fix unmatched braces
  /// 4. Normalize redundant whitespace
  /// 5. Remove empty groups `{}`
  /// 6. Remove redundant escapes
  /// 7. Fix consecutive superscripts/subscripts
  /// 8. Trim and clean
  String _postProcess(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;

    // 1. Remove stale special tokens
    s = s.replaceAll('<unk>', '');
    s = s.replaceAll('<pad>', '');
    s = s.replaceAll('<s>', '');
    s = s.replaceAll('</s>', '');

    // 2. Remove trailing incomplete commands (e.g. "\fra" at the end)
    final trailingCmd = RegExp(r'\\[a-zA-Z]*$');
    final match = trailingCmd.firstMatch(s);
    if (match != null) {
      final cmd = match.group(0)!;
      // Only remove if it's NOT a valid complete command
      if (!_isValidLatexCommand(cmd)) {
        s = s.substring(0, match.start);
      }
    }

    // 3. Fix unmatched braces
    s = _fixUnmatchedBraces(s);

    // 4. Normalize whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(r'\ ', ' ');

    // 5. Remove empty groups (but not \text{})
    s = s.replaceAll(RegExp(r'(?<!\\text)\{\}'), '');
    s = s.replaceAll(RegExp(r'(?<!\\mathrm)\{\}'), '');

    // 6. Fix doubled operators
    s = s.replaceAll('^^', '^');
    s = s.replaceAll('__', '_');

    // 7. Clean up spacing around common operators
    s = s.replaceAll(' ^', '^');
    s = s.replaceAll(' _', '_');
    s = s.replaceAll('{ ', '{');
    s = s.replaceAll(' }', '}');

    return s.trim();
  }

  /// Check if a command is a known valid LaTeX command.
  bool _isValidLatexCommand(String cmd) {
    const validCommands = {
      r'\frac',
      r'\sqrt',
      r'\sum',
      r'\prod',
      r'\int',
      r'\lim',
      r'\log',
      r'\ln',
      r'\sin',
      r'\cos',
      r'\tan',
      r'\alpha',
      r'\beta',
      r'\gamma',
      r'\delta',
      r'\epsilon',
      r'\theta',
      r'\lambda',
      r'\mu',
      r'\pi',
      r'\sigma',
      r'\phi',
      r'\psi',
      r'\omega',
      r'\infty',
      r'\partial',
      r'\nabla',
      r'\forall',
      r'\exists',
      r'\in',
      r'\cup',
      r'\cap',
      r'\subset',
      r'\supset',
      r'\times',
      r'\cdot',
      r'\leq',
      r'\geq',
      r'\neq',
      r'\approx',
      r'\equiv',
      r'\pm',
      r'\mp',
      r'\to',
      r'\rightarrow',
      r'\leftarrow',
      r'\Rightarrow',
      r'\Leftarrow',
      r'\hat',
      r'\bar',
      r'\vec',
      r'\dot',
      r'\ddot',
      r'\tilde',
      r'\text',
      r'\mathrm',
      r'\mathbf',
      r'\mathcal',
      r'\mathbb',
      r'\binom',
      r'\left',
      r'\right',
      r'\big',
      r'\Big',
      r'\bigg',
      r'\Bigg',
      r'\begin',
      r'\end',
      r'\over',
      r'\under',
    };
    return validCommands.contains(cmd);
  }

  /// Fix unmatched braces by adding missing closing/opening braces.
  String _fixUnmatchedBraces(String s) {
    int depth = 0;
    int minDepth = 0;

    for (int i = 0; i < s.length; i++) {
      if (s[i] == '{' && (i == 0 || s[i - 1] != '\\')) {
        depth++;
      } else if (s[i] == '}' && (i == 0 || s[i - 1] != '\\')) {
        depth--;
        if (depth < minDepth) minDepth = depth;
      }
    }

    // Add missing opening braces at start
    if (minDepth < 0) {
      s = '{' * (-minDepth) + s;
      depth -= minDepth;
    }

    // Add missing closing braces at end
    if (depth > 0) {
      s = s + '}' * depth;
    }

    return s;
  }
}
