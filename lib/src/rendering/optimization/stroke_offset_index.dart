import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import '../../storage/sqflite_stub_web.dart'
    if (dart.library.ffi) 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../export/binary_canvas_format.dart';
import '../../core/models/canvas_layer.dart';

/// 📦 STROKE OFFSET INDEX — Seekable binary format for 10M+ strokes
///
/// Stores byte offsets for each stroke within the binary blob, enabling
/// O(1) random access to individual strokes without decoding the entire file.
///
/// ARCHITECTURE:
/// ```
/// Binary blob: [LAYER_HEADER][stroke_0@offset_100][stroke_1@offset_350]...
/// Index table:  stroke_0 → offset=100, length=250
///               stroke_1 → offset=350, length=180
///
/// Page-in stroke_1:
///   1. Look up offset (350) and length (180) from index
///   2. Slice binary[350..530]
///   3. Decode only those bytes → full ProStroke
/// ```
class StrokeOffsetIndex {
  Database? _db;

  static const String _tableName = 'stroke_offsets';

  bool get isInitialized => _db != null;

  // =========================================================================
  // INITIALIZATION
  // =========================================================================

  Future<void> initialize(Database db) async {
    _db = db;
    await _ensureTable();
  }

  Future<void> _ensureTable() async {
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        stroke_id    TEXT NOT NULL,
        canvas_id    TEXT NOT NULL,
        layer_index  INTEGER NOT NULL,
        byte_offset  INTEGER NOT NULL,
        byte_length  INTEGER NOT NULL,
        PRIMARY KEY (stroke_id, canvas_id)
      )
    ''');
    await _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_stroke_offsets_canvas
      ON $_tableName(canvas_id)
    ''');
  }

  // =========================================================================
  // INDEX BUILD — Run after encode to build offset map
  // =========================================================================

  /// Build the offset index for a binary-encoded canvas.
  ///
  /// Parses the binary blob to record each stroke's byte offset and length.
  /// Then on next load, individual strokes can be seeked directly.
  Future<void> buildIndex(
    String canvasId,
    Uint8List binaryData,
    List<CanvasLayer> layers,
  ) async {
    if (_db == null) return;

    // Parse the binary to find stroke offsets — run in background isolate
    // to avoid UI jank at 10M strokes (~100ms scan).
    final layerCount = layers.length;
    final entries = await compute(
      _scanStrokeOffsetsIsolate,
      _ScanParams(data: binaryData, layerCount: layerCount),
    );
    if (entries.isEmpty) return;

    // Batch insert
    final batch = _db!.batch();

    // Clear old index for this canvas
    batch.delete(_tableName, where: 'canvas_id = ?', whereArgs: [canvasId]);

    for (final entry in entries) {
      batch.insert(_tableName, {
        'stroke_id': entry.strokeId,
        'canvas_id': canvasId,
        'layer_index': entry.layerIndex,
        'byte_offset': entry.byteOffset,
        'byte_length': entry.byteLength,
      });
    }

    await batch.commit(noResult: true);
  }

  /// Check if an offset index exists for a canvas.
  Future<bool> hasIndex(String canvasId) async {
    if (_db == null) return false;
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_tableName WHERE canvas_id = ?',
      [canvasId],
    );
    return (result.first['cnt'] as int) > 0;
  }

  // =========================================================================
  // SEEKABLE READ — Load individual strokes by byte offset
  // =========================================================================

  /// Read a single stroke from binary data using its stored offset.
  ///
  /// O(1) seek + O(points) decode — no need to read the entire blob.
  Future<ProStroke?> readStroke(
    String canvasId,
    String strokeId,
    Uint8List binaryData,
  ) async {
    if (_db == null) return null;

    final rows = await _db!.query(
      _tableName,
      columns: ['byte_offset', 'byte_length'],
      where: 'canvas_id = ? AND stroke_id = ?',
      whereArgs: [canvasId, strokeId],
    );

    if (rows.isEmpty) return null;

    final offset = rows.first['byte_offset'] as int;
    final length = rows.first['byte_length'] as int;

    if (offset + length > binaryData.length) return null;

    // Slice the binary and decode only this stroke
    final strokeBytes = binaryData.sublist(offset, offset + length);
    return _decodeStrokeFromBytes(strokeBytes);
  }

  /// Read multiple strokes by IDs (batched offset lookup).
  Future<Map<String, ProStroke>> readStrokes(
    String canvasId,
    List<String> strokeIds,
    Uint8List binaryData,
  ) async {
    if (_db == null || strokeIds.isEmpty) return const {};

    final result = <String, ProStroke>{};

    // Batch query all offsets
    final placeholders = strokeIds.map((_) => '?').join(',');
    final rows = await _db!.rawQuery(
      'SELECT stroke_id, byte_offset, byte_length FROM $_tableName '
      'WHERE canvas_id = ? AND stroke_id IN ($placeholders)',
      [canvasId, ...strokeIds],
    );

    for (final row in rows) {
      final strokeId = row['stroke_id'] as String;
      final offset = row['byte_offset'] as int;
      final length = row['byte_length'] as int;

      if (offset + length > binaryData.length) continue;

      final strokeBytes = binaryData.sublist(offset, offset + length);
      final stroke = _decodeStrokeFromBytes(strokeBytes);
      if (stroke != null) {
        result[strokeId] = stroke;
      }
    }

    return result;
  }

  /// Clear the index for a canvas.
  Future<void> clearIndex(String canvasId) async {
    if (_db == null) return;
    await _db!.delete(
      _tableName,
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
  }

  // =========================================================================
  // INTERNAL — Binary scanning and decoding
  // =========================================================================

  /// Scan a v3 binary blob to find stroke byte offsets.
  ///
  /// This re-parses the binary format header-by-header to record where
  /// each stroke starts and ends. Only needs to run once per save.
  static List<_OffsetEntry> _scanStrokeOffsets(Uint8List data, int layerCount) {
    final entries = <_OffsetEntry>[];

    // Check if it's a full file with header
    int startOffset = 0;
    if (BinaryCanvasFormat.isBinaryFormat(data) && data.length >= 16) {
      // Skip the file header (magic + version + flags + page count + page index)
      // Parse pages to find the layers block offset
      final bd = ByteData.sublistView(data);
      final pageCount = bd.getUint32(8, Endian.little);
      startOffset =
          16; // Skip file header (magic + version + flags + pageCount)
      // Skip page index entries
      startOffset += pageCount * 8; // Each page entry: pageId(4) + offset(4)
    }

    int pos = startOffset;
    if (pos + 4 > data.length) return entries;

    final bd = ByteData.sublistView(data);
    final binaryLayerCount = bd.getUint32(pos, Endian.little);
    pos += 4;

    for (int li = 0; li < binaryLayerCount && li < layerCount; li++) {
      // Skip layer header: id(string), name(string), flags(1), opacity(4)
      pos = _skipString(data, pos); // id
      pos = _skipString(data, pos); // name
      pos += 1; // flags
      pos += 4; // opacity

      if (pos + 16 > data.length) break;

      // Read counts
      final strokeCount = bd.getUint32(pos, Endian.little);
      pos += 4;
      final shapeCount = bd.getUint32(pos, Endian.little);
      pos += 4;
      final textCount = bd.getUint32(pos, Endian.little);
      pos += 4;
      final imageCount = bd.getUint32(pos, Endian.little);
      pos += 4;

      // Record stroke offsets
      for (int si = 0; si < strokeCount; si++) {
        final strokeStart = pos;
        final strokeId = _readStringAt(data, pos);
        pos = _skipString(data, pos); // id
        pos += 4; // createdAt
        pos += 1; // penType
        pos += 4; // color
        pos += 4; // baseWidth
        if (pos + 4 > data.length) break;
        final pointCount = bd.getUint32(pos, Endian.little);
        pos += 4;
        pos +=
            pointCount *
            16; // 4 floats × 4 bytes each (dx, dy, pressure, timestamp)

        entries.add(
          _OffsetEntry(
            strokeId: strokeId,
            layerIndex: li,
            byteOffset: strokeStart,
            byteLength: pos - strokeStart,
          ),
        );
      }

      // Skip shapes, texts, images (we don't need their offsets)
      for (int si = 0; si < shapeCount; si++) {
        pos = _skipShape(data, bd, pos);
      }
      for (int ti = 0; ti < textCount; ti++) {
        pos = _skipText(data, bd, pos);
      }
      for (int ii = 0; ii < imageCount; ii++) {
        pos = _skipImage(data, bd, pos);
      }
    }

    return entries;
  }

  /// Decode a single stroke from raw bytes (isolated from the binary stream).
  static ProStroke? _decodeStrokeFromBytes(Uint8List bytes) {
    try {
      final bd = ByteData.sublistView(bytes);
      int pos = 0;

      // Read stroke ID
      final idLen = bd.getUint16(pos, Endian.little);
      pos += 2;
      final id = utf8.decode(bytes.sublist(pos, pos + idLen));
      pos += idLen;

      // createdAt
      final createdAtEpoch = bd.getUint32(pos, Endian.little);
      pos += 4;

      // penType
      final penTypeIndex = bytes[pos];
      pos += 1;

      // color
      final colorValue = bd.getUint32(pos, Endian.little);
      pos += 4;

      // baseWidth
      final baseWidth = bd.getFloat32(pos, Endian.little);
      pos += 4;

      // points
      final pointCount = bd.getUint32(pos, Endian.little);
      pos += 4;

      final points = <ProDrawingPoint>[];
      for (int i = 0; i < pointCount; i++) {
        final dx = bd.getFloat32(pos, Endian.little);
        pos += 4;
        final dy = bd.getFloat32(pos, Endian.little);
        pos += 4;
        final pressure = bd.getFloat32(pos, Endian.little);
        pos += 4;
        final timestamp = bd.getUint32(pos, Endian.little);
        pos += 4;

        points.add(
          ProDrawingPoint(
            position: Offset(dx, dy),
            pressure: pressure,
            timestamp: timestamp,
          ),
        );
      }

      return ProStroke(
        id: id,
        points: points,
        color: Color(colorValue),
        baseWidth: baseWidth,
        penType:
            ProPenType.values[penTypeIndex.clamp(
              0,
              ProPenType.values.length - 1,
            )],
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtEpoch * 1000),
      );
    } catch (e) {
      return null;
    }
  }

  // =========================================================================
  // BINARY SKIP HELPERS — Navigate the format without decoding
  // =========================================================================

  static int _skipString(Uint8List data, int pos) {
    if (pos + 2 > data.length) return data.length;
    final bd = ByteData.sublistView(data);
    final len = bd.getUint16(pos, Endian.little);
    return pos + 2 + len;
  }

  static String _readStringAt(Uint8List data, int pos) {
    final bd = ByteData.sublistView(data);
    final len = bd.getUint16(pos, Endian.little);
    return utf8.decode(data.sublist(pos + 2, pos + 2 + len));
  }

  static int _skipShape(Uint8List data, ByteData bd, int pos) {
    pos = _skipString(data, pos); // id
    pos += 4; // createdAt
    pos += 1; // shapeType
    pos += 4; // color
    pos += 4; // strokeWidth
    pos += 1; // isFilled
    // position: 2 floats
    pos += 8;
    // size: 2 floats
    pos += 8;
    // rotation
    pos += 4;
    return pos;
  }

  static int _skipText(Uint8List data, ByteData bd, int pos) {
    pos = _skipString(data, pos); // id
    pos += 4; // createdAt
    pos = _skipString(data, pos); // text content
    pos += 4; // fontSize
    pos += 4; // color
    pos += 1; // isBold
    pos += 1; // isItalic
    pos += 8; // position (2 floats)
    pos += 4; // rotation
    pos = _skipString(data, pos); // fontFamily
    return pos;
  }

  static int _skipImage(Uint8List data, ByteData bd, int pos) {
    pos = _skipString(data, pos); // id
    pos = _skipString(data, pos); // assetPath
    pos += 16; // x, y, width, height (4 floats)
    pos += 4; // rotation
    pos += 1; // fitMode
    pos += 4; // opacity
    // Crop rect (4 floats if present)
    if (pos < data.length && data[pos] == 1) {
      pos += 1;
      pos += 16; // crop rect
    } else {
      pos += 1;
    }
    return pos;
  }
}

/// Parameters for compute() isolate binary scan.
class _ScanParams {
  final Uint8List data;
  final int layerCount;
  _ScanParams({required this.data, required this.layerCount});
}

/// Top-level function for compute() — scans binary blob for stroke offsets.
/// Must be top-level (not a method) for Dart isolate compatibility.
List<_OffsetEntry> _scanStrokeOffsetsIsolate(_ScanParams params) {
  return StrokeOffsetIndex._scanStrokeOffsets(params.data, params.layerCount);
}

/// Internal offset entry for stroke position in binary.
class _OffsetEntry {
  final String strokeId;
  final int layerIndex;
  final int byteOffset;
  final int byteLength;

  _OffsetEntry({
    required this.strokeId,
    required this.layerIndex,
    required this.byteOffset,
    required this.byteLength,
  });
}
