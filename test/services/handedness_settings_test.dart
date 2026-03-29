import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/handedness_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HandednessSettings — Multi-point Palm Rejection', () {
    late HandednessSettings settings;

    setUp(() {
      // Mock HapticFeedback platform channel to avoid MissingPluginException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async => null,
      );

      // Use the singleton but reset its state for testing
      settings = HandednessSettings.instance;
      settings.palmRejectionEnabled = true;
      settings.clearRecentFingerDownTimestamps();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('registerFingerDown returns false for single touch', () {
      final result = settings.registerFingerDown();
      expect(result, isFalse, reason: 'Single touch should not be rejected');
    });

    test('registerFingerDown returns true for 2 rapid touches', () {
      settings.registerFingerDown(); // First touch
      final result = settings.registerFingerDown(); // Second within 80ms
      expect(result, isTrue,
          reason: '2 touches within 80ms should trigger multi-point rejection');
    });

    test('clearRecentFingerDownTimestamps prevents cross-gesture contamination',
        () {
      settings.registerFingerDown(); // First touch of gesture 1
      settings.clearRecentFingerDownTimestamps(); // Gesture ends

      // New gesture starts — first touch should NOT be rejected
      final result = settings.registerFingerDown();
      expect(result, isFalse,
          reason: 'First touch of new gesture should not be rejected '
              'after clearing timestamps');
    });

    test(
        'velocity-rejected touch does NOT contaminate multi-point detection', () {
      // Simulate: first finger rejected by velocity check (slow + large area)
      // After the fix, registerFingerDown() runs AFTER all other checks,
      // so a velocity-rejected touch never registers a timestamp.

      final rejected = settings.shouldRejectTouch(
        position: const Offset(400, 400), // Center of screen (not in zone)
        radiusMajor: 25.0, // Large contact area (> _learnedPalmThreshold)
        radiusMinor: 20.0, // Roughly circular
        screenSize: const Size(800, 1200),
        speed: 0.1, // Near-zero velocity → triggers velocity check
      );

      // The touch should be rejected by velocity check
      expect(rejected, isTrue,
          reason: 'Slow touch with large area should be velocity-rejected');

      // KEY ASSERTION: The rejected touch should NOT have registered
      // a timestamp. A subsequent single finger-down should pass.
      final secondTouchResult = settings.registerFingerDown();
      expect(secondTouchResult, isFalse,
          reason: 'A velocity-rejected touch should not register a '
              'timestamp that contaminates the next touch');
    });

    test('shouldRejectTouch returns false for normal touch in center', () {
      final rejected = settings.shouldRejectTouch(
        position: const Offset(400, 600), // Center of screen
        radiusMajor: 10.0, // Small fingertip
        radiusMinor: 8.0,
        screenSize: const Size(800, 1200),
        speed: 5.0, // Normal speed
      );
      expect(rejected, isFalse,
          reason: 'Normal fingertip touch in center should pass');
    });
  });
}
