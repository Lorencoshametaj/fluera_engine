import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/digital_ink_service.dart';
import '../../services/handwriting_index_service.dart';
import '../../drawing/models/pro_drawing_point.dart';

// =============================================================================
// ✍️ SMART INK OVERLAY — Tap-to-reveal recognized handwriting text
//
// Glassmorphic popup that appears when the user taps on handwritten strokes.
// Features:
//   - Shows recognized text with alternative candidates
//   - Copy to clipboard
//   - Convert to DigitalTextElement
//   - Integrates with toolwheel (not toolbar)
//
// ARCHITECTURE:
//   - Stateful widget positioned at stroke location
//   - Queries HandwritingIndexService for existing recognition
//   - Falls back to live DigitalInkService recognition
//   - Spring-animated entrance/exit
// =============================================================================

/// Result returned from the Smart Ink overlay.
class SmartInkResult {
  /// The recognized text (possibly corrected by user via candidate selection).
  final String text;

  /// The action the user chose.
  final SmartInkAction action;

  const SmartInkResult({required this.text, required this.action});
}

enum SmartInkAction {
  /// User dismissed the overlay (no action).
  dismiss,

  /// Copy text to clipboard.
  copy,

  /// Convert strokes to a DigitalTextElement.
  convert,

  /// User selected an alternative candidate — update the index.
  selectAlternative,
}

/// ✍️ Smart Ink Overlay — tap-to-reveal handwriting recognition.
///
/// Shows recognized text above a stroke with glassmorphic styling.
/// Positioned in screen space, anchored to the stroke's bounds.
class SmartInkOverlay extends StatefulWidget {
  /// Screen-space position to anchor the overlay (typically above the stroke).
  final Offset anchorPosition;

  /// All stroke point sets to recognize (grouped nearby strokes).
  final List<List<ProDrawingPoint>> allStrokeSets;

  /// Stroke IDs for index lookup (one per stroke set).
  final List<String> strokeIds;

  /// Canvas ID for index lookup.
  final String canvasId;

  /// Canvas viewport for writing area context.
  final ui.Size? writingArea;

  /// Called when the user picks an action.
  final ValueChanged<SmartInkResult> onResult;

  /// Whether the app is in dark mode.
  final bool isDark;

  const SmartInkOverlay({
    super.key,
    required this.anchorPosition,
    required this.allStrokeSets,
    required this.strokeIds,
    required this.canvasId,
    required this.onResult,
    this.writingArea,
    this.isDark = true,
  });

  @override
  State<SmartInkOverlay> createState() => _SmartInkOverlayState();
}

