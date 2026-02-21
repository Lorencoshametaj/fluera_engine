/// 🔌 PLUGIN SIGNING SERVICE — Integrity verification via HMAC-SHA256.
///
/// Signs plugin bundles and verifies their integrity to prevent tampering.
///
/// ```dart
/// final service = PluginSigningService(secretKey: 'my-secret');
/// final bundle = service.sign(manifest: manifest, contentHash: 'abc123');
/// final valid = service.verify(bundle);
/// ```
library;

import 'dart:convert';

import 'plugin_manifest_schema.dart';

// =============================================================================
// SIGNED BUNDLE
// =============================================================================

/// A signed plugin bundle containing manifest + content hash + signature.
class SignedBundle {
  /// The marketplace manifest.
  final MarketplaceManifest manifest;

  /// SHA-256 hash of the plugin content.
  final String contentHash;

  /// HMAC-SHA256 signature.
  final String signature;

  /// Signing timestamp (epoch ms).
  final int signedAtMs;

  /// Signer identity.
  final String signerId;

  const SignedBundle({
    required this.manifest,
    required this.contentHash,
    required this.signature,
    required this.signedAtMs,
    this.signerId = 'system',
  });

  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'contentHash': contentHash,
    'signature': signature,
    'signedAtMs': signedAtMs,
    'signerId': signerId,
  };

  factory SignedBundle.fromJson(Map<String, dynamic> json) => SignedBundle(
    manifest: MarketplaceManifest.fromJson(
      json['manifest'] as Map<String, dynamic>,
    ),
    contentHash: json['contentHash'] as String,
    signature: json['signature'] as String,
    signedAtMs: json['signedAtMs'] as int,
    signerId: json['signerId'] as String? ?? 'system',
  );

  @override
  String toString() =>
      'SignedBundle(${manifest.id} v${manifest.version}, signer=$signerId)';
}

// =============================================================================
// VERIFICATION RESULT
// =============================================================================

/// Result of verifying a signed bundle.
class VerificationResult {
  final bool valid;
  final String? error;

  const VerificationResult.valid() : valid = true, error = null;
  const VerificationResult.invalid(this.error) : valid = false;

  @override
  String toString() => valid ? 'VALID' : 'INVALID: $error';
}

// =============================================================================
// PLUGIN SIGNING SERVICE
// =============================================================================

/// Signs and verifies plugin bundles using HMAC-SHA256.
///
/// Uses a simplified HMAC implementation (no dart:crypto dependency).
/// In production, replace _hmac with a real HMAC-SHA256 from package:crypto.
class PluginSigningService {
  /// Secret key for signing.
  final String _secretKey;

  /// Signer identity.
  final String signerId;

  const PluginSigningService({
    required String secretKey,
    this.signerId = 'system',
  }) : _secretKey = secretKey;

  /// Sign a plugin bundle.
  SignedBundle sign({
    required MarketplaceManifest manifest,
    required String contentHash,
  }) {
    final payload = _buildPayload(manifest, contentHash);
    final signature = _hmac(payload, _secretKey);

    return SignedBundle(
      manifest: manifest,
      contentHash: contentHash,
      signature: signature,
      signedAtMs: DateTime.now().millisecondsSinceEpoch,
      signerId: signerId,
    );
  }

  /// Verify a signed bundle.
  VerificationResult verify(SignedBundle bundle) {
    // Check manifest validity
    final errors = ManifestValidator.validate(bundle.manifest);
    final criticalErrors =
        errors.where((e) => e.severity == ManifestErrorSeverity.error).toList();
    if (criticalErrors.isNotEmpty) {
      return VerificationResult.invalid(
        'Manifest invalid: ${criticalErrors.first.message}',
      );
    }

    // Check content hash
    if (bundle.contentHash.isEmpty) {
      return const VerificationResult.invalid('Content hash is empty');
    }

    // Verify signature
    final payload = _buildPayload(bundle.manifest, bundle.contentHash);
    final expectedSig = _hmac(payload, _secretKey);
    if (bundle.signature != expectedSig) {
      return const VerificationResult.invalid(
        'Signature mismatch — content may have been tampered with',
      );
    }

    return const VerificationResult.valid();
  }

  /// Build the signing payload from manifest + content hash.
  static String _buildPayload(
    MarketplaceManifest manifest,
    String contentHash,
  ) {
    return '${manifest.id}:${manifest.version}:$contentHash';
  }

  /// Simplified HMAC (FNV-1a based). In production use package:crypto.
  static String _hmac(String message, String key) {
    final combined = '$key:$message';
    var hash = 0xcbf29ce484222325; // FNV offset basis (64-bit)
    for (int i = 0; i < combined.length; i++) {
      hash ^= combined.codeUnitAt(i);
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF; // FNV prime
    }
    // Format as hex string
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
