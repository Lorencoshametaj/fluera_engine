import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/models/pdf_page_model.dart';
import '../../core/models/pdf_document_model.dart';
import '../../canvas/nebula_canvas_config.dart';

/// 📥 Controller for importing PDF documents onto the canvas.
///
/// Orchestrates the full import pipeline:
/// 1. Accept raw PDF bytes
/// 2. Load via [NebulaPdfProvider]
/// 3. Create [PdfDocumentNode] with child [PdfPageNode]s
/// 4. Insert into the scene graph at the specified position
///
/// This controller does NOT handle file picking — that's the host app's
/// responsibility. It only processes bytes → scene graph nodes.
class PdfImportController {
  final NebulaPdfProvider? _provider;

  PdfImportController({NebulaPdfProvider? provider}) : _provider = provider;

  /// Whether PDF import is available (provider is configured).
  bool get isAvailable => _provider != null;

  /// Import a PDF document from raw bytes.
  ///
  /// Returns a [PdfDocumentNode] ready to be added to the scene graph,
  /// or `null` if the import fails or no provider is configured.
  ///
  /// [documentId] is the unique ID for the document node.
  /// [bytes] are the raw PDF file bytes.
  /// [insertPosition] is the canvas position for the grid origin.
  /// [gridColumns] controls the grid layout (default: 2).
  Future<PdfDocumentNode?> importDocument({
    required String documentId,
    required Uint8List bytes,
    Offset insertPosition = Offset.zero,
    int gridColumns = 2,
    double gridSpacing = 20.0,
  }) async {
    if (_provider == null) return null;

    // Load the document
    final loaded = await _provider.loadDocument(bytes);
    if (!loaded) return null;

    final pageCount = _provider.pageCount;
    if (pageCount == 0) return null;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Create page models and nodes
    final pageModels = <PdfPageModel>[];
    final pageNodes = <PdfPageNode>[];

    for (int i = 0; i < pageCount; i++) {
      final size = _provider.pageSize(i);

      final pageModel = PdfPageModel(
        pageIndex: i,
        originalSize: size,
        lastModifiedAt: now,
      );
      pageModels.add(pageModel);

      final pageNode = PdfPageNode(
        id: NodeId('${documentId}_page_$i'),
        pageModel: pageModel,
        name: 'Page ${i + 1}',
      );
      pageNodes.add(pageNode);
    }

    // Compute source hash (simple byte count + first bytes for uniqueness)
    final sourceHash = _computeSimpleHash(bytes);

    // Create document model
    final documentModel = PdfDocumentModel(
      sourceHash: sourceHash,
      totalPages: pageCount,
      pages: pageModels,
      gridColumns: gridColumns,
      gridSpacing: gridSpacing,
      gridOrigin: insertPosition,
      createdAt: now,
      lastModifiedAt: now,
    );

    // Create document node
    final docNode = PdfDocumentNode(
      id: NodeId(documentId),
      documentModel: documentModel,
      name: 'PDF ($pageCount pages)',
    );

    // Add page nodes as children
    for (final page in pageNodes) {
      docNode.add(page);
    }

    // Perform initial grid layout
    docNode.performGridLayout();

    return docNode;
  }

  /// Compute a simple hash for duplicate detection.
  ///
  /// Not cryptographically secure — just for quick comparison.
  String _computeSimpleHash(Uint8List bytes) {
    int hash = bytes.length;
    // Sample first 256 bytes + last 256 bytes
    final sampleSize = bytes.length < 512 ? bytes.length : 256;
    for (int i = 0; i < sampleSize; i++) {
      hash = (hash * 31 + bytes[i]) & 0x7FFFFFFF;
    }
    if (bytes.length > 512) {
      for (int i = bytes.length - 256; i < bytes.length; i++) {
        hash = (hash * 31 + bytes[i]) & 0x7FFFFFFF;
      }
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
