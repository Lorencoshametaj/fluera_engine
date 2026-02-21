import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🧮 LatexSymbolPalette — Enterprise-grade Material Design 3 searchable
/// symbol grid.
///
/// ## Enterprise Features
/// - **E13** Recent symbols tab (last 12 used, auto-tracked)
/// - **E14** Expanded symbol set: Logic and Matrices categories
/// - **E15** Long-press tooltip with both Unicode display and LaTeX command
///
/// Organized by category with a search field and horizontal category chips.
/// Tapping a symbol invokes [onSymbolSelected] with the LaTeX command string.
class LatexSymbolPalette extends StatefulWidget {
  /// Called when the user selects a symbol.
  final ValueChanged<String> onSymbolSelected;

  const LatexSymbolPalette({super.key, required this.onSymbolSelected});

  @override
  State<LatexSymbolPalette> createState() => _LatexSymbolPaletteState();
}

class _LatexSymbolPaletteState extends State<LatexSymbolPalette> {
  String _search = '';
  int _selectedCategory = 0;

  // E13: Recent symbols (static so it persists across rebuilds)
  static final List<_Symbol> _recentSymbols = [];

  void _onSymbolTap(_Symbol sym) {
    HapticFeedback.selectionClick(); // E6 (from editor sheet)

    // E13: Track recent
    _recentSymbols.remove(sym);
    _recentSymbols.insert(0, sym);
    if (_recentSymbols.length > 12) _recentSymbols.removeLast();

    widget.onSymbolSelected(sym.latex);
    setState(() {}); // Refresh recent count
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allCategories = _buildCategories();
    final filtered = _getFilteredSymbols(allCategories);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Cerca simbolo...',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: TextStyle(fontSize: 14, color: cs.onSurface),
          ),
        ),

        // Category chips
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: allCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == _selectedCategory;
              final cat = allCategories[i];
              return FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(cat.name, style: const TextStyle(fontSize: 12)),
                    // E13: Badge for recents count
                    if (cat.name == 'Recenti' && _recentSymbols.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_recentSymbols.length}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                selected: selected,
                onSelected: (_) => setState(() => _selectedCategory = i),
                showCheckmark: false,
                selectedColor: cs.primaryContainer,
                backgroundColor: cs.surfaceContainerLow,
                labelStyle: TextStyle(
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Symbol grid
        Expanded(
          child:
              filtered.isEmpty
                  ? Center(
                    child: Text(
                      'Nessun simbolo trovato',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  )
                  : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1.0,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final sym = filtered[i];
                      return _SymbolButton(
                        display: sym.display,
                        latex: sym.latex,
                        label: sym.label,
                        onTap: () => _onSymbolTap(sym),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  // E13: Build categories with "Recenti" prepended if non-empty
  List<_Category> _buildCategories() {
    if (_recentSymbols.isEmpty) return _categories;
    return [
      _Category('Recenti', List.unmodifiable(_recentSymbols)),
      ..._categories,
    ];
  }

  List<_Symbol> _getFilteredSymbols(List<_Category> categories) {
    final safeIndex = _selectedCategory.clamp(0, categories.length - 1);
    final category = categories[safeIndex];
    if (_search.isEmpty) return category.symbols;
    final q = _search.toLowerCase();
    return category.symbols
        .where(
          (s) =>
              s.display.toLowerCase().contains(q) ||
              s.latex.toLowerCase().contains(q) ||
              (s.label?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }
}

// E15: Enhanced symbol button with long-press tooltip
class _SymbolButton extends StatelessWidget {
  final String display;
  final String latex;
  final String? label;
  final VoidCallback onTap;

  const _SymbolButton({
    required this.display,
    required this.latex,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      // E15: Richer tooltip with both display and command
      richMessage: TextSpan(
        children: [
          TextSpan(text: '$display\n', style: const TextStyle(fontSize: 18)),
          TextSpan(
            text: latex,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
          if (label != null) ...[
            const TextSpan(text: '\n'),
            TextSpan(
              text: label!,
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
      preferBelow: false,
      // E15: Show on long-press (default)
      triggerMode: TooltipTriggerMode.longPress,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              display,
              style: TextStyle(fontSize: 18, color: cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _Symbol {
  final String display;
  final String latex;
  final String? label;
  const _Symbol(this.display, this.latex, [this.label]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _Symbol && latex == other.latex;

  @override
  int get hashCode => latex.hashCode;
}

class _Category {
  final String name;
  final List<_Symbol> symbols;
  const _Category(this.name, this.symbols);
}

const _categories = [
  _Category('Greci', [
    _Symbol('α', r'\alpha', 'alpha'),
    _Symbol('β', r'\beta', 'beta'),
    _Symbol('γ', r'\gamma', 'gamma'),
    _Symbol('δ', r'\delta', 'delta'),
    _Symbol('ε', r'\epsilon', 'epsilon'),
    _Symbol('ζ', r'\zeta', 'zeta'),
    _Symbol('η', r'\eta', 'eta'),
    _Symbol('θ', r'\theta', 'theta'),
    _Symbol('ι', r'\iota', 'iota'),
    _Symbol('κ', r'\kappa', 'kappa'),
    _Symbol('λ', r'\lambda', 'lambda'),
    _Symbol('μ', r'\mu', 'mu'),
    _Symbol('ν', r'\nu', 'nu'),
    _Symbol('ξ', r'\xi', 'xi'),
    _Symbol('π', r'\pi', 'pi'),
    _Symbol('ρ', r'\rho', 'rho'),
    _Symbol('σ', r'\sigma', 'sigma'),
    _Symbol('τ', r'\tau', 'tau'),
    _Symbol('υ', r'\upsilon', 'upsilon'),
    _Symbol('φ', r'\phi', 'phi'),
    _Symbol('χ', r'\chi', 'chi'),
    _Symbol('ψ', r'\psi', 'psi'),
    _Symbol('ω', r'\omega', 'omega'),
    _Symbol('Γ', r'\Gamma'),
    _Symbol('Δ', r'\Delta'),
    _Symbol('Θ', r'\Theta'),
    _Symbol('Λ', r'\Lambda'),
    _Symbol('Ξ', r'\Xi'),
    _Symbol('Π', r'\Pi'),
    _Symbol('Σ', r'\Sigma'),
    _Symbol('Φ', r'\Phi'),
    _Symbol('Ψ', r'\Psi'),
    _Symbol('Ω', r'\Omega'),
  ]),
  _Category('Operatori', [
    _Symbol('+', '+'),
    _Symbol('−', '-'),
    _Symbol('×', r'\times', 'times'),
    _Symbol('÷', r'\div', 'divide'),
    _Symbol('·', r'\cdot', 'center dot'),
    _Symbol('±', r'\pm', 'plus minus'),
    _Symbol('∓', r'\mp', 'minus plus'),
    _Symbol('∘', r'\circ', 'circle'),
    _Symbol('∪', r'\cup', 'union'),
    _Symbol('∩', r'\cap', 'intersection'),
    _Symbol('⊕', r'\oplus', 'direct sum'),
    _Symbol('⊗', r'\otimes', 'tensor product'),
  ]),
  _Category('Relazioni', [
    _Symbol('=', '='),
    _Symbol('≠', r'\neq', 'not equal'),
    _Symbol('<', '<'),
    _Symbol('>', '>'),
    _Symbol('≤', r'\leq', 'less or equal'),
    _Symbol('≥', r'\geq', 'greater or equal'),
    _Symbol('≈', r'\approx', 'approximately'),
    _Symbol('≡', r'\equiv', 'equivalent'),
    _Symbol('∼', r'\sim', 'similar'),
    _Symbol('∝', r'\propto', 'proportional'),
    _Symbol('∈', r'\in', 'element of'),
    _Symbol('∉', r'\notin', 'not element of'),
    _Symbol('⊂', r'\subset', 'subset'),
    _Symbol('⊃', r'\supset', 'superset'),
    _Symbol('⊆', r'\subseteq', 'subset or equal'),
    _Symbol('⊇', r'\supseteq', 'superset or equal'),
  ]),
  _Category('Frecce', [
    _Symbol('→', r'\rightarrow', 'right arrow'),
    _Symbol('←', r'\leftarrow', 'left arrow'),
    _Symbol('↔', r'\leftrightarrow', 'left-right arrow'),
    _Symbol('⇒', r'\Rightarrow', 'implies'),
    _Symbol('⇐', r'\Leftarrow', 'implied by'),
    _Symbol('⇔', r'\Leftrightarrow', 'if and only if'),
    _Symbol('↦', r'\mapsto', 'maps to'),
    _Symbol('↑', r'\uparrow', 'up arrow'),
    _Symbol('↓', r'\downarrow', 'down arrow'),
  ]),
  _Category('Strutture', [
    _Symbol('a/b', r'\frac{}{}', 'fraction'),
    _Symbol('√', r'\sqrt{}', 'square root'),
    _Symbol('∫', r'\int', 'integral'),
    _Symbol('∑', r'\sum', 'sum'),
    _Symbol('∏', r'\prod', 'product'),
    _Symbol('lim', r'\lim', 'limit'),
    _Symbol('∂', r'\partial', 'partial'),
    _Symbol('∇', r'\nabla', 'nabla'),
    _Symbol('∞', r'\infty', 'infinity'),
    _Symbol('…', r'\ldots', 'dots'),
    _Symbol('⋯', r'\cdots', 'center dots'),
    _Symbol('∅', r'\emptyset', 'empty set'),
  ]),
  _Category('Accenti', [
    _Symbol('x̂', r'\hat{}', 'hat'),
    _Symbol('x̄', r'\bar{}', 'bar'),
    _Symbol('x⃗', r'\vec{}', 'vector'),
    _Symbol('ẋ', r'\dot{}', 'dot'),
    _Symbol('ẍ', r'\ddot{}', 'double dot'),
    _Symbol('x̃', r'\tilde{}', 'tilde'),
    _Symbol('x̅', r'\overline{}', 'overline'),
    _Symbol('x̲', r'\underline{}', 'underline'),
  ]),
  // E14: New — Logic symbols
  _Category('Logica', [
    _Symbol('∀', r'\forall', 'for all'),
    _Symbol('∃', r'\exists', 'exists'),
    _Symbol('∄', r'\nexists', 'not exists'),
    _Symbol('¬', r'\neg', 'negation'),
    _Symbol('∧', r'\land', 'logical and'),
    _Symbol('∨', r'\lor', 'logical or'),
    _Symbol('⟹', r'\implies', 'implies'),
    _Symbol('⟺', r'\iff', 'if and only if'),
    _Symbol('∴', r'\therefore', 'therefore'),
    _Symbol('∵', r'\because', 'because'),
    _Symbol('⊤', r'\top', 'top/true'),
    _Symbol('⊥', r'\bot', 'bottom/false'),
    _Symbol('⊢', r'\vdash', 'proves'),
    _Symbol('⊨', r'\models', 'models'),
  ]),
  // E14: New — Matrix environments
  _Category('Matrici', [
    _Symbol('[M]', r'\begin{matrix}  \\  \end{matrix}', 'plain matrix'),
    _Symbol('(M)', r'\begin{pmatrix}  \\  \end{pmatrix}', 'parenthesized'),
    _Symbol('[M]', r'\begin{bmatrix}  \\  \end{bmatrix}', 'bracketed'),
    _Symbol('|M|', r'\begin{vmatrix}  \\  \end{vmatrix}', 'determinant'),
    _Symbol('‖M‖', r'\begin{Vmatrix}  \\  \end{Vmatrix}', 'double bars'),
    _Symbol('{M}', r'\begin{Bmatrix}  \\  \end{Bmatrix}', 'braced'),
    _Symbol(
      '2×2',
      r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
      '2x2 matrix',
    ),
    _Symbol(
      '3×3',
      r'\begin{pmatrix} a & b & c \\ d & e & f \\ g & h & i \end{pmatrix}',
      '3x3 matrix',
    ),
    _Symbol(
      'I₂',
      r'\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}',
      'identity 2x2',
    ),
    _Symbol(
      'I₃',
      r'\begin{pmatrix} 1 & 0 & 0 \\ 0 & 1 & 0 \\ 0 & 0 & 1 \end{pmatrix}',
      'identity 3x3',
    ),
  ]),
];
