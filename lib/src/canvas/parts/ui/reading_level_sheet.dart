import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/reading_level_service.dart';
import '../../../services/language_detection_service.dart';

// =============================================================================
// 📊 READING LEVEL SHEET — Premium bottom sheet for readability analysis
//
// Displays:
//  - Radial gauge with score + difficulty
//  - Grade level badge
//  - Detailed statistics (words, sentences, syllables)
//  - Formula scores (Flesch, FK-Grade, Gulpease, ARI)
// =============================================================================

class ReadingLevelSheet extends StatelessWidget {
  final ReadingLevelResult result;

  const ReadingLevelSheet._({required this.result});

  /// Show the reading level sheet for the given text.
  static Future<void> show(BuildContext context, String text) {
    HapticFeedback.mediumImpact();

    // Detect language and analyze
    final lang = LanguageDetectionService.instance.detectLanguage(text);
    final result = ReadingLevelService.instance.analyze(
      text,
      languageCode: lang.name,
    );

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReadingLevelSheet._(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[600] : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _difficultyColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.analytics_outlined,
                    color: _difficultyColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reading Level',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '${result.wordCount} words • ${result.sentenceCount} sentences',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Grade badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _difficultyColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _difficultyColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    result.languageCode == 'it'
                        ? result.gradeLabelIT
                        : result.gradeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _difficultyColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 20, endIndent: 20),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                children: [
                  // Radial gauge
                  _buildGauge(isDark),
                  const SizedBox(height: 20),

                  // Stats grid
                  _buildStatsGrid(isDark),
                  const SizedBox(height: 16),

                  // Formula scores
                  _buildFormulaScores(isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color get _difficultyColor => switch (result.difficulty) {
    ReadingDifficulty.veryEasy => const Color(0xFF34C759),
    ReadingDifficulty.easy => const Color(0xFF5AC8FA),
    ReadingDifficulty.moderate => const Color(0xFFFF9500),
    ReadingDifficulty.difficult => const Color(0xFFFF3B30),
    ReadingDifficulty.veryDifficult => const Color(0xFFAF52DE),
  };

  // ── Radial Gauge ───────────────────────────────────────────────────────

  Widget _buildGauge(bool isDark) {
    final score = result.fleschReadingEase;
    final label = result.languageCode == 'it'
        ? result.difficultyLabelIT
        : result.difficultyLabel;

    return SizedBox(
      width: 160,
      height: 160,
      child: CustomPaint(
        painter: _GaugePainter(
          score: score / 100.0,
          color: _difficultyColor,
          isDark: isDark,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${score.round()}',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: _difficultyColor,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stats Grid ─────────────────────────────────────────────────────────

  Widget _buildStatsGrid(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            '${result.avgWordsPerSentence}',
            'Words/Sentence',
            Icons.short_text_rounded,
            isDark,
          ),
          Container(
            width: 1,
            height: 40,
            color: isDark ? Colors.grey[700] : Colors.grey[300],
          ),
          _buildStatItem(
            '${result.avgSyllablesPerWord}',
            'Syllables/Word',
            Icons.text_fields_rounded,
            isDark,
          ),
          Container(
            width: 1,
            height: 40,
            color: isDark ? Colors.grey[700] : Colors.grey[300],
          ),
          _buildStatItem(
            '${result.avgCharactersPerWord}',
            'Chars/Word',
            Icons.abc_rounded,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String value,
    String label,
    IconData icon,
    bool isDark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: isDark ? Colors.grey[500] : Colors.grey[400]),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.grey[500] : Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Formula Scores ─────────────────────────────────────────────────────

  Widget _buildFormulaScores(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Readability Scores',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              letterSpacing: 0.2,
            ),
          ),
        ),
        _buildScoreRow(
          'Flesch Reading Ease',
          result.fleschReadingEase,
          100,
          isDark,
          subtitle: 'Higher = easier to read',
        ),
        const SizedBox(height: 8),
        _buildScoreRow(
          'Flesch-Kincaid Grade',
          result.fleschKincaidGrade,
          20,
          isDark,
          subtitle: 'US school grade level',
          invertColor: true,
        ),
        if (result.languageCode == 'it') ...[
          const SizedBox(height: 8),
          _buildScoreRow(
            'Gulpease (Italian)',
            result.gulpease,
            100,
            isDark,
            subtitle: 'Higher = easier to read',
          ),
        ],
        const SizedBox(height: 8),
        _buildScoreRow(
          'ARI',
          result.ari,
          20,
          isDark,
          subtitle: 'Automated Readability Index',
          invertColor: true,
        ),
      ],
    );
  }

  Widget _buildScoreRow(
    String label,
    double value,
    double maxValue,
    bool isDark, {
    String? subtitle,
    bool invertColor = false,
  }) {
    final progress = (value / maxValue).clamp(0.0, 1.0);
    final barColor = invertColor
        ? Color.lerp(const Color(0xFF34C759), const Color(0xFFFF3B30), progress)!
        : Color.lerp(const Color(0xFFFF3B30), const Color(0xFF34C759), progress)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: barColor,
              ),
            ),
          ],
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 9,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
      ],
    );
  }
}

// ── Gauge Painter ────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  final double score; // 0.0–1.0
  final Color color;
  final bool isDark;

  _GaugePainter({
    required this.score,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const startAngle = math.pi * 0.8;
    const sweepAngle = math.pi * 1.4;

    // Background arc
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.grey.withValues(alpha: 0.15);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Score arc
    final scorePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * score.clamp(0.0, 1.0),
      false,
      scorePaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.score != score || old.color != color;
}
