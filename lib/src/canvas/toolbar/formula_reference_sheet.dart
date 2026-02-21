import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 📊 Formula Reference Sheet — enterprise-grade function reference.
///
/// Shows all available spreadsheet functions organized by category,
/// with syntax, description, and tap-to-insert functionality.
class FormulaReferenceSheet extends StatefulWidget {
  /// Called when the user taps a function to insert it.
  final ValueChanged<String>? onInsertFormula;
  final ScrollController? scrollController;

  const FormulaReferenceSheet({
    super.key,
    this.onInsertFormula,
    this.scrollController,
  });

  /// Show as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    ValueChanged<String>? onInsertFormula,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (context, scrollController) => FormulaReferenceSheet(
                  scrollController: scrollController,
                  onInsertFormula: onInsertFormula,
                ),
          ),
    );
  }

  @override
  State<FormulaReferenceSheet> createState() => _FormulaReferenceSheetState();
}

class _FormulaReferenceSheetState extends State<FormulaReferenceSheet> {
  String _searchQuery = '';
  String? _expandedCategory;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // FORMULA DATABASE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  static const _categories = <_FormulaCategory>[
    _FormulaCategory(
      name: 'Math & Statistics',
      icon: Icons.calculate_rounded,
      color: Color(0xFF4285F4),
      formulas: [
        _FormulaInfo('SUM', 'SUM(A1:A10)', 'Sum of values in a range'),
        _FormulaInfo(
          'AVERAGE',
          'AVERAGE(A1:A10)',
          'Average of values in a range',
        ),
        _FormulaInfo('MIN', 'MIN(A1:A10)', 'Smallest value in a range'),
        _FormulaInfo('MAX', 'MAX(A1:A10)', 'Largest value in a range'),
        _FormulaInfo('ABS', 'ABS(A1)', 'Absolute value of a number'),
        _FormulaInfo('ROUND', 'ROUND(A1, 2)', 'Round to N decimal places'),
        _FormulaInfo('FLOOR', 'FLOOR(A1)', 'Round down to nearest integer'),
        _FormulaInfo('CEIL', 'CEIL(A1)', 'Round up to nearest integer'),
        _FormulaInfo('SQRT', 'SQRT(A1)', 'Square root of a number'),
        _FormulaInfo('POWER', 'POWER(A1, 2)', 'Raise a number to a power'),
        _FormulaInfo('MOD', 'MOD(A1, 3)', 'Remainder after division'),
        _FormulaInfo('PI', 'PI()', 'The constant π (3.14159…)'),
        _FormulaInfo('LOG', 'LOG(A1, 10)', 'Logarithm with base'),
        _FormulaInfo('LN', 'LN(A1)', 'Natural logarithm'),
        _FormulaInfo(
          'ROUNDDOWN',
          'ROUNDDOWN(A1, 2)',
          'Truncate toward zero at N decimals',
        ),
        _FormulaInfo(
          'ROUNDUP',
          'ROUNDUP(A1, 2)',
          'Round away from zero at N decimals',
        ),
        _FormulaInfo(
          'SUMPRODUCT',
          'SUMPRODUCT(A1:A10)',
          'Sum of element-wise products',
        ),
        _FormulaInfo('MEDIAN', 'MEDIAN(A1:A10)', 'Middle value of a dataset'),
        _FormulaInfo('STDEV', 'STDEV(A1:A10)', 'Sample standard deviation'),
        _FormulaInfo('LARGE', 'LARGE(A1:A10, 2)', 'Kth largest value in range'),
        _FormulaInfo(
          'SMALL',
          'SMALL(A1:A10, 2)',
          'Kth smallest value in range',
        ),
      ],
    ),
    _FormulaCategory(
      name: 'Logic',
      icon: Icons.call_split_rounded,
      color: Color(0xFF34A853),
      formulas: [
        _FormulaInfo(
          'IF',
          'IF(A1>10, "Yes", "No")',
          'Conditional: if-then-else',
        ),
        _FormulaInfo('AND', 'AND(A1>0, B1>0)', 'TRUE if all args are true'),
        _FormulaInfo('OR', 'OR(A1>0, B1>0)', 'TRUE if any arg is true'),
        _FormulaInfo('NOT', 'NOT(A1)', 'Invert a boolean value'),
        _FormulaInfo(
          'IFERROR',
          'IFERROR(A1, "fallback")',
          'Return fallback value if error, else value',
        ),
        _FormulaInfo(
          'CHOOSE',
          'CHOOSE(2, "A", "B", "C")',
          'Pick the Nth value from a list',
        ),
      ],
    ),
    _FormulaCategory(
      name: 'Text',
      icon: Icons.text_fields_rounded,
      color: Color(0xFFFBBC04),
      formulas: [
        _FormulaInfo('LEN', 'LEN(A1)', 'Length of a text string'),
        _FormulaInfo('UPPER', 'UPPER(A1)', 'Convert text to UPPERCASE'),
        _FormulaInfo('LOWER', 'LOWER(A1)', 'Convert text to lowercase'),
        _FormulaInfo(
          'CONCATENATE',
          'CONCATENATE(A1, " ", B1)',
          'Join text strings together',
        ),
        _FormulaInfo('LEFT', 'LEFT(A1, 3)', 'First N characters of text'),
        _FormulaInfo('RIGHT', 'RIGHT(A1, 3)', 'Last N characters of text'),
        _FormulaInfo('MID', 'MID(A1, 2, 3)', 'Extract substring from position'),
        _FormulaInfo('TRIM', 'TRIM(A1)', 'Remove extra whitespace'),
        _FormulaInfo(
          'FIND',
          'FIND("text", A1)',
          'Find position of text (1-indexed)',
        ),
        _FormulaInfo(
          'SUBSTITUTE',
          'SUBSTITUTE(A1, "old", "new")',
          'Replace occurrences of text',
        ),
        _FormulaInfo(
          'TEXT',
          'TEXT(A1, "0.00")',
          'Format number as text with pattern',
        ),
        _FormulaInfo('VALUE', 'VALUE(A1)', 'Convert text to number'),
      ],
    ),
    _FormulaCategory(
      name: 'Lookup & Reference',
      icon: Icons.search_rounded,
      color: Color(0xFF00BCD4),
      formulas: [
        _FormulaInfo(
          'VLOOKUP',
          'VLOOKUP(A1, B1:D10, 2, FALSE)',
          'Vertical lookup: search first column, return from another',
        ),
        _FormulaInfo(
          'HLOOKUP',
          'HLOOKUP(A1, B1:D10, 2, FALSE)',
          'Horizontal lookup: search first row, return from another',
        ),
        _FormulaInfo(
          'INDEX',
          'INDEX(A1:C10, 3, 2)',
          'Return value at specific row and column in range',
        ),
        _FormulaInfo(
          'MATCH',
          'MATCH(A1, B1:B10, 0)',
          'Find position of a value in a range',
        ),
        _FormulaInfo(
          'RANK',
          'RANK(A1, B1:B10, 0)',
          'Rank of value in range (0=desc, 1=asc)',
        ),
      ],
    ),
    _FormulaCategory(
      name: 'Counting',
      icon: Icons.tag_rounded,
      color: Color(0xFFEA4335),
      formulas: [
        _FormulaInfo('COUNT', 'COUNT(A1:A10)', 'Count cells with numbers'),
        _FormulaInfo('COUNTA', 'COUNTA(A1:A10)', 'Count non-empty cells'),
        _FormulaInfo('COUNTBLANK', 'COUNTBLANK(A1:A10)', 'Count empty cells'),
        _FormulaInfo(
          'COUNTIF',
          'COUNTIF(A1:A10, ">5")',
          'Count cells matching criteria',
        ),
      ],
    ),
    _FormulaCategory(
      name: 'Conditional Aggregation',
      icon: Icons.filter_alt_rounded,
      color: Color(0xFFFF5722),
      formulas: [
        _FormulaInfo(
          'SUMIF',
          'SUMIF(A1:A10, "A", B1:B10)',
          'Sum values where criteria matches',
        ),
        _FormulaInfo(
          'AVERAGEIF',
          'AVERAGEIF(A1:A10, ">5", B1:B10)',
          'Average values where criteria matches',
        ),
      ],
    ),
    _FormulaCategory(
      name: 'Date & Time',
      icon: Icons.calendar_today_rounded,
      color: Color(0xFF795548),
      formulas: [
        _FormulaInfo('TODAY', 'TODAY()', 'Current date as serial number'),
        _FormulaInfo('NOW', 'NOW()', 'Current date and time as serial'),
        _FormulaInfo('YEAR', 'YEAR(A1)', 'Extract year from serial date'),
        _FormulaInfo('MONTH', 'MONTH(A1)', 'Extract month from serial date'),
        _FormulaInfo('DAY', 'DAY(A1)', 'Extract day from serial date'),
        _FormulaInfo(
          'DATE',
          'DATE(2024, 1, 15)',
          'Create serial date from year, month, day',
        ),
      ],
    ),
    _FormulaCategory(
      name: 'Information',
      icon: Icons.info_outline_rounded,
      color: Color(0xFF9C27B0),
      formulas: [
        _FormulaInfo('ISBLANK', 'ISBLANK(A1)', 'TRUE if cell is empty'),
        _FormulaInfo(
          'ISNUMBER',
          'ISNUMBER(A1)',
          'TRUE if cell contains a number',
        ),
        _FormulaInfo('ISTEXT', 'ISTEXT(A1)', 'TRUE if cell contains text'),
        _FormulaInfo('ISERROR', 'ISERROR(A1)', 'TRUE if cell has an error'),
      ],
    ),
    _FormulaCategory(
      name: 'Operators',
      icon: Icons.compare_arrows_rounded,
      color: Color(0xFF607D8B),
      formulas: [
        _FormulaInfo('+', 'A1 + B1', 'Addition'),
        _FormulaInfo('-', 'A1 - B1', 'Subtraction'),
        _FormulaInfo('*', 'A1 * B1', 'Multiplication'),
        _FormulaInfo('/', 'A1 / B1', 'Division'),
        _FormulaInfo('>', 'A1 > B1', 'Greater than'),
        _FormulaInfo('<', 'A1 < B1', 'Less than'),
        _FormulaInfo('>=', 'A1 >= B1', 'Greater than or equal'),
        _FormulaInfo('<=', 'A1 <= B1', 'Less than or equal'),
        _FormulaInfo('=', 'A1 = B1', 'Equals comparison'),
        _FormulaInfo('<>', 'A1 <> B1', 'Not equal'),
        _FormulaInfo('A1:C5', 'SUM(A1:C5)', 'Cell range reference'),
      ],
    ),
  ];

  List<_FormulaCategory> get _filteredCategories {
    if (_searchQuery.isEmpty) return _categories;
    final q = _searchQuery.toUpperCase();
    return _categories
        .map((cat) {
          final filtered =
              cat.formulas
                  .where(
                    (f) =>
                        f.name.toUpperCase().contains(q) ||
                        f.description.toUpperCase().contains(q),
                  )
                  .toList();
          return filtered.isEmpty ? null : cat.copyWith(formulas: filtered);
        })
        .whereType<_FormulaCategory>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categories = _filteredCategories;

    return Column(
      children: [
        // ── Handle bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── Header ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.tertiary.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'fx',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Formula Reference',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      '${_categories.fold<int>(0, (s, c) => s + c.formulas.length)} functions available',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Close button
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // ── Search bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search functions…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor:
                  isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),

        const Divider(height: 1),

        // ── Categories list ──────────────────────────────────────────
        Expanded(
          child:
              categories.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No functions match "$_searchQuery"',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final isExpanded =
                          _expandedCategory == cat.name ||
                          _searchQuery.isNotEmpty;
                      return _buildCategory(context, cat, isExpanded);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildCategory(
    BuildContext context,
    _FormulaCategory category,
    bool isExpanded,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        InkWell(
          onTap: () {
            setState(() {
              _expandedCategory =
                  _expandedCategory == category.name ? null : category.name;
            });
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(category.icon, size: 18, color: category.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Text(
                  '${category.formulas.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Formula list
        if (isExpanded)
          ...category.formulas.map((f) => _buildFormulaItem(context, f)),
      ],
    );
  }

  Widget _buildFormulaItem(BuildContext context, _FormulaInfo formula) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        // Insert formula with = prefix
        final insertion =
            formula.name.contains(RegExp(r'[<>=+\-*/:]'))
                ? '=${formula.syntax}'
                : '=${formula.name}(';
        widget.onInsertFormula?.call(insertion);
        HapticFeedback.selectionClick();
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(52, 6, 16, 6),
        child: Row(
          children: [
            // Function signature
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + syntax
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: formula.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Syntax example
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isDark
                              ? cs.surfaceContainerHighest
                              : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '=${formula.syntax}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Description
                  Text(
                    formula.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Insert arrow
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DATA MODELS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _FormulaCategory {
  final String name;
  final IconData icon;
  final Color color;
  final List<_FormulaInfo> formulas;

  const _FormulaCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.formulas,
  });

  _FormulaCategory copyWith({List<_FormulaInfo>? formulas}) {
    return _FormulaCategory(
      name: name,
      icon: icon,
      color: color,
      formulas: formulas ?? this.formulas,
    );
  }
}

class _FormulaInfo {
  final String name;
  final String syntax;
  final String description;

  const _FormulaInfo(this.name, this.syntax, this.description);
}
