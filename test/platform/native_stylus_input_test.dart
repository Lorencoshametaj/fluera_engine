import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/platform/native_stylus_input.dart';
import 'package:fluera_engine/src/core/engine_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    EngineScope.reset();
  });

  tearDown(() {
    EngineScope.reset();
  });

  // =========================================================================
  // Initial State
  // =========================================================================

  group('initial state', () {
    test('starts uninitialized', () {
      final stylus = NativeStylusInput.create();
      expect(stylus.isInitialized, isFalse);
      expect(stylus.isStylusSupported, isFalse);
      expect(stylus.capabilities, isNull);
    });
  });

  // =========================================================================
  // Data Models
  // =========================================================================

  group('StylusHoverEvent', () {
    test('creates with required fields', () {
      const event = StylusHoverEvent(
        x: 100.0,
        y: 200.0,
        state: HoverState.began,
        isHovering: true,
        timestamp: 12345,
      );
      expect(event.x, 100.0);
      expect(event.y, 200.0);
      expect(event.state, HoverState.began);
      expect(event.isHovering, isTrue);
      expect(event.altitude, isNull);
      expect(event.distance, isNull);
    });

    test('creates with optional tilt and altitude', () {
      const event = StylusHoverEvent(
        x: 50.0,
        y: 75.0,
        state: HoverState.changed,
        isHovering: true,
        altitude: 1.2,
        distance: 5.0,
        tiltX: 0.3,
        orientation: 1.5,
        timestamp: 67890,
      );
      expect(event.altitude, 1.2);
      expect(event.distance, 5.0);
      expect(event.tiltX, 0.3);
      expect(event.orientation, 1.5);
    });

    test('toString is readable', () {
      const event = StylusHoverEvent(
        x: 10.0,
        y: 20.0,
        state: HoverState.ended,
        isHovering: false,
        timestamp: 0,
      );
      expect(event.toString(), contains('StylusHoverEvent'));
      expect(event.toString(), contains('ended'));
    });
  });

  group('StylusMetadataEvent', () {
    test('creates with required fields', () {
      const event = StylusMetadataEvent(
        x: 150.0,
        y: 250.0,
        pressure: 0.8,
        isButtonPressed: false,
        action: 'move',
        timestamp: 11111,
      );
      expect(event.x, 150.0);
      expect(event.y, 250.0);
      expect(event.pressure, 0.8);
      expect(event.isButtonPressed, isFalse);
      expect(event.action, 'move');
    });

    test('creates with tilt and button pressed', () {
      const event = StylusMetadataEvent(
        x: 100.0,
        y: 100.0,
        pressure: 0.5,
        tiltX: 0.2,
        orientation: 1.0,
        altitude: 1.4,
        isButtonPressed: true,
        action: 'down',
        timestamp: 22222,
      );
      expect(event.tiltX, 0.2);
      expect(event.orientation, 1.0);
      expect(event.altitude, 1.4);
      expect(event.isButtonPressed, isTrue);
    });

    test('toString is readable', () {
      const event = StylusMetadataEvent(
        x: 10.0,
        y: 20.0,
        pressure: 0.5,
        isButtonPressed: true,
        action: 'move',
        timestamp: 0,
      );
      expect(event.toString(), contains('StylusMetadataEvent'));
      expect(event.toString(), contains('button: true'));
    });
  });

  group('StylusCapabilities', () {
    test('creates without device name', () {
      const caps = StylusCapabilities(
        hasStylusSupport: true,
        hasTilt: true,
        hasPressure: true,
        hasPalmRejection: true,
        hasHover: true,
        hasButton: true,
        platform: 'iOS',
      );
      expect(caps.hasStylusSupport, isTrue);
      expect(caps.platform, 'iOS');
      expect(caps.deviceName, isNull);
    });

    test('creates with device name', () {
      const caps = StylusCapabilities(
        hasStylusSupport: true,
        hasTilt: true,
        hasPressure: true,
        hasPalmRejection: true,
        hasHover: true,
        hasButton: true,
        platform: 'Android',
        deviceName: 'Samsung S Pen',
      );
      expect(caps.deviceName, 'Samsung S Pen');
    });

    test('toString includes platform and features', () {
      const caps = StylusCapabilities(
        hasStylusSupport: true,
        hasTilt: false,
        hasPressure: true,
        hasPalmRejection: false,
        hasHover: true,
        hasButton: false,
        platform: 'Android',
      );
      final str = caps.toString();
      expect(str, contains('Android'));
      expect(str, contains('stylus: true'));
      expect(str, contains('hover: true'));
    });
  });

  // =========================================================================
  // HoverState enum
  // =========================================================================

  group('HoverState', () {
    test('has three states', () {
      expect(HoverState.values.length, 3);
      expect(HoverState.values, contains(HoverState.began));
      expect(HoverState.values, contains(HoverState.changed));
      expect(HoverState.values, contains(HoverState.ended));
    });
  });

  // =========================================================================
  // Reset for Testing
  // =========================================================================

  group('resetForTesting', () {
    test('resets all state', () {
      final stylus = NativeStylusInput.create();
      stylus.resetForTesting();
      expect(stylus.isInitialized, isFalse);
      expect(stylus.isStylusSupported, isFalse);
      expect(stylus.capabilities, isNull);
    });
  });
}
