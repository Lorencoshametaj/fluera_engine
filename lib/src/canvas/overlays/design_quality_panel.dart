import 'package:flutter/material.dart';
import '../../systems/design_linter.dart';

// ============================================================================
// ✅ DESIGN QUALITY PANEL — Lint results and design health check
// ============================================================================

class DesignQualityPanel extends StatelessWidget {
  final List<LintViolation> lintResults;
  const DesignQualityPanel({super.key, required this.lintResults});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final errors =
        lintResults.where((r) => r.severity == LintSeverity.error).length;
    final warnings =
        lintResults.where((r) => r.severity == LintSeverity.warning).length;
    final infos =
        lintResults.where((r) => r.severity == LintSeverity.info).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.8,
      builder:
          (ctx, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        color: cs.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Design Lint',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      if (errors > 0)
                        _SeverityBadge(
                          count: errors,
                          color: Colors.red,
                          label: 'E',
                        ),
                      const SizedBox(width: 6),
                      if (warnings > 0)
                        _SeverityBadge(
                          count: warnings,
                          color: Colors.orange,
                          label: 'W',
                        ),
                      const SizedBox(width: 6),
                      if (infos > 0)
                        _SeverityBadge(
                          count: infos,
                          color: Colors.blue,
                          label: 'I',
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child:
                      lintResults.isEmpty
                          ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 56,
                                  color: Colors.green.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No issues found!',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : ListView.builder(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.all(12),
                            itemCount: lintResults.length,
                            itemBuilder:
                                (ctx, i) => _LintResultTile(
                                  result: lintResults[i],
                                  cs: cs,
                                ),
                          ),
                ),
              ],
            ),
          ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  final int count;
  final Color color;
  final String label;
  const _SeverityBadge({
    required this.count,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count$label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _LintResultTile extends StatelessWidget {
  final LintViolation result;
  final ColorScheme cs;
  const _LintResultTile({required this.result, required this.cs});

  @override
  Widget build(BuildContext context) {
    final color = switch (result.severity) {
      LintSeverity.error => Colors.red,
      LintSeverity.warning => Colors.orange,
      LintSeverity.info => Colors.blue,
    };
    final icon = switch (result.severity) {
      LintSeverity.error => Icons.error_rounded,
      LintSeverity.warning => Icons.warning_rounded,
      LintSeverity.info => Icons.info_rounded,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.ruleId,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.message,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Node: ${result.nodeId}',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
