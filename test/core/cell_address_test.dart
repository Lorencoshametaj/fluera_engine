import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';

void main() {
  // ===========================================================================
  // CellAddress
  // ===========================================================================

  group('CellAddress - construction', () {
    test('stores column and row', () {
      const addr = CellAddress(0, 0);
      expect(addr.column, 0);
      expect(addr.row, 0);
    });
  });

  group('CellAddress - labels', () {
    test('A1 label', () {
      expect(const CellAddress(0, 0).label, 'A1');
    });

    test('B3 label', () {
      expect(const CellAddress(1, 2).label, 'B3');
    });

    test('Z1 label', () {
      expect(const CellAddress(25, 0).label, 'Z1');
    });

    test('AA1 label', () {
      expect(const CellAddress(26, 0).label, 'AA1');
    });

    test('fromLabel parses A1', () {
      final addr = CellAddress.fromLabel('A1');
      expect(addr.column, 0);
      expect(addr.row, 0);
    });

    test('fromLabel parses B3', () {
      final addr = CellAddress.fromLabel('B3');
      expect(addr.column, 1);
      expect(addr.row, 2);
    });

    test('fromLabel handles dollar signs', () {
      final addr = CellAddress.fromLabel('\$C\$5');
      expect(addr.column, 2);
      expect(addr.row, 4);
    });

    test('fromLabel handles AA1', () {
      final addr = CellAddress.fromLabel('AA1');
      expect(addr.column, 26);
    });
  });

  group('CellAddress - equality and compareTo', () {
    test('equal addresses', () {
      expect(const CellAddress(0, 0), const CellAddress(0, 0));
    });

    test('compareTo orders by row then column', () {
      expect(
        const CellAddress(0, 0).compareTo(const CellAddress(0, 1)),
        lessThan(0),
      );
      expect(
        const CellAddress(0, 0).compareTo(const CellAddress(1, 0)),
        lessThan(0),
      );
    });
  });

  group('CellAddress - JSON', () {
    test('round-trips', () {
      const addr = CellAddress(5, 10);
      final json = addr.toJson();
      final restored = CellAddress.fromJson(json);
      expect(restored, addr);
    });
  });

  // ===========================================================================
  // CellRange
  // ===========================================================================

  group('CellRange - construction', () {
    test('stores start and end', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(2, 4));
      expect(range.columnCount, 3);
      expect(range.rowCount, 5);
    });
  });

  group('CellRange - fromLabel', () {
    test('parses A1:C5', () {
      final range = CellRange.fromLabel('A1:C5');
      expect(range.start, const CellAddress(0, 0));
      expect(range.end, const CellAddress(2, 4));
    });

    test('invalid label throws', () {
      expect(() => CellRange.fromLabel('A1'), throwsFormatException);
    });
  });

  group('CellRange - contains', () {
    test('contains inside address', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(2, 2));
      expect(range.contains(const CellAddress(1, 1)), isTrue);
    });

    test('does not contain outside address', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(2, 2));
      expect(range.contains(const CellAddress(3, 3)), isFalse);
    });
  });

  group('CellRange - addresses', () {
    test('yields all cells in row-major order', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(1, 1));
      final addrs = range.addresses.toList();
      expect(addrs.length, 4); // 2x2
      expect(addrs.first, const CellAddress(0, 0));
      expect(addrs.last, const CellAddress(1, 1));
    });
  });

  group('CellRange - JSON', () {
    test('round-trips', () {
      final range = CellRange(
        const CellAddress(0, 0),
        const CellAddress(5, 10),
      );
      final json = range.toJson();
      final restored = CellRange.fromJson(json);
      expect(restored, range);
    });
  });

  group('CellRange - label', () {
    test('A1:C5', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(2, 4));
      expect(range.label, 'A1:C5');
    });
  });
}
