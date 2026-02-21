import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_validation.dart';
import 'cell_value.dart';
import 'conditional_format.dart';
import 'merge_region_manager.dart';
import 'spreadsheet_model.dart';

/// 📊 Native XLSX import/export for the tabular engine.
///
/// Implements OOXML (Office Open XML) spreadsheet format without any
/// third-party dependencies. Uses [dart:io] for ZIP compression and
/// generates XML directly.
///
/// ## Import
/// ```dart
/// final bytes = File('data.xlsx').readAsBytesSync();
/// final model = TabularXlsx.importBytes(bytes);
/// ```
///
/// ## Export
/// ```dart
/// final bytes = TabularXlsx.exportBytes(model);
/// File('output.xlsx').writeAsBytesSync(bytes);
/// ```
///
/// ### Limitations
/// - Import reads the **first sheet** only
/// - Import preserves numeric, text, boolean, and formula values
/// - Cell styles are NOT imported (only content)
/// - Export writes a single sheet with values, formulas, and merge regions
class TabularXlsx {
  TabularXlsx._();

  // =========================================================================
  // Import
  // =========================================================================

  /// Import an XLSX file from raw bytes into a [SpreadsheetModel].
  ///
  /// Reads the first worksheet. Auto-detects cell types from the
  /// OOXML type attribute (`n`=number, `s`=shared string, `b`=bool,
  /// `str`=formula result string).
  static SpreadsheetModel importBytes(
    Uint8List bytes, {
    MergeRegionManager? mergeManager,
  }) {
    final model = SpreadsheetModel();
    final archive = _readZip(bytes);

    // -- Shared strings table --
    final sstXml = archive['xl/sharedStrings.xml'];
    final sharedStrings =
        sstXml != null ? _parseSharedStrings(sstXml) : <String>[];

    // -- Sheet data (first sheet: xl/worksheets/sheet1.xml) --
    final sheetXml = archive['xl/worksheets/sheet1.xml'];
    if (sheetXml == null) return model;

    _parseSheet(sheetXml, model, sharedStrings, mergeManager);

    return model;
  }

  // =========================================================================
  // Export
  // =========================================================================

  /// Export a [SpreadsheetModel] to XLSX bytes.
  ///
  /// Creates a minimal valid OOXML workbook with a single worksheet.
  /// Formulas are preserved with their `=` prefix.
  static Uint8List exportBytes(
    SpreadsheetModel model, {
    String sheetName = 'Sheet1',
    MergeRegionManager? mergeManager,
  }) {
    // Collect all unique strings for the shared strings table.
    final sharedStrings = <String>[];
    final stringIndex = <String, int>{};

    for (final addr in model.occupiedAddresses) {
      final cell = model.getCell(addr);
      if (cell == null) continue;
      final val = cell.displayValue;
      if (val is TextValue) {
        if (!stringIndex.containsKey(val.value)) {
          stringIndex[val.value] = sharedStrings.length;
          sharedStrings.add(val.value);
        }
      }
    }

    // Build archive entries.
    final archive = <String, String>{};

    archive['[Content_Types].xml'] = _contentTypes();
    archive['_rels/.rels'] = _rootRels();
    archive['xl/_rels/workbook.xml.rels'] = _workbookRels(
      hasSharedStrings: sharedStrings.isNotEmpty,
    );
    archive['xl/workbook.xml'] = _workbook(sheetName);
    archive['xl/styles.xml'] = _minimalStyles();
    archive['xl/worksheets/sheet1.xml'] = _sheetXml(
      model,
      stringIndex,
      mergeManager,
    );

    if (sharedStrings.isNotEmpty) {
      archive['xl/sharedStrings.xml'] = _sharedStringsXml(sharedStrings);
    }

    return _writeZip(archive);
  }

  // =========================================================================
  // ZIP I/O (minimal implementation)
  // =========================================================================

