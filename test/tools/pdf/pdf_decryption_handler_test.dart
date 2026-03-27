import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/tools/pdf/pdf_decryption_handler.dart';

void main() {
  group('PdfDecryptionHandler', () {
    late PdfDecryptionHandler handler;

    setUp(() {
      handler = PdfDecryptionHandler();
    });

    // =========================================================================
    // 1. Non-encrypted PDF passthrough
    // =========================================================================
    test('non-encrypted PDF returns as-is with full permissions', () {
      final pdf = Uint8List.fromList(
        utf8.encode(
          '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          'xref\n0 2\n0000000000 65535 f \n0000000009 00000 n \n'
          'trailer\n<< /Size 2 /Root 1 0 R >>\nstartxref\n48\n%%EOF\n',
        ),
      );

      final result = handler.tryDecrypt(pdf);

      expect(result, isNotNull);
      expect(result!.permissions.canPrint, isTrue);
      expect(result.permissions.canCopy, isTrue);
      expect(result.permissions.canModify, isTrue);
      expect(result.isOwnerAuthenticated, isFalse);
    });

    // =========================================================================
    // 2. isEncrypted detection
    // =========================================================================
    test('isEncrypted returns false for non-encrypted PDF', () {
      final pdf = Uint8List.fromList(
        utf8.encode(
          '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          'trailer\n<< /Root 1 0 R >>\n%%EOF\n',
        ),
      );

      expect(handler.isEncrypted(pdf), isFalse);
    });

    test('isEncrypted returns true when /Encrypt ref exists', () {
      final pdf = Uint8List.fromList(
        utf8.encode(
          '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          'trailer\n<< /Root 1 0 R /Encrypt 5 0 R >>\n%%EOF\n',
        ),
      );

      expect(handler.isEncrypted(pdf), isTrue);
    });

    // =========================================================================
    // 3. Permission flag parsing
    // =========================================================================
    test('PdfPermissions correctly parses flag bits', () {
      // Flags: print (bit 2) + copy (bit 4) = 4 + 16 = 20
      final perms = PdfPermissions.fromFlags(20);

      expect(perms.canPrint, isTrue);
      expect(perms.canCopy, isTrue);
      expect(perms.canModify, isFalse);
      expect(perms.canAnnotate, isFalse);
    });

    test('PdfPermissions.unrestricted allows everything', () {
      final perms = PdfPermissions.unrestricted;

      expect(perms.canPrint, isTrue);
      expect(perms.canModify, isTrue);
      expect(perms.canCopy, isTrue);
      expect(perms.canAnnotate, isTrue);
      expect(perms.canFillForms, isTrue);
      expect(perms.canExtractForAccessibility, isTrue);
      expect(perms.canAssemble, isTrue);
      expect(perms.canPrintHighQuality, isTrue);
    });

    // =========================================================================
    // 4. RC4 cipher correctness
    // =========================================================================
    test('RC4 encrypt and decrypt are symmetric', () {
      final handler = PdfDecryptionHandler();
      final key = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]);
      final plaintext = Uint8List.fromList(utf8.encode('Hello, World!'));

      // Access RC4 via a test wrapper.
      final encrypted = handler.rc4ForTest(key, plaintext);
      final decrypted = handler.rc4ForTest(key, encrypted);

      expect(decrypted, plaintext);
    });

    // =========================================================================
    // 5. MD5 hash correctness
    // =========================================================================
    test('MD5 produces correct hash for empty input', () {
      final handler = PdfDecryptionHandler();
      final hash = handler.md5ForTest(Uint8List(0));

      // MD5 of empty string = d41d8cd98f00b204e9800998ecf8427e
      final expected = 'd41d8cd98f00b204e9800998ecf8427e';
      final actual =
          hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      expect(actual, expected);
    });

    test('MD5 produces correct hash for "abc"', () {
      final handler = PdfDecryptionHandler();
      final hash = handler.md5ForTest(Uint8List.fromList(utf8.encode('abc')));

      // MD5 of "abc" = 900150983cd24fb0d6963f7d28e17f72
      final expected = '900150983cd24fb0d6963f7d28e17f72';
      final actual =
          hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      expect(actual, expected);
    });

    // =========================================================================
    // 6. extractPermissions from non-encrypted
    // =========================================================================
    test('extractPermissions returns unrestricted for non-encrypted', () {
      final pdf = Uint8List.fromList(
        utf8.encode('%PDF-1.4\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n'),
      );

      final perms = handler.extractPermissions(pdf);
      expect(perms, isNotNull);
      expect(perms!.canPrint, isTrue);
      expect(perms.canCopy, isTrue);
    });
  });
}
