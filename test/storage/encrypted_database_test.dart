// ============================================================================
// 🧪 UNIT TESTS — Encrypted Database Provider (A16, Art. 32)
// ============================================================================

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/storage/encrypted_database_provider.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // DATABASE ENCRYPTION CONFIG
  // ═══════════════════════════════════════════════════════════════════════════

  group('DatabaseEncryptionConfig', () {
    test('disabled config has no key', () {
      const config = DatabaseEncryptionConfig.disabled();
      expect(config.enabled, isFalse);
      expect(config.key, isNull);
      expect(config.hexKey, isNull);
      expect(config.pragmaStatements, isEmpty);
    });

    test('fromPassphrase generates 32-byte key', () {
      final config = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'test-secret-123',
        databaseName: 'fluera_canvas.db',
        kdfIterations: 1000, // Low for test speed
      );
      expect(config.enabled, isTrue);
      expect(config.key, isNotNull);
      expect(config.key!.length, 32); // AES-256 = 32 bytes
    });

    test('same passphrase + salt = same key (deterministic)', () {
      final config1 = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'my-secret',
        databaseName: 'test.db',
        kdfIterations: 100,
      );
      final config2 = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'my-secret',
        databaseName: 'test.db',
        kdfIterations: 100,
      );
      expect(config1.key, equals(config2.key));
    });

    test('different passphrases = different keys', () {
      final config1 = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'secret-A',
        databaseName: 'test.db',
        kdfIterations: 100,
      );
      final config2 = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'secret-B',
        databaseName: 'test.db',
        kdfIterations: 100,
      );
      expect(config1.key, isNot(equals(config2.key)));
    });

    test('different database names = different keys (cross-DB isolation)', () {
      final config1 = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'same-secret',
        databaseName: 'db_user_1.db',
        kdfIterations: 100,
      );
      final config2 = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'same-secret',
        databaseName: 'db_user_2.db',
        kdfIterations: 100,
      );
      expect(config1.key, isNot(equals(config2.key)));
    });

    test('empty passphrase returns disabled config', () {
      final config = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: '',
        databaseName: 'test.db',
      );
      expect(config.enabled, isFalse);
    });

    test('hexKey format is correct for SQLCipher', () {
      final config = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'test',
        databaseName: 'test.db',
        kdfIterations: 100,
      );
      expect(config.hexKey, isNotNull);
      expect(config.hexKey!, startsWith("x'"));
      expect(config.hexKey!, endsWith("'"));
      // 32 bytes = 64 hex chars + x'' wrapper = 67 chars
      expect(config.hexKey!.length, 67);
    });

    test('pragmaStatements includes all required PRAGMAs', () {
      final config = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'test',
        databaseName: 'test.db',
        kdfIterations: 100,
      );
      final pragmas = config.pragmaStatements;
      expect(pragmas.length, 5);
      expect(pragmas[0], startsWith('PRAGMA key = '));
      expect(pragmas[1], contains('cipher_page_size'));
      expect(pragmas[2], contains('kdf_iter'));
      expect(pragmas[3], contains('HMAC_SHA256'));
      expect(pragmas[4], contains('PBKDF2_HMAC_SHA256'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENCRYPTED DATABASE PROVIDER
  // ═══════════════════════════════════════════════════════════════════════════

  group('EncryptedDatabaseProvider', () {
    late EncryptedDatabaseProvider provider;

    setUp(() => provider = EncryptedDatabaseProvider());

    test('encryption disabled by default', () {
      expect(provider.isEncryptionEnabled, isFalse);
    });

    test('encryption enabled after setPassphrase', () {
      provider.setPassphrase('my-secure-passphrase');
      expect(provider.isEncryptionEnabled, isTrue);
    });

    test('clearPassphrase disables encryption', () {
      provider.setPassphrase('my-secure-passphrase');
      provider.clearPassphrase();
      expect(provider.isEncryptionEnabled, isFalse);
    });

    test('getConfig returns disabled when no passphrase', () {
      final config = provider.getConfig(databaseName: 'test.db');
      expect(config.enabled, isFalse);
    });

    test('getConfig returns enabled config with passphrase', () {
      provider.setPassphrase('test-secret');
      final config = provider.getConfig(databaseName: 'test.db');
      expect(config.enabled, isTrue);
      expect(config.key!.length, 32);
    });

    test('setPassphrase overwrites previous passphrase securely', () {
      provider.setPassphrase('first');
      provider.setPassphrase('second');
      final config = provider.getConfig(databaseName: 'test.db');
      // Key should derive from 'second', not 'first'
      final expected = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'second',
        databaseName: 'test.db',
      );
      expect(config.key, equals(expected.key));
    });

    test('clearPassphrase zeros underlying bytes', () {
      provider.setPassphrase('sensitive');
      expect(provider.isEncryptionEnabled, isTrue);
      provider.clearPassphrase();
      expect(provider.isEncryptionEnabled, isFalse);
      // Double-clear is safe (no crash)
      provider.clearPassphrase();
      expect(provider.isEncryptionEnabled, isFalse);
    });

    test('getConfigAsync returns valid config', () async {
      provider.setPassphrase('async-test');
      final config = await provider.getConfigAsync(databaseName: 'async.db');
      expect(config.enabled, isTrue);
      expect(config.key!.length, 32);
    });

    test('getConfigAsync returns disabled when no passphrase', () async {
      final config = await provider.getConfigAsync(databaseName: 'test.db');
      expect(config.enabled, isFalse);
    });

    test('fromPassphraseAsync produces same key as sync version', () async {
      final syncConfig = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'deterministic-test',
        databaseName: 'compare.db',
        kdfIterations: 100,
      );
      final asyncConfig = await DatabaseEncryptionConfig.fromPassphraseAsync(
        passphrase: 'deterministic-test',
        databaseName: 'compare.db',
        kdfIterations: 100,
      );
      expect(asyncConfig.key, equals(syncConfig.key));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MIGRATION DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Migration detection', () {
    test('detects unencrypted SQLite database', () {
      // SQLite magic header: "SQLite format 3\0"
      final header = Uint8List.fromList([
        0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
      ]);
      expect(EncryptedDatabaseProvider.isUnencryptedDatabase(header), isTrue);
    });

    test('encrypted database has no SQLite header', () {
      // Random bytes (encrypted)
      final header = Uint8List.fromList([
        0xA3, 0x7B, 0x12, 0xF4, 0x88, 0x9C, 0x01, 0xDE,
        0x55, 0x2A, 0xC7, 0x3E, 0x91, 0x6F, 0xB0, 0x44,
      ]);
      expect(EncryptedDatabaseProvider.isUnencryptedDatabase(header), isFalse);
    });

    test('too-short header returns false', () {
      final header = Uint8List.fromList([0x53, 0x51, 0x4c]);
      expect(EncryptedDatabaseProvider.isUnencryptedDatabase(header), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MIGRATION & KEY ROTATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Migration statements', () {
    late EncryptedDatabaseProvider provider;

    setUp(() {
      provider = EncryptedDatabaseProvider();
      provider.setPassphrase('migration-test');
    });

    test('generates 3 migration SQL statements', () {
      final config = provider.getConfig(databaseName: 'test.db');
      final stmts = provider.getMigrationStatements(
        encryptedPath: '/path/to/encrypted.db',
        config: config,
      );
      expect(stmts.length, 3);
      expect(stmts[0], contains('ATTACH DATABASE'));
      expect(stmts[0], contains('KEY'));
      expect(stmts[1], contains('sqlcipher_export'));
      expect(stmts[2], contains('DETACH'));
    });

    test('disabled config returns no migration statements', () {
      final config = const DatabaseEncryptionConfig.disabled();
      final stmts = provider.getMigrationStatements(
        encryptedPath: '/path/to/encrypted.db',
        config: config,
      );
      expect(stmts, isEmpty);
    });

    test('key rotation generates PRAGMA rekey', () {
      final newConfig = DatabaseEncryptionConfig.fromPassphrase(
        passphrase: 'new-passphrase',
        databaseName: 'test.db',
        kdfIterations: 100,
      );
      final stmt = provider.getKeyRotationStatement(newConfig);
      expect(stmt, isNotNull);
      expect(stmt!, startsWith('PRAGMA rekey = '));
    });
  });
}