class _SmartInkOverlayState extends State<SmartInkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  String? _recognizedText;
  String _detectedType = 'text'; // 'math' or 'text'
  List<InkCandidate> _candidates = const [];
  bool _isLoading = true;
  int _selectedCandidateIndex = 0;
  bool _copied = false;

  // ── Result cache (avoids re-recognition for same strokes) ──────────
  static final Map<int, _CachedResult> _cache = {};
  int get _cacheKey => Object.hashAll(widget.strokeIds);

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scaleAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );

    _entranceController.forward();
    _loadRecognition();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  /// Load recognition: check cache → index → live recognition.
  Future<void> _loadRecognition() async {
    // ── Check cache first ──────────────────────────────────────────────
    final cached = _cache[_cacheKey];
    if (cached != null) {
      _recognizedText = cached.text;
      _detectedType = cached.detectedType;
      _candidates = cached.candidates;
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // ── Try index (instant) ────────────────────────────────────────────
    final indexService = HandwritingIndexService.instance;
    if (indexService.isInitialized && widget.strokeIds.isNotEmpty) {
      final textMap = await indexService.getTextMapForStrokes(
        widget.canvasId,
        widget.strokeIds,
      );
      if (textMap.isNotEmpty) {
        _recognizedText = textMap.values.join(' ').trim();
      }
    }

    // ── Live recognition ──────────────────────────────────────────────
    final inkService = DigitalInkService.instance;
    final totalPoints = widget.allStrokeSets.fold<int>(
        0, (sum, s) => sum + s.length);
    if (inkService.isAvailable && totalPoints >= 5) {
      String? preContext;
      if (indexService.isInitialized) {
        preContext = await indexService.getPreContext(widget.canvasId);
      }
      final context = InkRecognitionContext(
        writingArea: widget.writingArea,
        preContext: preContext,
      );
      final candidates = await inkService.recognizeMultiStrokeCandidates(
        widget.allStrokeSets,
        context: context,
        maxCandidates: 5,
      );
      if (candidates.isNotEmpty) {
        _candidates = candidates;
        _recognizedText ??= candidates.first.text;

        // Detect type from result content
        final text = _recognizedText ?? '';
        _detectedType = _looksLikeMath(text) ? 'math' : 'text';
      }
    }

    // ── Cache result ──────────────────────────────────────────────────
    if (_recognizedText != null) {
      _cache[_cacheKey] = _CachedResult(
        text: _recognizedText!,
        detectedType: _detectedType,
        candidates: _candidates,
      );
      // Cap cache at 50 entries
      if (_cache.length > 50) _cache.remove(_cache.keys.first);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Heuristic: does this look like a math expression?
  static bool _looksLikeMath(String s) {
    return s.contains('^{') || s.contains('_{') ||
        s.contains(r'\frac') || s.contains(r'\sqrt') ||
        s.contains(r'\sum') || s.contains(r'\int') ||
        RegExp(r'[\^_{}\\]').hasMatch(s);
  }

  void _dismiss() {
    _entranceController.reverse().then((_) {
      if (mounted) {
        widget.onResult(SmartInkResult(
          text: _recognizedText ?? '',
          action: SmartInkAction.dismiss,
        ));
      }
    });
  }

  void _copyToClipboard() {
    if (_recognizedText == null) return;
    // Smart copy: raw LaTeX for math, plain text for text
    Clipboard.setData(ClipboardData(text: _recognizedText!));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _dismiss();
    });
  }

  void _convertToText() {
    if (_recognizedText == null) return;
    HapticFeedback.mediumImpact();
    widget.onResult(SmartInkResult(
      text: _recognizedText!,
      action: SmartInkAction.convert,
    ));
  }

  void _selectCandidate(int index) {
    if (index >= _candidates.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCandidateIndex = index;
      _recognizedText = _candidates[index].text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    // Position: above the anchor, centered horizontally
    const overlayWidth = 260.0;
    final left = (widget.anchorPosition.dx - overlayWidth / 2)
        .clamp(12.0, screenSize.width - overlayWidth - 12.0);
    final top = (widget.anchorPosition.dy - 140)
        .clamp(12.0, screenSize.height - 200);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                alignment: Alignment.bottomCenter,
                child: _buildCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    final isDark = widget.isDark;
    final bgColor = isDark
        ? const Color(0xCC1E1E2E)
        : const Color(0xCCF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark
        ? Colors.white38
        : Colors.black38;
    final accentColor = const Color(0xFF818CF8);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 260,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Icon(Icons.draw_rounded, size: 16,
                        color: accentColor),
                    const SizedBox(width: 6),
                    Text('Smart Ink',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: subtleColor, letterSpacing: 0.5,
                      ),
                    ),
                    if (!_isLoading && _recognizedText != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (_detectedType == 'math'
                              ? const Color(0xFFFF9800)
                              : const Color(0xFF4CAF50)
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _detectedType == 'math' ? '𝑓(x)' : 'Aa',
                          style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: _detectedType == 'math'
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: subtleColor),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Recognized text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _isLoading
                    ? SizedBox(
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentColor,
                            ),
                          ),
                        ),
                      )
                    : _recognizedText == null
                        ? Text(
                            'Could not recognize text',
                            style: TextStyle(
                              fontSize: 14, color: subtleColor,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Text(
                            _detectedType == 'math'
                                ? _latexToUnicode(_recognizedText!)
                                : _recognizedText!,
                            style: TextStyle(
                              fontSize: _detectedType == 'math' ? 24 : 20,
                              fontWeight: FontWeight.w500,
                              color: textColor, height: 1.3,
                              fontFamily: _detectedType == 'math'
                                  ? 'serif' : null,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
              ),

              // Candidate chips (if multiple)
              if (_candidates.length > 1 && !_isLoading) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, index) {
                      final isSelected = index == _selectedCandidateIndex;
                      return GestureDetector(
                        onTap: () => _selectCandidate(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accentColor.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? accentColor
                                  : subtleColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _candidates[index].text,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected ? accentColor : subtleColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Action buttons
              if (_recognizedText != null && !_isLoading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      // Copy button
                      Expanded(
                        child: _ActionButton(
                          icon: _copied
                              ? Icons.check_rounded
                              : Icons.copy_rounded,
                          label: _copied ? 'Copied!' : 'Copy',
                          color: _copied
                              ? const Color(0xFF6BCB7F)
                              : accentColor,
                          onTap: _copied ? null : _copyToClipboard,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Convert button
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.text_fields_rounded,
                          label: 'Convert',
                          color: const Color(0xFFA87FDB),
                          onTap: _convertToText,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact action button for the Smart Ink overlay.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(label,
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: color, letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cached recognition result to avoid re-processing same strokes.
class _CachedResult {
  final String text;
  final String detectedType;
  final List<InkCandidate> candidates;

  const _CachedResult({
    required this.text,
    required this.detectedType,
    required this.candidates,
  });
}

/// Convert common LaTeX to readable Unicode math text.
///
/// Examples:
///   x^{2}+1  →  x²+1
///   \frac{a}{b}  →  a/b
///   \sqrt{x}  →  √x
String _latexToUnicode(String latex) {
  var s = latex;

  // Superscripts
  const superMap = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    'n': 'ⁿ', 'i': 'ⁱ', '+': '⁺', '-': '⁻', '=': '⁼',
    '(': '⁽', ')': '⁾', 'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ',
    'd': 'ᵈ', 'e': 'ᵉ', 'k': 'ᵏ', 'm': 'ᵐ', 'x': 'ˣ',
  };

  // Subscripts
  const subMap = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    'a': 'ₐ', 'e': 'ₑ', 'i': 'ᵢ', 'n': 'ₙ', 'x': 'ₓ',
    '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  };

  // Replace ^{...} with Unicode superscripts
  s = s.replaceAllMapped(RegExp(r'\^{([^}]*)}'), (m) {
    return m[1]!.split('').map((c) => superMap[c] ?? c).join();
  });
  s = s.replaceAllMapped(RegExp(r'\^(.)'), (m) {
    return superMap[m[1]!] ?? '^${m[1]}';
  });

  // Replace _{...} with Unicode subscripts
  s = s.replaceAllMapped(RegExp(r'_{([^}]*)}'), (m) {
    return m[1]!.split('').map((c) => subMap[c] ?? c).join();
  });
  s = s.replaceAllMapped(RegExp(r'_(.)'), (m) {
    return subMap[m[1]!] ?? '_${m[1]}';
  });

  // Common commands
  s = s.replaceAllMapped(RegExp(r'\\frac{([^}]*)}{([^}]*)}'), (m) =>
      '${m[1]}⁄${m[2]}');
  s = s.replaceAllMapped(RegExp(r'\\sqrt{([^}]*)}'), (m) => '√${m[1]}');
  s = s.replaceAll(r'\sqrt', '√');
  s = s.replaceAll(r'\pi', 'π');
  s = s.replaceAll(r'\alpha', 'α');
  s = s.replaceAll(r'\beta', 'β');
  s = s.replaceAll(r'\gamma', 'γ');
  s = s.replaceAll(r'\delta', 'δ');
  s = s.replaceAll(r'\theta', 'θ');
  s = s.replaceAll(r'\lambda', 'λ');
  s = s.replaceAll(r'\mu', 'μ');
  s = s.replaceAll(r'\sigma', 'σ');
  s = s.replaceAll(r'\omega', 'ω');
  s = s.replaceAll(r'\infty', '∞');
  s = s.replaceAll(r'\sum', '∑');
  s = s.replaceAll(r'\int', '∫');
  s = s.replaceAll(r'\prod', '∏');
  s = s.replaceAll(r'\times', '×');
  s = s.replaceAll(r'\div', '÷');
  s = s.replaceAll(r'\pm', '±');
  s = s.replaceAll(r'\leq', '≤');
  s = s.replaceAll(r'\geq', '≥');
  s = s.replaceAll(r'\neq', '≠');
  s = s.replaceAll(r'\approx', '≈');
  s = s.replaceAll(r'\cdot', '·');

  // Clean up remaining braces and backslashes
  s = s.replaceAll(RegExp(r'[{}]'), '');

  return s;
}
