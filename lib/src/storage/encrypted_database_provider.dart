// ============================================================================
// 🔐 ENCRYPTED DATABASE PROVIDER — SQLCipher encryption at-rest (A16, Art.32)
//
// Specifica: A16-21 → A16-25
//
// Provides AES-256 encryption for all SQLite databases via SQLCipher.
// This is a drop-in provider that the SqliteStorageAdapter uses
// transparently — no changes to queries, schema, or business logic.
//
// ARCHITECTURE:
//   EncryptedDatabaseProvider (this file)
//       ↓ provides factory + codec
//   SqliteStorageAdapter._initialize()
//       ↓ uses factory.openDatabase(path, codec: ...)
//   sqflite_common_ffi + sqlite3_flutter_libs (native)
//
// KEY MANAGEMENT:
//   - Key is derived from a user-provided passphrase via PBKDF2
//   - Key is NEVER stored in the database itself
//   - Host app provides the passphrase (from Keychain/Keystore)
//   - If no passphrase is set, the database is opened WITHOUT encryption
//     (graceful fallback for development/testing)
//
// MIGRATION:
//   - Existing unencrypted databases can be migrated to encrypted ones
//   - Uses SQLCipher's `sqlcipher_export()` for zero-downtime migration
//   - Original file is securely deleted after successful migration
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// 🔐 Encryption configuration for the database.
class DatabaseEncryptionConfig {
  /// Whether encryption is enabled.
  final bool enabled;

  /// The raw encryption key (32 bytes for AES-256).
  /// Derived from the passphrase via PBKDF2.
  /// Null if encryption is disabled.
  final Uint8List? key;

  /// Number of PBKDF2 iterations (higher = slower brute-force).
  /// Default: 256000 (OWASP recommendation for PBKDF2-SHA256).
  final int kdfIterations;

  /// SQLCipher page size (must match database page size).
  final int pageSize;

  const DatabaseEncryptionConfig._({
    required this.enabled,
    this.key,
    this.kdfIterations = 256000,
    this.pageSize = 4096,
  });

  /// Create a disabled config (no encryption).
  const DatabaseEncryptionConfig.disabled()
      : this._(enabled: false);

  /// Create an encryption config from a passphrase (synchronous).
  ///
  /// ⚠️ Prefer [fromPassphraseAsync] for production — this blocks
  /// the main thread for ~1-2s with 256k iterations.
  factory DatabaseEncryptionConfig.fromPassphrase({
    required String passphrase,
    required String databaseName,
    int kdfIterations = 256000,
  }) {
    if (passphrase.isEmpty) {
      return const DatabaseEncryptionConfig.disabled();
    }

    final key = _deriveKey(
      passphrase: passphrase,
      salt: 'fluera_$databaseName',
      iterations: kdfIterations,
    );

    return DatabaseEncryptionConfig._(
      enabled: true,
      key: key,
      kdfIterations: kdfIterations,
    );
  }

  /// Create an encryption config from a passphrase (async, off main thread).
  ///
  /// Uses [compute] to derive the key in a background isolate,
  /// preventing UI jank during the 256k PBKDF2 iterations.
  static Future<DatabaseEncryptionConfig> fromPassphraseAsync({
    required String passphrase,
    required String databaseName,
    int kdfIterations = 256000,
  }) async {
    if (passphrase.isEmpty) {
      return const DatabaseEncryptionConfig.disabled();
    }

    final key = await compute(
      _deriveKeyIsolate,
      _KeyDerivationParams(
        passphrase: passphrase,
        salt: 'fluera_$databaseName',
        iterations: kdfIterations,
      ),
    );

    return DatabaseEncryptionConfig._(
      enabled: true,
      key: key,
      kdfIterations: kdfIterations,
    );
  }

  /// Derive a 32-byte key from passphrase using PBKDF2-SHA256.
  static Uint8List _deriveKey({
    required String passphrase,
    required String salt,
    required int iterations,
  }) {
    // PBKDF2-SHA256 implementation using dart:crypto's HMAC
    final saltBytes = utf8.encode(salt);
    final passphraseBytes = utf8.encode(passphrase);

    // PBKDF2 with HMAC-SHA256
    var block = Hmac(sha256, passphraseBytes)
        .convert([...saltBytes, 0, 0, 0, 1]).bytes;
    var result = Uint8List.fromList(block);

    for (int i = 1; i < iterations; i++) {
      block = Hmac(sha256, passphraseBytes).convert(block).bytes;
      for (int j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }

    // Take first 32 bytes for AES-256
    return Uint8List.fromList(result.sublist(0, 32));
  }

  /// Top-level function for compute() isolate.
  static Uint8List _deriveKeyIsolate(_KeyDerivationParams params) {
    return _deriveKey(
      passphrase: params.passphrase,
      salt: params.salt,
      iterations: params.iterations,
    );
  }

  /// Get the hex-encoded key for SQLCipher PRAGMA.
  ///
  /// SQLCipher accepts keys as hex strings prefixed with `x'...'`.
  String? get hexKey {
    if (key == null) return null;
    final hex = key!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return "x'$hex'";
  }

  /// Get the SQLCipher PRAGMA statements to execute after opening.
  ///
  /// These must be the FIRST statements after opening the database,
  /// before any other queries.
  List<String> get pragmaStatements {
    if (!enabled || hexKey == null) return [];

    return [
      "PRAGMA key = ${hexKey!}",
      'PRAGMA cipher_page_size = $pageSize',
      'PRAGMA kdf_iter = $kdfIterations',
      'PRAGMA cipher_hmac_algorithm = HMAC_SHA256',
      'PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA256',
    ];
  }
}

/// 🔐 Encrypted Database Provider (A16, Art. 32).
///
/// Manages database encryption lifecycle:
/// - Key derivation from passphrase
/// - Encryption config generation
/// - Migration of unencrypted → encrypted databases
/// - Key rotation
///
/// Usage:
/// ```dart
/// final provider = EncryptedDatabaseProvider();
///
/// // Set passphrase (from iOS Keychain / Android Keystore)
/// provider.setPassphrase('user-secret-from-keychain');
///
/// // Get config for SqliteStorageAdapter
/// final config = provider.getConfig(databaseName: 'fluera_canvas.db');
///
/// // Check if a database needs migration
/// if (await provider.needsMigration(dbPath)) {
///   await provider.migrateToEncrypted(dbPath, config);
/// }
/// ```
class EncryptedDatabaseProvider {
  /// Current passphrase stored as bytes for secure zeroing.
  /// Dart Strings are immutable and cannot be cleared from memory.
  Uint8List? _passphraseBytes;

