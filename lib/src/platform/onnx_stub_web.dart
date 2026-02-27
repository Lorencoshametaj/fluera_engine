// Stub for web — provides no-op types matching onnxruntime_v2 API surface.
// On native platforms, the real onnxruntime_v2 is used via conditional import.

class OrtEnv {
  static final OrtEnv instance = OrtEnv._();
  OrtEnv._();
  void init() {}
  void release() {}
}

class OrtSession {
  OrtSession.fromBuffer(dynamic bytes, OrtSessionOptions options) {
    throw UnsupportedError('ONNX Runtime is not supported on web');
  }
  OrtSession.fromFile(dynamic file, OrtSessionOptions options) {
    throw UnsupportedError('ONNX Runtime is not supported on web');
  }
  Future<List<OrtValue?>?> runAsync(
    OrtRunOptions options,
    Map<String, OrtValue> inputs,
  ) async {
    throw UnsupportedError('ONNX Runtime is not supported on web');
  }

  void release() {}
}

class OrtSessionOptions {}

class OrtRunOptions {
  void release() {}
}

class OrtValue {
  dynamic get value => null;
  void release() {}
}

class OrtValueTensor extends OrtValue {
  OrtValueTensor._();
  static OrtValue createTensorWithDataList(dynamic data, List<int> shape) {
    throw UnsupportedError('ONNX Runtime is not supported on web');
  }
}
