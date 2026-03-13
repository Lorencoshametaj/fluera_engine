/// 📤 Export Settings — composable value object.
///
/// Configures the output format and quality for image export.
class ExportSettings {
  final String format; // 'png', 'jpeg', 'webp'
  final int quality; // 0-100 (for lossy formats)

  const ExportSettings({this.format = 'png', this.quality = 95});

  static const defaultSettings = ExportSettings();

  /// Whether this uses a lossy format
  bool get isLossy => format != 'png';

  ExportSettings copyWith({String? format, int? quality}) => ExportSettings(
    format: format ?? this.format,
    quality: quality ?? this.quality,
  );

  Map<String, dynamic> toJson() => {'format': format, 'quality': quality};

  factory ExportSettings.fromJson(Map<String, dynamic> json) => ExportSettings(
    format: json['format'] as String? ?? 'png',
    quality: (json['quality'] as num?)?.toInt() ?? 95,
  );
}