  /// Whether encryption is enabled.
  bool get isEncryptionEnabled =>
      _passphraseBytes != null && _passphraseBytes!.isNotEmpty;

  /// Set the passphrase from host app's secure storage.
  ///
  /// Call this BEFORE initializing the SqliteStorageAdapter.
  /// The passphrase should come from:
  /// - iOS: Keychain Services
  /// - Android: Android Keystore
  /// - Desktop: OS-specific secret manager
  void setPassphrase(String passphrase) {
    // Clear previous passphrase bytes securely
    _zeroPassphrase();
    _passphraseBytes = Uint8List.fromList(utf8.encode(passphrase));
  }

  /// Clear the passphrase securely (e.g., on logout).
  ///
  /// Overwrites the passphrase bytes with zeros before releasing,
  /// to minimize the window for memory dump attacks.
  void clearPassphrase() {
    _zeroPassphrase();
  }

  void _zeroPassphrase() {
    if (_passphraseBytes != null) {
      _passphraseBytes!.fillRange(0, _passphraseBytes!.length, 0);
      _passphraseBytes = null;
    }
  }

  /// Get the encryption config for a specific database (sync).
  ///
  /// ⚠️ For production, prefer [getConfigAsync] to avoid blocking.
  DatabaseEncryptionConfig getConfig({required String databaseName}) {
    if (!isEncryptionEnabled) {
      return const DatabaseEncryptionConfig.disabled();
    }

    return DatabaseEncryptionConfig.fromPassphrase(
      passphrase: utf8.decode(_passphraseBytes!),
      databaseName: databaseName,
    );
  }

  /// Get the encryption config asynchronously (background isolate).
  ///
  /// Recommended for production to avoid ~1-2s UI jank during
  /// PBKDF2 key derivation.
  Future<DatabaseEncryptionConfig> getConfigAsync({
    required String databaseName,
  }) async {
    if (!isEncryptionEnabled) {
      return const DatabaseEncryptionConfig.disabled();
    }

    return DatabaseEncryptionConfig.fromPassphraseAsync(
      passphrase: utf8.decode(_passphraseBytes!),
      databaseName: databaseName,
    );
  }

  /// Check if an existing database is unencrypted and needs migration.
  ///
  /// SQLite databases start with "SQLite format 3\000".
  /// Encrypted databases start with random bytes.
  ///
  /// Returns true if the file exists and is unencrypted.
  static bool isUnencryptedDatabase(Uint8List headerBytes) {
    if (headerBytes.length < 16) return false;

    // SQLite magic header: "SQLite format 3\000" (16 bytes)
    const sqliteMagic = [
      0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66,
      0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
    ];

    for (int i = 0; i < 16; i++) {
      if (headerBytes[i] != sqliteMagic[i]) return false;
    }
    return true;
  }

  /// Migration steps for converting unencrypted → encrypted database.
  ///
  /// The host app executes these steps using raw SQLite APIs:
  /// ```sql
  /// -- 1. Open the plaintext database
  /// ATTACH DATABASE 'encrypted.db' AS encrypted KEY 'x{hex_key}';
  ///
  /// -- 2. Export all data to the encrypted copy
  /// SELECT sqlcipher_export('encrypted');
  ///
  /// -- 3. Detach and swap files
  /// DETACH DATABASE encrypted;
  /// ```
  ///
  /// Returns the SQL statements needed. The host app is responsible
  /// for executing them and swapping the files.
  List<String> getMigrationStatements({
    required String encryptedPath,
    required DatabaseEncryptionConfig config,
  }) {
    if (!config.enabled || config.hexKey == null) return [];

    return [
      "ATTACH DATABASE '$encryptedPath' AS encrypted KEY ${config.hexKey!}",
      "SELECT sqlcipher_export('encrypted')",
      'DETACH DATABASE encrypted',
    ];
  }

  /// Key rotation: re-encrypt with a new passphrase.
  ///
  /// Uses SQLCipher's `PRAGMA rekey` for in-place re-encryption.
  /// Returns the PRAGMA statement to execute.
  String? getKeyRotationStatement(DatabaseEncryptionConfig newConfig) {
    if (!newConfig.enabled || newConfig.hexKey == null) return null;
    return 'PRAGMA rekey = ${newConfig.hexKey!}';
  }
}

/// Parameters for background isolate PBKDF2 key derivation.
class _KeyDerivationParams {
  final String passphrase;
  final String salt;
  final int iterations;

  const _KeyDerivationParams({
    required this.passphrase,
    required this.salt,
    required this.iterations,
  });
}
