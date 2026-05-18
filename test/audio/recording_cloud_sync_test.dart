// ============================================================================
// ☁️ RECORDING CLOUD SYNC — interface contract tests
//
// Verifies the engine-side abstract interface behaves correctly with the
// NoopRecordingCloudSync default and with a recording-FakeRecordingCloudSync
// that captures invocations. We don't bring up a real Supabase here —
// host-side impl is tested via integration on device.
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/audio/cloud/recording_cloud_sync.dart';
import 'package:fluera_engine/src/time_travel/models/synchronized_recording.dart';

SynchronizedRecording _rec({
  String id = 'r1',
  String? branchId,
  String? audioStorageUrl,
}) =>
    SynchronizedRecording(
      id: id,
      audioPath: '/tmp/$id.m4a',
      totalDuration: const Duration(seconds: 10),
      startTime: DateTime(2025, 1, 1),
      syncedStrokes: const [],
      canvasId: 'c1',
      branchId: branchId,
      audioStorageUrl: audioStorageUrl,
    );

class _FakeRecordingCloudSync implements RecordingCloudSync {
  final List<String> uploadCalls = [];
  final List<String> downloadCalls = [];
  final List<String> deleteCalls = [];
  String? Function(SynchronizedRecording)? uploadResult;
  String? Function(SynchronizedRecording)? downloadResult;

  @override
  Future<String?> uploadRecording(SynchronizedRecording recording) async {
    uploadCalls.add(recording.id);
    return uploadResult?.call(recording);
  }

  @override
  Future<String?> downloadRecording(SynchronizedRecording recording) async {
    downloadCalls.add(recording.id);
    return downloadResult?.call(recording);
  }

  @override
  Future<void> deleteRemote(SynchronizedRecording recording) async {
    deleteCalls.add(recording.id);
  }
}

void main() {
  group('NoopRecordingCloudSync', () {
    const sync = NoopRecordingCloudSync();

    test('uploadRecording returns null', () async {
      expect(await sync.uploadRecording(_rec()), isNull);
    });

    test('downloadRecording returns null', () async {
      expect(await sync.downloadRecording(_rec(audioStorageUrl: 'x')), isNull);
    });

    test('deleteRemote is a no-op (no throw)', () async {
      await sync.deleteRemote(_rec());
      expect(true, isTrue);
    });
  });

  group('RecordingCloudSync contract — Fake', () {
    late _FakeRecordingCloudSync sync;
    setUp(() => sync = _FakeRecordingCloudSync());

    test('upload returns the URL the impl computes', () async {
      sync.uploadResult = (r) => 'u1/c1/main/${r.id}.m4a';
      final url = await sync.uploadRecording(_rec(id: 'rec_a'));
      expect(url, 'u1/c1/main/rec_a.m4a');
      expect(sync.uploadCalls, ['rec_a']);
    });

    test('upload returns null when impl signals failure', () async {
      sync.uploadResult = (_) => null;
      final url = await sync.uploadRecording(_rec(id: 'rec_b'));
      expect(url, isNull);
      expect(sync.uploadCalls, ['rec_b']);
    });

    test('download is called with the recording carrying audioStorageUrl',
        () async {
      sync.downloadResult = (r) => '/tmp/downloaded/${r.id}.m4a';
      final rec = _rec(id: 'rec_c', audioStorageUrl: 'u1/c1/main/rec_c.m4a');
      final localPath = await sync.downloadRecording(rec);
      expect(localPath, '/tmp/downloaded/rec_c.m4a');
      expect(sync.downloadCalls, ['rec_c']);
    });

    test('deleteRemote records the invocation', () async {
      await sync.deleteRemote(_rec(id: 'rec_d'));
      expect(sync.deleteCalls, ['rec_d']);
    });

    test('branchId is preserved through the adapter call', () async {
      sync.uploadResult = (r) =>
          'u1/c1/${r.branchId ?? 'main'}/${r.id}.m4a';
      final url =
          await sync.uploadRecording(_rec(id: 'rec_e', branchId: 'br_alt'));
      expect(url, 'u1/c1/br_alt/rec_e.m4a');
    });
  });
}