  /// Read a ZIP archive into a map of path → UTF-8 content.
  ///
  /// Uses the ZIP local file header format (PK\x03\x04).
  static Map<String, String> _readZip(Uint8List bytes) {
    final entries = <String, String>{};
    int offset = 0;

    while (offset + 30 <= bytes.length) {
      // Check for local file header signature: PK\x03\x04
      if (bytes[offset] != 0x50 ||
          bytes[offset + 1] != 0x4B ||
          bytes[offset + 2] != 0x03 ||
          bytes[offset + 3] != 0x04) {
        break; // End of local headers (central directory follows).
      }

      final compressionMethod = bytes[offset + 8] | (bytes[offset + 9] << 8);
      final compressedSize = _readUint32(bytes, offset + 18);
      final uncompressedSize = _readUint32(bytes, offset + 22);
      final nameLength = bytes[offset + 26] | (bytes[offset + 27] << 8);
      final extraLength = bytes[offset + 28] | (bytes[offset + 29] << 8);

      final nameBytes = bytes.sublist(offset + 30, offset + 30 + nameLength);
      final name = utf8.decode(nameBytes);

      final dataStart = offset + 30 + nameLength + extraLength;
      final dataEnd = dataStart + compressedSize;

      if (dataEnd > bytes.length) break;

      final compressedData = bytes.sublist(dataStart, dataEnd);

      if (compressedSize > 0) {
        try {
          if (compressionMethod == 0) {
            // Stored (no compression).
            entries[name] = utf8.decode(compressedData);
          } else if (compressionMethod == 8) {
            // Deflate compression.
            final inflated = _inflate(compressedData);
            entries[name] = utf8.decode(inflated);
          }
        } catch (_) {
          // Skip files we can't decode (e.g. binary).
        }
      }

      offset = dataEnd;
    }

    return entries;
  }

  /// Inflate deflate-compressed data (raw deflate, no zlib header).
  static Uint8List _inflate(Uint8List compressed) {
    // Wrap with zlib header for ZLibDecoder compatibility.
    // zlib header: CMF=0x78 (deflate, window=32K), FLG=0x01 (no dict, check=1)
    final withHeader = Uint8List(compressed.length + 6);
    withHeader[0] = 0x78;
    withHeader[1] = 0x01;
    withHeader.setRange(2, 2 + compressed.length, compressed);

    // Compute Adler-32 checksum for zlib trailer.
    final decompressed = ZLibCodec(raw: true).decode(compressed);
    return Uint8List.fromList(decompressed);
  }

  /// Write a ZIP archive from a map of path → UTF-8 content.
  static Uint8List _writeZip(Map<String, String> entries) {
    final buf = BytesBuilder();
    final centralDir = BytesBuilder();
    final offsets = <int>[];

    for (final entry in entries.entries) {
      final name = utf8.encode(entry.key);
      final data = utf8.encode(entry.value);

      // Compress with deflate.
      final compressed = ZLibCodec(raw: true).encode(data);

      offsets.add(buf.length);

      // Local file header.
      buf.add(
        _localFileHeader(
          name: name,
          compressedSize: compressed.length,
          uncompressedSize: data.length,
          crc32: _crc32(data),
        ),
      );
      buf.add(Uint8List.fromList(compressed));

      // Central directory entry.
      centralDir.add(
        _centralDirEntry(
          name: name,
          compressedSize: compressed.length,
          uncompressedSize: data.length,
          crc32: _crc32(data),
          localHeaderOffset: offsets.last,
        ),
      );
    }

    final centralDirOffset = buf.length;
    buf.add(centralDir.toBytes());

    // End of central directory record.
    buf.add(
      _endOfCentralDir(
        entryCount: entries.length,
        centralDirSize: centralDir.length,
        centralDirOffset: centralDirOffset,
      ),
    );

    return buf.toBytes();
  }

  static Uint8List _localFileHeader({
    required List<int> name,
    required int compressedSize,
    required int uncompressedSize,
    required int crc32,
  }) {
    final header = ByteData(30 + name.length);
    header.setUint32(0, 0x04034b50, Endian.little); // signature
    header.setUint16(4, 20, Endian.little); // version needed
    header.setUint16(6, 0, Endian.little); // flags
    header.setUint16(8, 8, Endian.little); // compression: deflate
    header.setUint16(10, 0, Endian.little); // mod time
    header.setUint16(12, 0, Endian.little); // mod date
    header.setUint32(14, crc32, Endian.little);
    header.setUint32(18, compressedSize, Endian.little);
    header.setUint32(22, uncompressedSize, Endian.little);
    header.setUint16(26, name.length, Endian.little);
    header.setUint16(28, 0, Endian.little); // extra field length
    final bytes = header.buffer.asUint8List();
    bytes.setRange(30, 30 + name.length, name);
    return bytes;
  }

