import '../../core/modules/canvas_module.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../base/tool_interface.dart';

// =============================================================================
// PDF MODULE
// =============================================================================

/// 📄 Self-contained PDF module for the Nebula Engine canvas.
///
/// Encapsulates all PDF functionality:
/// - [PdfPageNode]: scene graph node for a single PDF page
/// - [PdfDocumentNode]: group node containing ordered PDF pages
/// - PDF tools (grid, text selection, search, annotations, import)
/// - PDF export (writer, annotation exporter)
///
/// ## Usage
///
/// ```dart
/// await EngineScope.current.moduleRegistry.register(PDFModule());
///
/// final pdf = EngineScope.current.moduleRegistry.findModule<PDFModule>()!;
/// ```
class PDFModule extends CanvasModule {
  @override
  String get moduleId => 'pdf';

  @override
  String get displayName => 'PDF';

  @override
  List<NodeDescriptor> get nodeDescriptors => [
    NodeDescriptor(
      nodeType: 'pdfPage',
      fromJson: PdfPageNode.fromJson,
      displayName: 'PDF Page',
    ),
    NodeDescriptor(
      nodeType: 'pdfDocument',
      fromJson: PdfDocumentNode.fromJson,
      displayName: 'PDF Document',
    ),
  ];

  @override
  List<DrawingTool> createTools() => const [];

  @override
  bool get isInitialized => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize(ModuleContext context) async {
    if (_initialized) return;
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
