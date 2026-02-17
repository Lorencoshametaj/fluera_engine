import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/platform/native_vibration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;

  setUp(() {
    log = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('nebulaengine.vibration/method'),
          (MethodCall methodCall) async {
            log.add(methodCall);
            switch (methodCall.method) {
              case 'hasVibrator':
                return true;
              case 'vibrate':
                return null;
              case 'cancel':
                return null;
              default:
                return null;
            }
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('nebulaengine.vibration/method'),
          null,
        );
  });

  // =========================================================================
  // hasVibrator
  // =========================================================================

  group('hasVibrator', () {
    test('returns true when platform reports vibrator', () async {
      final result = await NativeVibration.hasVibrator();
      expect(result, isTrue);
      expect(log.last.method, 'hasVibrator');
    });

    test('returns null on platform exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('nebulaengine.vibration/method'),
            (_) => throw PlatformException(code: 'UNAVAILABLE'),
          );
      final result = await NativeVibration.hasVibrator();
      expect(result, isNull);
    });
  });

  // =========================================================================
  // vibrate
  // =========================================================================

  group('vibrate', () {
    test('simple vibration sends correct method', () async {
      await NativeVibration.vibrate(duration: 200);
      expect(log.last.method, 'vibrate');
      expect(log.last.arguments['duration'], 200);
    });

    test('vibration with amplitude sends both params', () async {
      await NativeVibration.vibrate(duration: 300, amplitude: 128);
      expect(log.last.arguments['duration'], 300);
      expect(log.last.arguments['amplitude'], 128);
    });

    test('pattern vibration sends pattern array', () async {
      await NativeVibration.vibrate(pattern: [0, 100, 50, 100]);
      expect(log.last.arguments['pattern'], [0, 100, 50, 100]);
    });

    test('pattern with intensities sends both', () async {
      await NativeVibration.vibrate(
        pattern: [0, 100, 50, 100],
        intensities: [255, 128],
      );
      expect(log.last.arguments['pattern'], [0, 100, 50, 100]);
      expect(log.last.arguments['intensities'], [255, 128]);
    });

    test('rejects amplitude below 0', () {
      expect(
        () => NativeVibration.vibrate(amplitude: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects amplitude above 255', () {
      expect(
        () => NativeVibration.vibrate(amplitude: 256),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty pattern', () {
      expect(
        () => NativeVibration.vibrate(pattern: []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative pattern values', () {
      expect(
        () => NativeVibration.vibrate(pattern: [0, -100]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects intensity values out of range', () {
      expect(
        () => NativeVibration.vibrate(pattern: [0, 100], intensities: [300]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // =========================================================================
  // cancel
  // =========================================================================

  group('cancel', () {
    test('sends cancel method call', () async {
      await NativeVibration.cancel();
      expect(log.last.method, 'cancel');
    });
  });

  // =========================================================================
  // Convenience Methods
  // =========================================================================

  group('convenience methods', () {
    test('light() sends short medium vibration', () async {
      await NativeVibration.light();
      expect(log.last.method, 'vibrate');
      expect(log.last.arguments['duration'], 200);
      expect(log.last.arguments['amplitude'], 128);
    });

    test('medium() sends medium vibration', () async {
      await NativeVibration.medium();
      expect(log.last.arguments['duration'], 400);
      expect(log.last.arguments['amplitude'], 200);
    });

    test('heavy() sends strong vibration', () async {
      await NativeVibration.heavy();
      expect(log.last.arguments['duration'], 600);
      expect(log.last.arguments['amplitude'], 255);
    });

    test('success() sends pattern', () async {
      await NativeVibration.success();
      expect(log.last.arguments['pattern'], isA<List>());
    });

    test('error() sends pattern', () async {
      await NativeVibration.error();
      expect(log.last.arguments['pattern'], isA<List>());
    });

    test('warning() sends pattern', () async {
      await NativeVibration.warning();
      expect(log.last.arguments['pattern'], isA<List>());
    });

    test('notification() sends pattern', () async {
      await NativeVibration.notification();
      expect(log.last.arguments['pattern'], isA<List>());
    });

    test('alarm() sends pattern', () async {
      await NativeVibration.alarm();
      expect(log.last.arguments['pattern'], isA<List>());
    });
  });
}
