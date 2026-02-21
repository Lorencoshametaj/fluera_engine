import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🧮 LaTeX Command Reference — Enterprise-grade Material Design 3 cheat sheet.
///
/// Organized by category with tap-to-insert functionality,
/// search filtering, and beautiful grouped layout.
class LatexCommandReference extends StatefulWidget {
  /// Optional callback when a command is selected.
  final void Function(String command)? onCommandSelected;

  const LatexCommandReference({super.key, this.onCommandSelected});

  /// Show as a full-screen modal route.
  static Future<void> show(
    BuildContext context, {
    void Function(String command)? onCommandSelected,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => LatexCommandReference(onCommandSelected: onCommandSelected),
      ),
    );
  }

  @override
  State<LatexCommandReference> createState() => _LatexCommandReferenceState();
}

class _LatexCommandReferenceState extends State<LatexCommandReference>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _categories = <_CommandCategory>[
    _CommandCategory(
      name: 'Functions',
      icon: Icons.functions_rounded,
      commands: [
        _Cmd(r'\log', 'Logarithm', 'log'),
        _Cmd(r'\ln', 'Natural logarithm', 'ln'),
        _Cmd(r'\lg', 'Base-10 logarithm', 'lg'),
        _Cmd(r'\exp', 'Exponential', 'exp'),
        _Cmd(r'\sin', 'Sine', 'sin'),
        _Cmd(r'\cos', 'Cosine', 'cos'),
        _Cmd(r'\tan', 'Tangent', 'tan'),
        _Cmd(r'\cot', 'Cotangent', 'cot'),
        _Cmd(r'\sec', 'Secant', 'sec'),
        _Cmd(r'\csc', 'Cosecant', 'csc'),
        _Cmd(r'\arcsin', 'Arcsine', 'arcsin'),
        _Cmd(r'\arccos', 'Arccosine', 'arccos'),
        _Cmd(r'\arctan', 'Arctangent', 'arctan'),
        _Cmd(r'\sinh', 'Hyperbolic sine', 'sinh'),
        _Cmd(r'\cosh', 'Hyperbolic cosine', 'cosh'),
        _Cmd(r'\tanh', 'Hyperbolic tangent', 'tanh'),
        _Cmd(r'\coth', 'Hyperbolic cotangent', 'coth'),
        _Cmd(r'\min', 'Minimum', 'min'),
        _Cmd(r'\max', 'Maximum', 'max'),
        _Cmd(r'\sup', 'Supremum', 'sup'),
        _Cmd(r'\inf', 'Infimum', 'inf'),
        _Cmd(r'\arg', 'Argument', 'arg'),
        _Cmd(r'\det', 'Determinant', 'det'),
        _Cmd(r'\gcd', 'GCD', 'gcd'),
        _Cmd(r'\deg', 'Degree', 'deg'),
        _Cmd(r'\dim', 'Dimension', 'dim'),
        _Cmd(r'\hom', 'Homomorphism', 'hom'),
        _Cmd(r'\ker', 'Kernel', 'ker'),
        _Cmd(r'\Pr', 'Probability', 'Pr'),
        _Cmd(r'\mod', 'Modulo', 'mod'),
        _Cmd(r'\lim', 'Limit', 'lim'),
        _Cmd(r'\lim_{x \to 0}', 'Limit with variable', 'lim x→0'),
      ],
    ),
    _CommandCategory(
      name: 'Structures',
      icon: Icons.grid_view_rounded,
      commands: [
        _Cmd(r'\frac{a}{b}', 'Fraction', 'a/b'),
        _Cmd(r'\sqrt{x}', 'Square root', '√x'),
        _Cmd(r'\sqrt[n]{x}', 'Nth root', 'ⁿ√x'),
        _Cmd(r'x^{n}', 'Superscript', 'xⁿ'),
        _Cmd(r'x_{i}', 'Subscript', 'xᵢ'),
        _Cmd(r'x_{i}^{n}', 'Sub + superscript', 'xᵢⁿ'),
      ],
    ),
    _CommandCategory(
      name: 'Operators',
      icon: Icons.calculate_rounded,
      commands: [
        _Cmd(r'\int', 'Integral', '∫'),
        _Cmd(r'\int_{a}^{b}', 'Definite integral', '∫ₐᵇ'),
        _Cmd(r'\iint', 'Double integral', '∬'),
        _Cmd(r'\iiint', 'Triple integral', '∭'),
        _Cmd(r'\oint', 'Contour integral', '∮'),
        _Cmd(r'\sum', 'Summation', '∑'),
        _Cmd(r'\sum_{i=1}^{N}', 'Summation with limits', '∑ᵢ₌₁ᴺ'),
        _Cmd(r'\prod', 'Product', '∏'),
        _Cmd(r'\prod_{i=1}^{N}', 'Product with limits', '∏ᵢ₌₁ᴺ'),
      ],
    ),
    _CommandCategory(
      name: 'Greek Letters',
      icon: Icons.language_rounded,
      commands: [
        _Cmd(r'\alpha', 'Alpha', 'α'),
        _Cmd(r'\beta', 'Beta', 'β'),
        _Cmd(r'\gamma', 'Gamma', 'γ'),
        _Cmd(r'\Gamma', 'Gamma (upper)', 'Γ'),
        _Cmd(r'\delta', 'Delta', 'δ'),
        _Cmd(r'\Delta', 'Delta (upper)', 'Δ'),
        _Cmd(r'\epsilon', 'Epsilon', 'ε'),
        _Cmd(r'\zeta', 'Zeta', 'ζ'),
        _Cmd(r'\eta', 'Eta', 'η'),
        _Cmd(r'\theta', 'Theta', 'θ'),
        _Cmd(r'\Theta', 'Theta (upper)', 'Θ'),
        _Cmd(r'\iota', 'Iota', 'ι'),
        _Cmd(r'\kappa', 'Kappa', 'κ'),
        _Cmd(r'\lambda', 'Lambda', 'λ'),
        _Cmd(r'\Lambda', 'Lambda (upper)', 'Λ'),
        _Cmd(r'\mu', 'Mu', 'μ'),
        _Cmd(r'\nu', 'Nu', 'ν'),
        _Cmd(r'\xi', 'Xi', 'ξ'),
        _Cmd(r'\Xi', 'Xi (upper)', 'Ξ'),
        _Cmd(r'\pi', 'Pi', 'π'),
        _Cmd(r'\Pi', 'Pi (upper)', 'Π'),
        _Cmd(r'\rho', 'Rho', 'ρ'),
        _Cmd(r'\sigma', 'Sigma', 'σ'),
        _Cmd(r'\Sigma', 'Sigma (upper)', 'Σ'),
        _Cmd(r'\tau', 'Tau', 'τ'),
        _Cmd(r'\upsilon', 'Upsilon', 'υ'),
        _Cmd(r'\phi', 'Phi', 'φ'),
        _Cmd(r'\Phi', 'Phi (upper)', 'Φ'),
        _Cmd(r'\chi', 'Chi', 'χ'),
        _Cmd(r'\psi', 'Psi', 'ψ'),
        _Cmd(r'\Psi', 'Psi (upper)', 'Ψ'),
        _Cmd(r'\omega', 'Omega', 'ω'),
        _Cmd(r'\Omega', 'Omega (upper)', 'Ω'),
      ],
    ),
    _CommandCategory(
      name: 'Relations',
      icon: Icons.compare_arrows_rounded,
      commands: [
        _Cmd(r'\leq', 'Less or equal', '≤'),
        _Cmd(r'\geq', 'Greater or equal', '≥'),
        _Cmd(r'\neq', 'Not equal', '≠'),
        _Cmd(r'\approx', 'Approximately', '≈'),
        _Cmd(r'\equiv', 'Equivalent', '≡'),
        _Cmd(r'\sim', 'Similar', '∼'),
        _Cmd(r'\propto', 'Proportional', '∝'),
        _Cmd(r'\pm', 'Plus-minus', '±'),
        _Cmd(r'\mp', 'Minus-plus', '∓'),
        _Cmd(r'\times', 'Cross product', '×'),
        _Cmd(r'\div', 'Division', '÷'),
        _Cmd(r'\cdot', 'Dot product', '·'),
        _Cmd(r'\circ', 'Composition', '∘'),
      ],
    ),
    _CommandCategory(
      name: 'Set Theory',
      icon: Icons.hub_rounded,
      commands: [
        _Cmd(r'\in', 'Element of', '∈'),
        _Cmd(r'\notin', 'Not element of', '∉'),
        _Cmd(r'\subset', 'Subset', '⊂'),
        _Cmd(r'\supset', 'Superset', '⊃'),
        _Cmd(r'\cup', 'Union', '∪'),
        _Cmd(r'\cap', 'Intersection', '∩'),
        _Cmd(r'\emptyset', 'Empty set', '∅'),
        _Cmd(r'\forall', 'For all', '∀'),
        _Cmd(r'\exists', 'Exists', '∃'),
        _Cmd(r'\nexists', 'Does not exist', '∄'),
        _Cmd(r'\infty', 'Infinity', '∞'),
        _Cmd(r'\partial', 'Partial derivative', '∂'),
        _Cmd(r'\nabla', 'Nabla (gradient)', '∇'),
      ],
    ),
    _CommandCategory(
      name: 'Arrows',
      icon: Icons.arrow_forward_rounded,
      commands: [
        _Cmd(r'\to', 'Right arrow', '→'),
        _Cmd(r'\rightarrow', 'Right arrow', '→'),
        _Cmd(r'\leftarrow', 'Left arrow', '←'),
        _Cmd(r'\leftrightarrow', 'Bidirectional arrow', '↔'),
        _Cmd(r'\Rightarrow', 'Implies', '⇒'),
        _Cmd(r'\Leftarrow', 'Implied by', '⇐'),
        _Cmd(r'\Leftrightarrow', 'If and only if', '⇔'),
        _Cmd(r'\mapsto', 'Maps to', '↦'),
      ],
    ),
    _CommandCategory(
      name: 'Environments',
      icon: Icons.view_module_rounded,
      commands: [
        _Cmd(r'\left( \right)', 'Auto-sized parens', '( )'),
        _Cmd(r'\left[ \right]', 'Auto-sized brackets', '[ ]'),
        _Cmd(r'\left\{ \right\}', 'Auto-sized braces', '{ }'),
        _Cmd(r'\begin{matrix} a & b \\ c & d \end{matrix}', 'Matrix', 'matrix'),
        _Cmd(
          r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
          'Matrix ( )',
          'pmatrix',
        ),
        _Cmd(
          r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}',
          'Matrix [ ]',
          'bmatrix',
        ),
        _Cmd(
          r'\begin{vmatrix} a & b \\ c & d \end{vmatrix}',
          'Determinant',
          'vmatrix',
        ),
        _Cmd(r'\begin{cases} x & y \\ z & w \end{cases}', 'Cases', 'cases'),
      ],
    ),
    _CommandCategory(
      name: 'Accents',
      icon: Icons.format_overline_rounded,
      commands: [
        _Cmd(r'\hat{x}', 'Hat', 'x̂'),
        _Cmd(r'\bar{x}', 'Bar', 'x̄'),
        _Cmd(r'\vec{x}', 'Vector arrow', 'x⃗'),
        _Cmd(r'\dot{x}', 'Dot above', 'ẋ'),
        _Cmd(r'\ddot{x}', 'Double dot', 'ẍ'),
        _Cmd(r'\tilde{x}', 'Tilde', 'x̃'),
        _Cmd(r'\overline{AB}', 'Overline', 'A̅B̅'),
        _Cmd(r'\widehat{AB}', 'Wide hat', 'ÂB̂'),
      ],
    ),
    _CommandCategory(
      name: 'Fonts',
      icon: Icons.text_fields_rounded,
      commands: [
        _Cmd(r'\mathbb{R}', 'Blackboard bold', 'ℝ'),
        _Cmd(r'\mathbb{N}', 'Natural numbers', 'ℕ'),
        _Cmd(r'\mathbb{Z}', 'Integers', 'ℤ'),
        _Cmd(r'\mathbb{Q}', 'Rationals', 'ℚ'),
        _Cmd(r'\mathbb{C}', 'Complex numbers', 'ℂ'),
        _Cmd(r'\mathcal{A}', 'Calligraphic', '𝒜'),
        _Cmd(r'\mathbf{x}', 'Bold', 'x'),
        _Cmd(r'\mathit{x}', 'Italic', 'x'),
        _Cmd(r'\text{text}', 'Roman text', 'text'),
      ],
    ),
    _CommandCategory(
      name: 'Spacing',
      icon: Icons.space_bar_rounded,
      commands: [
        _Cmd(r'\,', 'Thin space', '(3/18 em)'),
        _Cmd(r'\;', 'Medium space', '(5/18 em)'),
        _Cmd(r'\quad', 'Quad space', '(1 em)'),
        _Cmd(r'\qquad', 'Double quad', '(2 em)'),
        _Cmd(r'\!', 'Negative thin space', '(-3/18 em)'),
      ],
    ),
    _CommandCategory(
      name: 'Dots',
      icon: Icons.more_horiz_rounded,
      commands: [
        _Cmd(r'\ldots', 'Lower dots', '…'),
        _Cmd(r'\cdots', 'Centered dots', '⋯'),
        _Cmd(r'\vdots', 'Vertical dots', '⋮'),
        _Cmd(r'\ddots', 'Diagonal dots', '⋱'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxScrolled) => [
              SliverAppBar.large(
                pinned: true,
                backgroundColor: cs.surface,
                surfaceTintColor: cs.surfaceTint,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('LaTeX Commands'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline_rounded),
                    tooltip: 'Info',
                    onPressed: () => _showInfoDialog(context, cs),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              // Search bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Search commands...',
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.search_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing:
                        _searchQuery.isNotEmpty
                            ? [
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () => _searchController.clear(),
                              ),
                            ]
                            : null,
                    elevation: WidgetStateProperty.all(0),
                    backgroundColor: WidgetStateProperty.all(
                      cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    ),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
              // Tab bar (only when NOT searching)
              if (_searchQuery.isEmpty)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    tabBar: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: cs.outlineVariant.withValues(alpha: 0.3),
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                      tabs:
                          _categories
                              .map(
                                (c) => Tab(
                                  icon: Icon(c.icon, size: 18),
                                  text: c.name,
                                  height: 56,
                                ),
                              )
                              .toList(),
                    ),
                    color: cs.surface,
                  ),
                ),
            ],
        body:
            _searchQuery.isNotEmpty
                ? _buildSearchResults(cs)
                : TabBarView(
                  controller: _tabController,
                  children:
                      _categories
                          .map((cat) => _buildCategoryGrid(cat, cs))
                          .toList(),
                ),
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme cs) {
    final allCmds = <_Cmd>[];
    for (final cat in _categories) {
      for (final cmd in cat.commands) {
        if (cmd.latex.toLowerCase().contains(_searchQuery) ||
            cmd.description.toLowerCase().contains(_searchQuery) ||
            cmd.preview.toLowerCase().contains(_searchQuery)) {
          allCmds.add(cmd);
        }
      }
    }

    if (allCmds.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "$_searchQuery"',
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: allCmds.length,
      itemBuilder: (context, index) => _buildCommandTile(allCmds[index], cs),
    );
  }

  Widget _buildCategoryGrid(_CommandCategory category, ColorScheme cs) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.6,
      ),
      itemCount: category.commands.length,
      itemBuilder:
          (context, index) => _buildCommandCard(category.commands[index], cs),
    );
  }

  Widget _buildCommandCard(_Cmd cmd, ColorScheme cs) {
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onCommandTap(cmd, cs),
        onLongPress: () => _onCommandLongPress(cmd),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Preview symbol
              Text(
                cmd.preview,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  color: cs.primary,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // LaTeX source
              Text(
                cmd.latex,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Description
              Text(
                cmd.description,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommandTile(_Cmd cmd, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _onCommandTap(cmd, cs),
          onLongPress: () => _onCommandLongPress(cmd),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Preview
                SizedBox(
                  width: 40,
                  child: Text(
                    cmd.preview,
                    style: TextStyle(fontSize: 20, color: cs.primary),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 16),
                // Command + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cmd.latex,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cmd.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Copy icon
                Icon(
                  Icons.content_copy_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCommandTap(_Cmd cmd, ColorScheme cs) {
    HapticFeedback.selectionClick();
    if (widget.onCommandSelected != null) {
      widget.onCommandSelected!(cmd.latex);
      Navigator.of(context).pop();
    } else {
      Clipboard.setData(ClipboardData(text: cmd.latex));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Text(cmd.preview, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${cmd.latex} copied',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _onCommandLongPress(_Cmd cmd) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: cmd.latex));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${cmd.latex} copied to clipboard',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, ColorScheme cs) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.functions_rounded),
                SizedBox(width: 12),
                Text('LaTeX Engine'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nebula Engine — Native LaTeX Renderer',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fully native rendering with zero external dependencies.\n'
                  'Parser → AST → Layout Engine → Canvas.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  label: 'Supported commands',
                  value:
                      '${_categories.fold<int>(0, (s, c) => s + c.commands.length)}',
                ),
                _InfoRow(label: 'Categories', value: '${_categories.length}'),
                const _InfoRow(label: 'External deps', value: '0'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

class _Cmd {
  final String latex;
  final String description;
  final String preview;

  const _Cmd(this.latex, this.description, this.preview);
}

class _CommandCategory {
  final String name;
  final IconData icon;
  final List<_Cmd> commands;

  const _CommandCategory({
    required this.name,
    required this.icon,
    required this.commands,
  });
}

// ─── Tab Bar Delegate ────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color color;

  _TabBarDelegate({required this.tabBar, required this.color});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: color, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar || color != oldDelegate.color;
}

// ─── Info Row ────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