  static Uint8List _centralDirEntry({
    required List<int> name,
    required int compressedSize,
    required int uncompressedSize,
    required int crc32,
    required int localHeaderOffset,
  }) {
    final header = ByteData(46 + name.length);
    header.setUint32(0, 0x02014b50, Endian.little); // signature
    header.setUint16(4, 20, Endian.little); // version made by
    header.setUint16(6, 20, Endian.little); // version needed
    header.setUint16(8, 0, Endian.little); // flags
    header.setUint16(10, 8, Endian.little); // compression: deflate
    header.setUint16(12, 0, Endian.little); // mod time
    header.setUint16(14, 0, Endian.little); // mod date
    header.setUint32(16, crc32, Endian.little);
    header.setUint32(20, compressedSize, Endian.little);
    header.setUint32(24, uncompressedSize, Endian.little);
    header.setUint16(28, name.length, Endian.little);
    header.setUint16(30, 0, Endian.little); // extra length
    header.setUint16(32, 0, Endian.little); // comment length
    header.setUint16(34, 0, Endian.little); // disk number
    header.setUint16(36, 0, Endian.little); // internal attrs
    header.setUint32(38, 0, Endian.little); // external attrs
    header.setUint32(42, localHeaderOffset, Endian.little);
    final bytes = header.buffer.asUint8List();
    bytes.setRange(46, 46 + name.length, name);
    return bytes;
  }

  static Uint8List _endOfCentralDir({
    required int entryCount,
    required int centralDirSize,
    required int centralDirOffset,
  }) {
    final record = ByteData(22);
    record.setUint32(0, 0x06054b50, Endian.little); // signature
    record.setUint16(4, 0, Endian.little); // disk number
    record.setUint16(6, 0, Endian.little); // central dir disk
    record.setUint16(8, entryCount, Endian.little);
    record.setUint16(10, entryCount, Endian.little);
    record.setUint32(12, centralDirSize, Endian.little);
    record.setUint32(16, centralDirOffset, Endian.little);
    record.setUint16(20, 0, Endian.little); // comment length
    return record.buffer.asUint8List();
  }

  // -------------------------------------------------------------------------
  // CRC-32 (used by ZIP format)
  // -------------------------------------------------------------------------

  static final List<int> _crc32Table = _buildCrc32Table();

