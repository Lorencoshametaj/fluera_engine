import '../modules/canvas_module.dart';
import '../nodes/tabular_node.dart';
import '../tabular/spreadsheet_model.dart';
import '../tabular/spreadsheet_evaluator.dart';
import '../tabular/tabular_latex_bridge.dart';
import '../scene_graph/invalidation_graph.dart';
import '../../tools/base/tool_interface.dart';
import '../../tools/tabular/tabular_tool.dart';

// =============================================================================
// TABULAR MODULE
// =============================================================================

/// 📊 Self-contained spreadsheet module for the Fluera Engine canvas.
///
/// Encapsulates all tabular functionality:
/// - [SpreadsheetModel]: sparse cell storage with formulas
/// - [SpreadsheetEvaluator]: formula evaluation engine
/// - [TabularLatexBridge]: reactive cell → LaTeX substitution
/// - [TabularTool]: interactive cell selection and editing
/// - [TabularNode]: scene graph node type
///
/// ## Usage
///
/// ```dart
/// final scope = EngineScope.current;
/// await scope.moduleRegistry.register(TabularModule());
///
/// // Access module internals
/// final tabular = scope.moduleRegistry.findModule<TabularModule>()!;
/// print(tabular.spreadsheetModel.cellCount);
/// ```
class TabularModule extends CanvasModule {
  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  @override
  String get moduleId => 'tabular';

  @override
  String get displayName => 'Spreadsheet';

  // ---------------------------------------------------------------------------
  // Module-owned services
  // ---------------------------------------------------------------------------

  /// Global spreadsheet model shared across all tabular nodes in this scope.
  late final SpreadsheetModel spreadsheetModel;

  /// Formula evaluator for the spreadsheet model.
  late final SpreadsheetEvaluator spreadsheetEvaluator;

  /// Reactive bridge: cell changes → LaTeX node re-rendering.
  late final TabularLatexBridge tabularLatexBridge;

  // ---------------------------------------------------------------------------
  // CanvasModule contract
  // ---------------------------------------------------------------------------

  @override
  List<NodeDescriptor> get nodeDescriptors => [
    NodeDescriptor(
      nodeType: 'tabular',
      fromJson: TabularNode.fromJson,
      displayName: 'Table',
    ),
  ];

  @override
  List<DrawingTool> createTools() => [TabularTool()];

  @override
  bool get isInitialized => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize(ModuleContext context) async {
    if (_initialized) return;

    spreadsheetModel = SpreadsheetModel();
    spreadsheetEvaluator = SpreadsheetEvaluator(spreadsheetModel);

    // TabularLatexBridge needs the InvalidationGraph from the scope
    final invalidationGraph =
        (context.scope as dynamic).invalidationGraph as InvalidationGraph;
    tabularLatexBridge = TabularLatexBridge(
      spreadsheetEvaluator,
      invalidationGraph,
    );

    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    tabularLatexBridge.dispose();
    spreadsheetEvaluator.dispose();
    _initialized = false;
  }
}
