import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// 🛠️ DEV HANDOFF PANEL — Inspect, measure, generate code
// ============================================================================

class DevHandoffPanel extends StatefulWidget {
  const DevHandoffPanel({super.key});

  @override
  State<DevHandoffPanel> createState() => _DevHandoffPanelState();
}

class _DevHandoffPanelState extends State<DevHandoffPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFormat = 'Flutter';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.9,
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
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.code_rounded, color: cs.primary, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Dev Handoff',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Inspect'),
                    Tab(text: 'Code'),
                    Tab(text: 'Assets'),
                  ],
                  labelColor: cs.primary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: cs.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildInspectTab(cs),
                      _buildCodeTab(cs),
                      _buildAssetsTab(cs),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildInspectTab(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PropertyRow('Width', '375.0', cs),
          _PropertyRow('Height', '812.0', cs),
          _PropertyRow('X', '0.0', cs),
          _PropertyRow('Y', '0.0', cs),
          const Divider(height: 24),
          _PropertyRow('Background', '#FFFFFF', cs),
          _PropertyRow('Border Radius', '12.0', cs),
          _PropertyRow('Opacity', '1.0', cs),
        ],
      ),
    );
  }

  Widget _buildCodeTab(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final fmt in ['Flutter', 'CSS', 'SwiftUI']) ...[
                ChoiceChip(
                  label: Text(fmt),
                  selected: _selectedFormat == fmt,
                  onSelected: (s) => setState(() => _selectedFormat = fmt),
                  selectedColor: cs.primaryContainer,
                  labelStyle: TextStyle(
                    color:
                        _selectedFormat == fmt
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedFormat,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _getCodePreview()),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      },
                    ),
                  ],
                ),
                Text(
                  _getCodePreview(),
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurface,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCodePreview() => switch (_selectedFormat) {
    'Flutter' =>
      'Container(\n  width: 375,\n  height: 812,\n  decoration: BoxDecoration(\n    color: Colors.white,\n    borderRadius: BorderRadius.circular(12),\n  ),\n)',
    'CSS' =>
      '.element {\n  width: 375px;\n  height: 812px;\n  background: #FFFFFF;\n  border-radius: 12px;\n}',
    'SwiftUI' =>
      'RoundedRectangle(cornerRadius: 12)\n  .fill(Color.white)\n  .frame(width: 375, height: 812)',
    _ => '',
  };

  Widget _buildAssetsTab(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_rounded,
            size: 56,
            color: cs.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No exportable assets',
            style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _PropertyRow(this.label, this.value, this.cs);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
