import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../models/pdf_document_model.dart';

/// 📄 Scene graph node for a PDF preview card on the canvas.
///
/// Replaces the old multi-page [PdfDocumentNode] layout. Instead of placing
/// all pages as children on the canvas, this node shows a single compact
/// preview card with the first page thumbnail. Long-press opens a separate
/// full-screen PDF reader screen.
///
/// DESIGN PRINCIPLES:
/// - Single element on the canvas (like an image node)
/// - Holds the full [PdfDocumentModel] for the reader
/// - Thumbnail image rendered from page 1
/// - No child nodes — pages live only in the reader screen
/// - Serializable for canvas save/restore
class PdfPreviewCardNode extends CanvasNode {
  /// Document-level metadata (hash, page info, file path, etc.).
  PdfDocumentModel documentModel;

  /// Cached thumbnail image of page 1 (set during import or restore).
  ui.Image? thumbnailImage;

  /// Display width of the preview card on canvas.
  double cardWidth;

  /// Display height of the preview card on canvas.
  double cardHeight;

  /// Document ID used to look up the native provider and painter.
  final String documentId;

  PdfPreviewCardNode({
    required super.id,
    required this.documentModel,
    required this.documentId,
    this.cardWidth = 200,
    this.cardHeight = 260,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Card sizing
  // ---------------------------------------------------------------------------

  /// Set card size from the first page's aspect ratio.
  /// Fits to [targetWidth] and computes height proportionally,
  /// then adds space for the bottom badge.
  void fitToPageAspectRatio({double targetWidth = 200}) {
    if (documentModel.pages.isEmpty) return;
    final firstPage = documentModel.pages.first;
    final aspect = firstPage.originalSize.width / firstPage.originalSize.height;
    cardWidth = targetWidth;
    // Badge height ~40px
    cardHeight = targetWidth / aspect + 40;
  }

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds => Rect.fromLTWH(0, 0, cardWidth, cardHeight);

  // ---------------------------------------------------------------------------
  // Memory management
  // ---------------------------------------------------------------------------

  /// Dispose the cached thumbnail.
  void disposeThumbnail() {
    thumbnailImage?.dispose();
    thumbnailImage = null;
  }

  @override
  void dispose() {
    disposeThumbnail();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitPdfPreviewCard(this);

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'pdfPreviewCard';
    json['documentModel'] = documentModel.toJson();
    json['documentId'] = documentId;
    json['cardWidth'] = cardWidth;
    json['cardHeight'] = cardHeight;
    return json;
  }

  factory PdfPreviewCardNode.fromJson(Map<String, dynamic> json) {
    final docModel = PdfDocumentModel.fromJson(
      Map<String, dynamic>.from(json['documentModel'] as Map),
    );
    final node = PdfPreviewCardNode(
      id: NodeId(json['id'] as String),
      documentModel: docModel,
      documentId: (json['documentId'] as String?) ?? json['id'] as String,
      cardWidth: (json['cardWidth'] as num?)?.toDouble() ?? 200,
      cardHeight: (json['cardHeight'] as num?)?.toDouble() ?? 260,
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  /// Migrate from old PdfDocumentNode JSON format.
  ///
  /// Converts old multi-page grid documents to a single preview card.
  factory PdfPreviewCardNode.migrateFromDocumentJson(
    Map<String, dynamic> json,
  ) {
    final docModel = PdfDocumentModel.fromJson(
      Map<String, dynamic>.from(json['documentModel'] as Map),
    );
    final docId = json['id'] as String;
    final node = PdfPreviewCardNode(
      id: NodeId(docId),
      documentModel: docModel,
      documentId: docId,
      name: (json['name'] as String?) ?? 'PDF (${docModel.totalPages} pages)',
    );
    CanvasNode.applyBaseFromJson(node, json);
    node.fitToPageAspectRatio();
    return node;
  }
}
