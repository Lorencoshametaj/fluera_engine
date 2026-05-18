// ============================================================================
// 🤝 COLLAB INVITE LINK — DTO + parser tests
//
// Locks the deep-link contract so iOS Universal Links / Android App Links /
// in-app share-text handlers all stay coherent on the same wire format.
// ============================================================================

import 'package:fluera_engine/fluera_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toCustomSchemeUri', () {
    test('emits fluera://collab/<id>?token=...&role=editor for editors', () {
      const link = CollabInviteLink(
        canvasId: 'canvas-abc',
        token: 'tok-123',
        inviterPeerId: 'peer-xyz',
      );
      final uri = link.toCustomSchemeUri();
      expect(uri.scheme, 'fluera');
      expect(uri.host, 'collab');
      expect(uri.pathSegments, ['canvas-abc']);
      expect(uri.queryParameters['token'], 'tok-123');
      expect(uri.queryParameters['inviter'], 'peer-xyz');
      expect(uri.queryParameters['role'], 'editor');
    });

    test('omits inviter param when peer id is null', () {
      const link = CollabInviteLink(canvasId: 'c', token: 't');
      final uri = link.toCustomSchemeUri();
      expect(uri.queryParameters.containsKey('inviter'), isFalse);
    });

    test('emits role=viewer when constructed as viewer', () {
      const link = CollabInviteLink(
        canvasId: 'c',
        token: 't',
        role: CollabInviteRole.viewer,
      );
      expect(link.toCustomSchemeUri().queryParameters['role'], 'viewer');
    });
  });

  group('toUniversalUri', () {
    test('emits https://fluera.dev/collab/<id>?token=...', () {
      const link = CollabInviteLink(canvasId: 'c1', token: 'tk');
      final uri = link.toUniversalUri();
      expect(uri.scheme, 'https');
      expect(uri.host, 'fluera.dev');
      expect(uri.pathSegments, ['collab', 'c1']);
      expect(uri.queryParameters['token'], 'tk');
    });
  });

  group('tryParse — happy paths', () {
    test('parses a custom-scheme link with all fields', () {
      final uri = Uri.parse(
          'fluera://collab/canvas-1?token=t1&inviter=peer-1&role=viewer');
      final link = CollabInviteLink.tryParse(uri);
      expect(link, isNotNull);
      expect(link!.canvasId, 'canvas-1');
      expect(link.token, 't1');
      expect(link.inviterPeerId, 'peer-1');
      expect(link.role, CollabInviteRole.viewer);
    });

    test('parses a universal link with all fields', () {
      final uri = Uri.parse(
          'https://fluera.dev/collab/canvas-2?token=t2&inviter=p2&role=editor');
      final link = CollabInviteLink.tryParse(uri);
      expect(link, isNotNull);
      expect(link!.canvasId, 'canvas-2');
      expect(link.token, 't2');
      expect(link.role, CollabInviteRole.editor);
    });

    test('defaults role to editor when omitted', () {
      final uri = Uri.parse('fluera://collab/c?token=t');
      final link = CollabInviteLink.tryParse(uri);
      expect(link, isNotNull);
      expect(link!.role, CollabInviteRole.editor);
    });

    test('round-trips: build → parse preserves all fields', () {
      const original = CollabInviteLink(
        canvasId: 'roundtrip-canvas',
        token: 'roundtrip-token',
        inviterPeerId: 'roundtrip-peer',
        role: CollabInviteRole.viewer,
      );
      final parsedCustom = CollabInviteLink.tryParse(original.toCustomSchemeUri());
      final parsedUniversal =
          CollabInviteLink.tryParse(original.toUniversalUri());

      for (final p in [parsedCustom, parsedUniversal]) {
        expect(p, isNotNull, reason: 'round-trip lost the link');
        expect(p!.canvasId, original.canvasId);
        expect(p.token, original.token);
        expect(p.inviterPeerId, original.inviterPeerId);
        expect(p.role, original.role);
      }
    });
  });

  group('tryParse — rejection cases', () {
    test('returns null on wrong scheme', () {
      expect(CollabInviteLink.tryParse(Uri.parse('http://collab/c?token=t')),
          isNull);
      expect(
          CollabInviteLink.tryParse(Uri.parse('mailto:foo@example.com?token=t')),
          isNull);
    });

    test('returns null on wrong host', () {
      expect(CollabInviteLink.tryParse(Uri.parse('fluera://other/c?token=t')),
          isNull);
      expect(
          CollabInviteLink.tryParse(
              Uri.parse('https://example.com/collab/c?token=t')),
          isNull);
    });

    test('returns null when canvas id is missing', () {
      expect(CollabInviteLink.tryParse(Uri.parse('fluera://collab?token=t')),
          isNull);
      expect(
          CollabInviteLink.tryParse(Uri.parse('https://fluera.dev/collab?token=t')),
          isNull);
    });

    test('returns null when token is missing or empty', () {
      expect(CollabInviteLink.tryParse(Uri.parse('fluera://collab/c')), isNull);
      expect(CollabInviteLink.tryParse(Uri.parse('fluera://collab/c?token=')),
          isNull);
    });

    test('falls back to editor on an unknown role value', () {
      final uri = Uri.parse('fluera://collab/c?token=t&role=admin');
      final link = CollabInviteLink.tryParse(uri);
      expect(link, isNotNull);
      expect(link!.role, CollabInviteRole.editor,
          reason: 'Unknown role string must default to editor, not throw');
    });
  });

  group('Scheme + host constants', () {
    test('exposes canonical scheme + host for native deep-link config', () {
      expect(CollabInviteLink.customScheme, 'fluera');
      expect(CollabInviteLink.customHost, 'collab');
      expect(CollabInviteLink.universalHost, 'fluera.dev');
    });
  });

  group('V1FeatureGate flag', () {
    test('collaboration compile flag is enabled (V1 launch 2026-05-14)', () {
      expect(V1FeatureGate.collaboration, isTrue);
    });
  });
}