  static List<int> _buildCrc32Table() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }

  static int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  // =========================================================================
  // OOXML Import Parsing
  // =========================================================================

  /// Parse shared strings table from xl/sharedStrings.xml.
  static List<String> _parseSharedStrings(String xml) {
    final strings = <String>[];
    // Extract <t>...</t> content from each <si> element.
    final pattern = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
    for (final match in pattern.allMatches(xml)) {
      strings.add(_xmlUnescape(match.group(1) ?? ''));
    }
    return strings;
  }

  /// Parse worksheet XML into the model.
  static void _parseSheet(
    String xml,
    SpreadsheetModel model,
    List<String> sharedStrings,
    MergeRegionManager? mergeManager,
  ) {
    // Parse <row> elements.
    final rowPattern = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true);
    final cellPattern = RegExp(
      r'<c\s+r="([A-Z]+\d+)"([^>]*)(?:><v>(.*?)</v>|><f>(.*?)</f><v>(.*?)</v>|/>)',
      dotAll: true,
    );

    for (final rowMatch in rowPattern.allMatches(xml)) {
      final rowContent = rowMatch.group(1) ?? '';

      for (final cellMatch in cellPattern.allMatches(rowContent)) {
        final ref = cellMatch.group(1)!;
        final attrs = cellMatch.group(2) ?? '';
        final vValue = cellMatch.group(3);
        final fValue = cellMatch.group(4);
        final fvValue = cellMatch.group(5);

        final addr = CellAddress.fromLabel(ref);

        // Determine cell type from t="..." attribute.
        final typeMatch = RegExp(r't="(\w+)"').firstMatch(attrs);
        final cellType = typeMatch?.group(1);

        CellValue value;
        if (fValue != null) {
          // Formula cell.
          value = FormulaValue(_xmlUnescape(fValue));
        } else if (cellType == 's' && vValue != null) {
          // Shared string reference.
          final idx = int.tryParse(vValue) ?? 0;
          value =
              idx < sharedStrings.length
                  ? TextValue(sharedStrings[idx])
                  : const TextValue('');
        } else if (cellType == 'b' && vValue != null) {
          // Boolean.
          value = BoolValue(vValue == '1');
        } else if (cellType == 'str' && vValue != null) {
          // Inline string.
          value = TextValue(_xmlUnescape(vValue));
        } else if (vValue != null) {
          // Numeric (default).
          final n = num.tryParse(vValue);
          value = n != null ? NumberValue(n) : TextValue(vValue);
        } else {
          continue; // Empty cell reference.
        }

        model.setCell(addr, CellNode(value: value));
      }
    }

    // Parse <mergeCell> elements.
    if (mergeManager != null) {
      final mergePattern = RegExp(r'<mergeCell\s+ref="([^"]+)"');
      for (final match in mergePattern.allMatches(xml)) {
        final ref = match.group(1)!;
        try {
          mergeManager.addRegion(CellRange.fromLabel(ref));
        } catch (_) {
          // Skip invalid or overlapping merge regions.
        }
      }
    }

    // Parse <dataValidation> elements.
    _parseDataValidations(xml, model);

    // Parse <conditionalFormatting> elements.
    _parseConditionalFormatting(xml, model);
  }

  // =========================================================================
  // OOXML Export XML Generation
  // =========================================================================

  static String _sheetXml(
    SpreadsheetModel model,
    Map<String, int> stringIndex,
    MergeRegionManager? mergeManager,
  ) {
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/'
      'spreadsheetml/2006/main">',
    );

    // Column widths.
    if (model.maxColumn >= 0) {
      buf.write('<cols>');
      for (int c = 0; c <= model.maxColumn; c++) {
        final w = model.getColumnWidth(c);
        // Excel column width ≈ logical pixels / 7.5.
        final excelWidth = (w / 7.5).toStringAsFixed(2);
        buf.write(
          '<col min="${c + 1}" max="${c + 1}" '
          'width="$excelWidth" customWidth="1"/>',
        );
      }
      buf.write('</cols>');
    }

    // Sheet data.
    buf.write('<sheetData>');

    if (model.cellCount > 0) {
      final maxRow = model.maxRow;
      final maxCol = model.maxColumn;

      for (int r = 0; r <= maxRow; r++) {
        // Check if row has any cells.
        bool hasData = false;
        for (int c = 0; c <= maxCol; c++) {
          if (model.hasCell(CellAddress(c, r))) {
            hasData = true;
            break;
          }
        }
        if (!hasData) continue;

        buf.write('<row r="${r + 1}">');
        for (int c = 0; c <= maxCol; c++) {
          final addr = CellAddress(c, r);
          final cell = model.getCell(addr);
          if (cell == null) continue;

          _writeCellXml(buf, addr, cell, stringIndex);
        }
        buf.write('</row>');
      }
    }
    buf.write('</sheetData>');

    // Merge cells.
    if (mergeManager != null && mergeManager.regionCount > 0) {
      buf.write('<mergeCells count="${mergeManager.regionCount}">');
      for (final region in mergeManager.regions) {
        buf.write('<mergeCell ref="${region.label}"/>');
      }
      buf.write('</mergeCells>');
    }

    // Data validations.
    _writeDataValidations(buf, model);

    // Conditional formatting.
    _writeConditionalFormatting(buf, model);

    buf.write('</worksheet>');
    return buf.toString();
  }

  static void _writeCellXml(
    StringBuffer buf,
    CellAddress addr,
    CellNode cell,
    Map<String, int> stringIndex,
  ) {
    final ref = addr.label;
    final val = cell.value;

    switch (val) {
      case FormulaValue(:final expression):
        // Formula cell: write formula + cached value.
        final computed = cell.computedValue;
        buf.write('<c r="$ref"><f>${_xmlEscape(expression)}</f>');
        if (computed is NumberValue) {
          buf.write('<v>${computed.value}</v>');
        } else if (computed is TextValue) {
          buf.write('<v>${_xmlEscape(computed.value)}</v>');
        }
        buf.write('</c>');

      case NumberValue(:final value):
        buf.write('<c r="$ref"><v>$value</v></c>');

      case TextValue(:final value):
        final idx = stringIndex[value];
        if (idx != null) {
          buf.write('<c r="$ref" t="s"><v>$idx</v></c>');
        } else {
          buf.write('<c r="$ref" t="str"><v>${_xmlEscape(value)}</v></c>');
        }

      case BoolValue(:final value):
        buf.write('<c r="$ref" t="b"><v>${value ? '1' : '0'}</v></c>');

      case ErrorValue(:final error):
        buf.write(
          '<c r="$ref" t="e"><v>${_xmlEscape(ErrorValue(error).displayString)}</v></c>',
        );

      case EmptyValue():
        break; // Don't write empty cells.

      case ComplexValue():
        // Write metadata as string fallback.
        buf.write(
          '<c r="$ref" t="str"><v>${_xmlEscape(val.displayString)}</v></c>',
        );
    }
  }

  static String _sharedStringsXml(List<String> strings) {
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.write(
      '<sst xmlns="http://schemas.openxmlformats.org/'
      'spreadsheetml/2006/main" '
      'count="${strings.length}" uniqueCount="${strings.length}">',
    );
    for (final s in strings) {
      buf.write('<si><t>${_xmlEscape(s)}</t></si>');
    }
    buf.write('</sst>');
    return buf.toString();
  }

  static String _contentTypes() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>''';

  static String _rootRels() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static String _workbookRels({bool hasSharedStrings = false}) {
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.write(
      '<Relationships xmlns="http://schemas.openxmlformats.org/'
      'package/2006/relationships">',
    );
    buf.write(
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/>',
    );
    buf.write(
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
    if (hasSharedStrings) {
      buf.write(
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships/sharedStrings" '
        'Target="sharedStrings.xml"/>',
      );
    }
    buf.write('</Relationships>');
    return buf.toString();
  }

  static String _workbook(String sheetName) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="${_xmlEscape(sheetName)}" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';

  static String _minimalStyles() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>''';

  // =========================================================================
  // OOXML Data Validation Export/Import
  // =========================================================================

  /// Write `<dataValidations>` element for all validation rules.
  static void _writeDataValidations(StringBuffer buf, SpreadsheetModel model) {
    final validations = <CellAddress, CellValidation>{};
    for (final addr in model.occupiedAddresses) {
      if (model.hasValidation(addr)) {
        validations[addr] = model.getValidation(addr)!;
      }
    }
    if (validations.isEmpty) return;

    buf.write('<dataValidations count="${validations.length}">');
    for (final entry in validations.entries) {
      final addr = entry.key;
      final rule = entry.value;

      // Map CellValidationType to OOXML type attribute.
      final ooxmlType = switch (rule.type) {
        CellValidationType.number => 'decimal',
        CellValidationType.integer => 'whole',
        CellValidationType.list => 'list',
        CellValidationType.date => 'date',
        CellValidationType.textLength => 'textLength',
        CellValidationType.custom => 'custom',
        CellValidationType.any => 'none',
      };

      // Determine operator.
      String operator = 'between';
      if (rule.min != null && rule.max != null) {
        operator = 'between';
      } else if (rule.min != null) {
        operator = 'greaterThanOrEqual';
      } else if (rule.max != null) {
        operator = 'lessThanOrEqual';
      }

      // Error style.
      final errorStyle = switch (rule.errorStyle) {
        ValidationErrorStyle.stop => 'stop',
        ValidationErrorStyle.warning => 'warning',
        ValidationErrorStyle.information => 'information',
      };

      buf.write(
        '<dataValidation type="$ooxmlType" operator="$operator" '
        'sqref="${addr.label}" '
        'allowBlank="${rule.ignoreBlank ? '1' : '0'}" '
        'errorStyle="$errorStyle"'
        '${rule.showInputMessage ? ' showInputMessage="1"' : ''}'
        '${rule.errorTitle != null ? ' errorTitle="${_xmlEscape(rule.errorTitle!)}"' : ''}'
        '${rule.errorMessage != null ? ' error="${_xmlEscape(rule.errorMessage!)}"' : ''}'
        '${rule.inputTitle != null ? ' promptTitle="${_xmlEscape(rule.inputTitle!)}"' : ''}'
        '${rule.inputMessage != null ? ' prompt="${_xmlEscape(rule.inputMessage!)}"' : ''}'
        '>',
      );

      // Formulas for constraints.
      if (rule.type == CellValidationType.list && rule.allowedValues != null) {
        buf.write(
          '<formula1>"${_xmlEscape(rule.allowedValues!.join(','))}"</formula1>',
        );
      } else if (rule.type == CellValidationType.custom &&
          rule.customFormula != null) {
        buf.write('<formula1>${_xmlEscape(rule.customFormula!)}</formula1>');
      } else {
        if (rule.min != null) buf.write('<formula1>${rule.min}</formula1>');
        if (rule.max != null) buf.write('<formula2>${rule.max}</formula2>');
      }

      buf.write('</dataValidation>');
    }
    buf.write('</dataValidations>');
  }

  /// Parse `<dataValidation>` elements from sheet XML.
  static void _parseDataValidations(String xml, SpreadsheetModel model) {
    final dvPattern = RegExp(
      r'<dataValidation\s+([^>]*)>(.*?)</dataValidation>',
      dotAll: true,
    );

    for (final match in dvPattern.allMatches(xml)) {
      final attrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';

      // Extract attributes.
      final sqref = RegExp(r'sqref="([^"]+)"').firstMatch(attrs)?.group(1);
      final typeStr = RegExp(r'type="([^"]+)"').firstMatch(attrs)?.group(1);
      final operatorStr = RegExp(
        r'operator="([^"]+)"',
      ).firstMatch(attrs)?.group(1);
      final allowBlank = RegExp(
        r'allowBlank="([^"]+)"',
      ).firstMatch(attrs)?.group(1);
      final errorStyleStr = RegExp(
        r'errorStyle="([^"]+)"',
      ).firstMatch(attrs)?.group(1);
      final errorTitle = RegExp(
        r'errorTitle="([^"]*)"',
      ).firstMatch(attrs)?.group(1);
      final errorMsg = RegExp(r'error="([^"]*)"').firstMatch(attrs)?.group(1);
      final inputTitle = RegExp(
        r'promptTitle="([^"]*)"',
      ).firstMatch(attrs)?.group(1);
      final inputMsg = RegExp(r'prompt="([^"]*)"').firstMatch(attrs)?.group(1);

      if (sqref == null) continue;

      // Map OOXML type to our type.
      final type = switch (typeStr) {
        'decimal' => CellValidationType.number,
        'whole' => CellValidationType.integer,
        'list' => CellValidationType.list,
        'date' => CellValidationType.date,
        'textLength' => CellValidationType.textLength,
        'custom' => CellValidationType.custom,
        _ => CellValidationType.any,
      };

      // Extract formulas.
      final f1 = RegExp(
        r'<formula1>(.*?)</formula1>',
        dotAll: true,
      ).firstMatch(body)?.group(1);
      final f2 = RegExp(
        r'<formula2>(.*?)</formula2>',
        dotAll: true,
      ).firstMatch(body)?.group(1);

      // Build validation.
      num? min;
      num? max;
      List<String>? allowedValues;
      String? customFormula;

      if (type == CellValidationType.list && f1 != null) {
        // Strip surrounding quotes.
        final listStr =
            f1.startsWith('"') && f1.endsWith('"')
                ? f1.substring(1, f1.length - 1)
                : f1;
        allowedValues = listStr.split(',');
      } else if (type == CellValidationType.custom && f1 != null) {
        customFormula = _xmlUnescape(f1);
      } else {
        if (f1 != null) min = num.tryParse(f1);
        if (f2 != null) max = num.tryParse(f2);
        // Handle single-bound operators.
        if (operatorStr == 'greaterThanOrEqual' && min != null) {
          max = null;
        } else if (operatorStr == 'lessThanOrEqual' && f1 != null) {
          max = num.tryParse(f1);
          min = null;
        }
      }

      final errorStyle = switch (errorStyleStr) {
        'warning' => ValidationErrorStyle.warning,
        'information' => ValidationErrorStyle.information,
        _ => ValidationErrorStyle.stop,
      };

      final validation = CellValidation(
        type: type,
        min: min,
        max: max,
        allowedValues: allowedValues,
        customFormula: customFormula,
        errorTitle: errorTitle != null ? _xmlUnescape(errorTitle) : null,
        errorMessage: errorMsg != null ? _xmlUnescape(errorMsg) : null,
        errorStyle: errorStyle,
        ignoreBlank: allowBlank != '0',
        showInputMessage: RegExp(r'showInputMessage="1"').hasMatch(attrs),
        inputTitle: inputTitle != null ? _xmlUnescape(inputTitle) : null,
        inputMessage: inputMsg != null ? _xmlUnescape(inputMsg) : null,
      );

      // Parse sqref — may be a single cell or range.
      try {
        final addr = CellAddress.fromLabel(sqref);
        model.setValidation(addr, validation);
      } catch (_) {
        // Skip unsupported sqref formats.
      }
    }
  }

  // =========================================================================
  // OOXML Conditional Formatting Export/Import
  // =========================================================================

  /// Write `<conditionalFormatting>` elements for all rules.
  static void _writeConditionalFormatting(
    StringBuffer buf,
    SpreadsheetModel model,
  ) {
    final rules = model.conditionalFormats.rules;
    if (rules.isEmpty) return;

    for (final rule in rules) {
      buf.write('<conditionalFormatting sqref="${rule.appliesTo.label}">');

      // Map our condition to OOXML cfRule type and operator.
      final (cfType, operator) = _conditionToOoxml(rule.condition);

      buf.write(
        '<cfRule type="$cfType"'
        '${operator != null ? ' operator="$operator"' : ''}'
        ' priority="${rule.priority}"'
        '${rule.stopIfTrue ? ' stopIfTrue="1"' : ''}',
      );
      buf.write('>');

      // Formula (threshold value).
      if (rule.threshold != null) {
        buf.write('<formula>${rule.threshold}</formula>');
      }

      // Inline differential formatting (dxf).
      _writeDxf(buf, rule.format);

      buf.write('</cfRule>');
      buf.write('</conditionalFormatting>');
    }
  }

  /// Map our FormatCondition to OOXML cfRule type + operator.
  static (String, String?) _conditionToOoxml(FormatCondition c) => switch (c) {
    FormatCondition.greaterThan => ('cellIs', 'greaterThan'),
    FormatCondition.greaterThanOrEqual => ('cellIs', 'greaterThanOrEqual'),
    FormatCondition.lessThan => ('cellIs', 'lessThan'),
    FormatCondition.lessThanOrEqual => ('cellIs', 'lessThanOrEqual'),
    FormatCondition.equal => ('cellIs', 'equal'),
    FormatCondition.notEqual => ('cellIs', 'notEqual'),
    FormatCondition.between => ('cellIs', 'between'),
    FormatCondition.notBetween => ('cellIs', 'notBetween'),
    FormatCondition.textContains => ('containsText', null),
    FormatCondition.textStartsWith => ('beginsWith', null),
    FormatCondition.textEndsWith => ('endsWith', null),
    FormatCondition.isBlank => ('containsBlanks', null),
    FormatCondition.isNotBlank => ('notContainsBlanks', null),
    FormatCondition.isError => ('containsErrors', null),
    FormatCondition.custom => ('expression', null),
  };

  /// Write inline `<dxf>` element for conditional format styling.
  static void _writeDxf(StringBuffer buf, CellFormat format) {
    buf.write('<dxf>');
    if (format.textColor != null ||
        format.bold != null ||
        format.italic != null ||
        format.fontSize != null) {
      buf.write('<font>');
      if (format.bold == true) buf.write('<b/>');
      if (format.italic == true) buf.write('<i/>');
      if (format.fontSize != null) {
        buf.write('<sz val="${format.fontSize}"/>');
      }
      if (format.textColor != null) {
        buf.write('<color rgb="${_colorToArgb(format.textColor!)}"/>');
      }
      buf.write('</font>');
    }
    if (format.backgroundColor != null) {
      buf.write(
        '<fill><patternFill patternType="solid">'
        '<fgColor rgb="${_colorToArgb(format.backgroundColor!)}"/>'
        '</patternFill></fill>',
      );
    }
    buf.write('</dxf>');
  }

  /// Convert a Color to OOXML ARGB hex string (e.g. "FFFF0000").
  static String _colorToArgb(Color c) {
    final a = (c.a * 255).round().clamp(0, 255);
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '${a.toRadixString(16).padLeft(2, '0')}'
            '${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  /// Parse OOXML ARGB hex string to Color.
  static Color? _argbToColor(String? argb) {
    if (argb == null || argb.length < 6) return null;
    final hex = argb.length == 8 ? argb : 'FF$argb';
    return Color(int.parse(hex, radix: 16));
  }

  /// Parse `<conditionalFormatting>` elements from sheet XML.
  static void _parseConditionalFormatting(String xml, SpreadsheetModel model) {
    final cfPattern = RegExp(
      r'<conditionalFormatting\s+sqref="([^"]+)">(.*?)</conditionalFormatting>',
      dotAll: true,
    );

    for (final match in cfPattern.allMatches(xml)) {
      final sqref = match.group(1)!;
      final body = match.group(2) ?? '';

      CellRange range;
      try {
        range = CellRange.fromLabel(sqref);
      } catch (_) {
        continue;
      }

      // Parse <cfRule> elements.
      final rulePattern = RegExp(
        r'<cfRule\s+([^>]*)>(.*?)</cfRule>',
        dotAll: true,
      );

      for (final ruleMatch in rulePattern.allMatches(body)) {
        final rAttrs = ruleMatch.group(1) ?? '';
        final rBody = ruleMatch.group(2) ?? '';

        final typeStr = RegExp(r'type="([^"]+)"').firstMatch(rAttrs)?.group(1);
        final operatorStr = RegExp(
          r'operator="([^"]+)"',
        ).firstMatch(rAttrs)?.group(1);
        final priorityStr = RegExp(
          r'priority="(\d+)"',
        ).firstMatch(rAttrs)?.group(1);
        final stopIfTrue = RegExp(r'stopIfTrue="1"').hasMatch(rAttrs);

        // Map OOXML type/operator back to our FormatCondition.
        final condition = _ooxmlToCondition(typeStr, operatorStr);

        // Extract formula (threshold).
        final formula = RegExp(
          r'<formula>(.*?)</formula>',
          dotAll: true,
        ).firstMatch(rBody)?.group(1);
        dynamic threshold;
        if (formula != null) {
          threshold = num.tryParse(formula) ?? formula;
        }

        // Parse <dxf> for formatting.
        final format = _parseDxf(rBody);

        model.conditionalFormats.addRule(
          ConditionalFormatRule(
            appliesTo: range,
            condition: condition,
            threshold: threshold,
            format: format,
            priority: int.tryParse(priorityStr ?? '') ?? 0,
            stopIfTrue: stopIfTrue,
          ),
        );
      }
    }
  }

  /// Map OOXML cfRule type/operator back to FormatCondition.
  static FormatCondition _ooxmlToCondition(String? type, String? operator) {
    if (type == 'cellIs') {
      return switch (operator) {
        'greaterThan' => FormatCondition.greaterThan,
        'greaterThanOrEqual' => FormatCondition.greaterThanOrEqual,
        'lessThan' => FormatCondition.lessThan,
        'lessThanOrEqual' => FormatCondition.lessThanOrEqual,
        'equal' => FormatCondition.equal,
        'notEqual' => FormatCondition.notEqual,
        'between' => FormatCondition.between,
        'notBetween' => FormatCondition.notBetween,
        _ => FormatCondition.equal,
      };
    }
    return switch (type) {
      'containsText' => FormatCondition.textContains,
      'beginsWith' => FormatCondition.textStartsWith,
      'endsWith' => FormatCondition.textEndsWith,
      'containsBlanks' => FormatCondition.isBlank,
      'notContainsBlanks' => FormatCondition.isNotBlank,
      'containsErrors' => FormatCondition.isError,
      _ => FormatCondition.custom,
    };
  }

  /// Parse `<dxf>` element for cell formatting.
  static CellFormat _parseDxf(String xml) {
    Color? textColor;
    Color? bgColor;
    bool? bold;
    bool? italic;
    double? fontSize;

    // Font attributes.
    final fontMatch = RegExp(
      r'<font>(.*?)</font>',
      dotAll: true,
    ).firstMatch(xml);
    if (fontMatch != null) {
      final fontXml = fontMatch.group(1)!;
      bold = fontXml.contains('<b/>') || fontXml.contains('<b ');
      italic = fontXml.contains('<i/>') || fontXml.contains('<i ');
      final szMatch = RegExp(r'<sz val="([^"]+)"').firstMatch(fontXml);
      if (szMatch != null) fontSize = double.tryParse(szMatch.group(1)!);
      final colorMatch = RegExp(r'<color rgb="([^"]+)"').firstMatch(fontXml);
      textColor = _argbToColor(colorMatch?.group(1));
    }

    // Fill attributes.
    final fillMatch = RegExp(
      r'<fill>(.*?)</fill>',
      dotAll: true,
    ).firstMatch(xml);
    if (fillMatch != null) {
      final fillXml = fillMatch.group(1)!;
      final fgMatch = RegExp(r'<fgColor rgb="([^"]+)"').firstMatch(fillXml);
      bgColor = _argbToColor(fgMatch?.group(1));
    }

    return CellFormat(
      textColor: textColor,
      backgroundColor: bgColor,
      bold: bold,
      italic: italic,
      fontSize: fontSize,
    );
  }

  // -------------------------------------------------------------------------
  // XML helpers
  // -------------------------------------------------------------------------

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _xmlUnescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
