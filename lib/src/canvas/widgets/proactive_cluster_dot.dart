import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/proactive_analysis_model.dart';

/// 💡 PROACTIVE CLUSTER DOT
///
/// Visual states:
/// - pending      → dim amber pulse
/// - ready        → cyan + gap count badge  
/// - dueForReview → orange 📅 pulse  (SR review overdue)
/// - allMastered  → green ✓
///
/// Long-press → sneak peek tooltip with SCAN + gaps (auto-dismiss 3s)
class ProactiveClusterDot extends StatefulWidget {
  final Offset screenPosition;
  final ProactiveAnalysisEntry entry;
  final VoidCallback onTap;
  final int gapCount;
  final bool allMastered;

  const ProactiveClusterDot({
    super.key,
    required this.screenPosition,
    required this.entry,
    required this.onTap,
    this.gapCount = 0,
    this.allMastered = false,
  });

  @override
  State<ProactiveClusterDot> createState() => _ProactiveClusterDotState();
}

class _ProactiveClusterDotState extends State<ProactiveClusterDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _showPeek = false;
  Timer? _peekTimer;

  static const _readyColor   = Color(0xFF00E5FF); // cyan
  static const _pendingColor = Color(0xFFFFAB40); // amber
  static const _reviewColor  = Color(0xFFFF7043); // deep orange — due for review
  static const _masterColor  = Color(0xFF66BB6A); // green

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    _peekTimer?.cancel();
    super.dispose();
  }

  void _triggerPeek() {
    HapticFeedback.mediumImpact();
    setState(() => _showPeek = true);
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showPeek = false);
    });
  }

  Color get _dotColor {
    if (widget.allMastered) return _masterColor;
    switch (widget.entry.status) {
      case ProactiveStatus.dueForReview: return _reviewColor;
      case ProactiveStatus.pending:      return _pendingColor;
      default:                           return _readyColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady   = widget.entry.status == ProactiveStatus.ready ||
                      widget.entry.status == ProactiveStatus.dueForReview;
    final isDue     = widget.entry.status == ProactiveStatus.dueForReview;
    final isMaster  = widget.allMastered && isReady;
    final color     = isMaster ? _masterColor : _dotColor;
    final pos       = widget.screenPosition;
    final scanText  = widget.entry.scanText;
    final gaps      = widget.entry.gaps;

    return Positioned(
      left: pos.dx + 14,
      top: pos.dy - 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Sneak-peek tooltip ────────────────────────────────────────
          if (_showPeek && scanText.isNotEmpty)
            Positioned(
              bottom: 24,
              left: -80,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 200),
                builder: (_, v, child) => Opacity(opacity: v,
                    child: Transform.scale(scale: 0.85 + 0.15 * v, child: child)),
                child: Container(
                  width: 200,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E0E1A).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
                    boxShadow: [BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 12,
                    )],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // SCAN text
                      Text(
                        scanText.length > 90
                            ? '${scanText.substring(0, 87)}…'
                            : scanText,
                        style: const TextStyle(
                          color: Color(0xFFE0E0E0),
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                      if (gaps.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...gaps.take(3).map((g) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('• $g',
                            style: TextStyle(
                              color: color.withValues(alpha: 0.85),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            )),
                        )),
                      ],
                      const SizedBox(height: 4),
                      Text('Tieni premuto per aprire →',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.5),
                          fontSize: 8,
                          fontStyle: FontStyle.italic,
                        )),
                    ],
                  ),
                ),
              ),
            ),

          // ── Main dot ─────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final t = _anim.value;
              final scale = isMaster
                  ? 1.0 + math.sin(t * math.pi) * 0.06
                  : isDue
                      ? 0.9 + t * 0.2  // more aggressive pulse for due
                      : isReady
                          ? 1.0 + math.sin(t * math.pi) * 0.22
                          : 0.8 + t * 0.2;
              final opacity = isReady ? 0.78 + t * 0.22 : 0.3 + t * 0.3;

              return GestureDetector(
                onTap: widget.onTap,
                onLongPress: _triggerPeek,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: opacity * 0.85),
                      border: Border.all(color: color.withValues(alpha: opacity), width: 1.5),
                      boxShadow: isReady
                          ? [BoxShadow(
                              color: color.withValues(alpha: opacity * 0.55),
                              blurRadius: 10 + t * 8,
                              spreadRadius: 2 + t * 3,
                            )]
                          : null,
                    ),
                    child: Center(
                      child: isMaster
                          ? Icon(Icons.check_rounded, size: 11,
                              color: Colors.white.withValues(alpha: 0.9))
                          : isDue
                              ? Text('📅', style: const TextStyle(fontSize: 8))
                              : isReady && widget.gapCount > 0
                                  ? Text('${widget.gapCount}',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white.withValues(alpha: 0.95),
                                        height: 1,
                                      ))
                                  : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
