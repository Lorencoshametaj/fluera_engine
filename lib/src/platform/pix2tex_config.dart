/// 🔧 Pix2Tex API configuration.
///
/// Configures the connection to a self-hosted pix2tex (LaTeX-OCR) server.
///
/// ```dart
/// final config = Pix2TexConfig(
///   host: '192.168.1.10',
///   port: 8502,
///   timeout: Duration(seconds: 15),
/// );
/// ```
class Pix2TexConfig {
  /// Hostname or IP of the pix2tex server.
  final String host;

  /// Port number (default: 8502).
  final int port;

  /// Request timeout (default: 10 seconds).
  final Duration timeout;

  /// Maximum retry attempts on transient failures (default: 3).
  final int maxRetries;

  /// Use HTTPS instead of HTTP.
  final bool useTls;

  /// Optional API key sent as `Authorization: Bearer <key>`.
  final String? apiKey;

  const Pix2TexConfig({
    this.host = 'localhost',
    this.port = 8502,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 3,
    this.useTls = false,
    this.apiKey,
  });

  /// Base URL for the pix2tex API.
  String get baseUrl {
    final scheme = useTls ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  /// Prediction endpoint.
  Uri get predictUri => Uri.parse('$baseUrl/predict');

  /// Health check endpoint.
  Uri get healthUri => Uri.parse('$baseUrl/health');

  /// Copy with overrides.
  Pix2TexConfig copyWith({
    String? host,
    int? port,
    Duration? timeout,
    int? maxRetries,
    bool? useTls,
    String? apiKey,
  }) {
    return Pix2TexConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      timeout: timeout ?? this.timeout,
      maxRetries: maxRetries ?? this.maxRetries,
      useTls: useTls ?? this.useTls,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  @override
  String toString() =>
      'Pix2TexConfig($baseUrl, timeout: $timeout, retries: $maxRetries)';
}
