/// 📦 ASSET MANIFEST — Tracks exportable nodes for developer handoff.
///
/// Maintains a registry of nodes that should be exported as assets
/// (icons, illustrations, etc.) with their naming conventions and formats.
library;

/// Supported image export formats.
enum AssetFormat { png1x, png2x, png3x, svg, pdf, webp }

/// A single exportable asset entry.
class HandoffAssetEntry {
  final String nodeId;
  final String name;
  final List<AssetFormat> formats;
  final String? description;
  final String? group;

  const HandoffAssetEntry({
    required this.nodeId,
    required this.name,
    this.formats = const [AssetFormat.png2x, AssetFormat.svg],
    this.description,
    this.group,
  });

  /// Generate file names for all formats.
  List<String> fileNames() => formats.map((f) => '$name.${_ext(f)}').toList();

  String _ext(AssetFormat f) => switch (f) {
    AssetFormat.png1x => 'png',
    AssetFormat.png2x => '@2x.png',
    AssetFormat.png3x => '@3x.png',
    AssetFormat.svg => 'svg',
    AssetFormat.pdf => 'pdf',
    AssetFormat.webp => 'webp',
  };

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'name': name,
    'formats': formats.map((f) => f.name).toList(),
    if (description != null) 'description': description,
    if (group != null) 'group': group,
  };

  factory HandoffAssetEntry.fromJson(Map<String, dynamic> json) =>
      HandoffAssetEntry(
        nodeId: json['nodeId'] as String,
        name: json['name'] as String,
        formats:
            (json['formats'] as List<dynamic>?)
                ?.map((f) => AssetFormat.values.byName(f as String))
                .toList() ??
            [AssetFormat.png2x, AssetFormat.svg],
        description: json['description'] as String?,
        group: json['group'] as String?,
      );
}

/// Registry of exportable assets.
class AssetManifest {
  AssetManifest();
  final Map<String, HandoffAssetEntry> _entries = {};

  Map<String, HandoffAssetEntry> get entries => Map.unmodifiable(_entries);

  int get length => _entries.length;

  void addEntry(HandoffAssetEntry entry) {
    _entries[entry.nodeId] = entry;
  }

  bool removeEntry(String nodeId) => _entries.remove(nodeId) != null;

  HandoffAssetEntry? getEntry(String nodeId) => _entries[nodeId];

  bool hasEntry(String nodeId) => _entries.containsKey(nodeId);

  /// Get all entries in a specific group.
  List<HandoffAssetEntry> entriesInGroup(String group) =>
      _entries.values.where((e) => e.group == group).toList();

  /// Get all unique groups.
  Set<String> get groups =>
      _entries.values
          .where((e) => e.group != null)
          .map((e) => e.group!)
          .toSet();

  /// Get entries by format.
  List<HandoffAssetEntry> entriesByFormat(AssetFormat format) =>
      _entries.values.where((e) => e.formats.contains(format)).toList();

  /// Generate a summary of all assets grouped by category.
  Map<String, List<HandoffAssetEntry>> groupedEntries() {
    final grouped = <String, List<HandoffAssetEntry>>{};
    for (final entry in _entries.values) {
      final key = entry.group ?? 'ungrouped';
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    return grouped;
  }

  Map<String, dynamic> toJson() => {
    'entries': _entries.values.map((e) => e.toJson()).toList(),
  };

  factory AssetManifest.fromJson(Map<String, dynamic> json) {
    final manifest = AssetManifest();
    final list = json['entries'] as List<dynamic>? ?? [];
    for (final raw in list) {
      final entry = HandoffAssetEntry.fromJson(raw as Map<String, dynamic>);
      manifest._entries[entry.nodeId] = entry;
    }
    return manifest;
  }
}
