import 'dart:io';
import 'package:flutter/material.dart';

import '../models/timelapse_export_config.dart';
import '../services/timelapse_export_service.dart';
import '../services/time_travel_playback_engine.dart';

/// 🎬 Premium Timelapse Export Dialog
///
/// Bottom sheet dark-themed con controlli per configurare ed esportare
/// il timelapse del processo creativo. Design coerente con il tema
/// Time Travel (palette viola).
class TimelapseExportDialog extends StatefulWidget {
  final TimeTravelPlaybackEngine engine;
  final int totalEventCount;

  const TimelapseExportDialog({
    super.key,
    required this.engine,
    required this.totalEventCount,
  });

  /// 🎬 Mostra il dialog come modal bottom sheet
  static Future<File?> show(
    BuildContext context, {
    required TimeTravelPlaybackEngine engine,
    required int totalEventCount,
  }) {
    return showModalBottomSheet<File?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => TimelapseExportDialog(
            engine: engine,
            totalEventCount: totalEventCount,
          ),
    );
  }

  @override
  State<TimelapseExportDialog> createState() => _TimelapseExportDialogState();
}

class _TimelapseExportDialogState extends State<TimelapseExportDialog> {
  // Config state
  TimelapseResolution _resolution = TimelapseResolution.fullHd1080;
  TimelapseSpeed _speed = TimelapseSpeed.x8;
  TimelapseFormat _format = TimelapseFormat.mp4;
  bool _showWatermark = true;
  Color _backgroundColor = Colors.white;

  // Export state
  bool _isExporting = false;
  double _progress = 0.0;
  String _status = '';
  bool _isCancelled = false;
  File? _exportedFile;

  TimelapseExportConfig get _config => TimelapseExportConfig.auto(
    eventCount: widget.totalEventCount,
    resolution: _resolution,
    speed: _speed,
    format: _format,
    backgroundColor: _backgroundColor,
    showWatermark: _showWatermark,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(color: Colors.white12, height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child:
                  _isExporting
                      ? _buildExportProgress()
                      : _exportedFile != null
                      ? _buildExportComplete()
                      : _buildConfigForm(),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // HANDLE & HEADER
  // ============================================================================

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B2FBE), Color(0xFF9B59B6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.movie_creation,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export Timelapse',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Share your creative process',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // CONFIG FORM
  // ============================================================================

  Widget _buildConfigForm() {
    final config = _config;
    final estimatedDuration = config.estimatedDurationSec(
      widget.totalEventCount,
    );
    final estimatedSize = config.estimatedFileSizeMb(widget.totalEventCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // RESOLUTION
        _buildSectionLabel('Resolution'),
        const SizedBox(height: 8),
        _buildResolutionSelector(),
        const SizedBox(height: 20),

        // SPEED
        _buildSectionLabel('Speed'),
        const SizedBox(height: 8),
        _buildSpeedSelector(),
        const SizedBox(height: 20),

        // FORMAT
        _buildSectionLabel('Format'),
        const SizedBox(height: 8),
        _buildFormatSelector(),
        const SizedBox(height: 20),

        // OPTIONS
        _buildSectionLabel('Options'),
        const SizedBox(height: 8),
        _buildOptionSwitch(
          'Watermark',
          'Show "Made with Looponia"',
          _showWatermark,
          (v) => setState(() => _showWatermark = v),
          Icons.branding_watermark,
        ),
        const SizedBox(height: 8),
        _buildBackgroundSelector(),
        const SizedBox(height: 20),

        // ESTIMATES
        _buildEstimates(estimatedDuration, estimatedSize),
        const SizedBox(height: 24),

        // EXPORT BUTTON
        _buildExportButton(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildResolutionSelector() {
    return Row(
      children:
          TimelapseResolution.values.map((res) {
            final isSelected = res == _resolution;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: res != TimelapseResolution.values.last ? 8 : 0,
                ),
                child: _buildChip(
                  label: res.label.replaceAll(' ', '\n'),
                  subtitle: res.description,
                  isSelected: isSelected,
                  onTap: () => setState(() => _resolution = res),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildSpeedSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            TimelapseSpeed.values.map((speed) {
              final isSelected = speed == _speed;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(speed.label),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _speed = speed),
                  backgroundColor: const Color(0xFF2A2A4A),
                  selectedColor: const Color(0xFF7B2FBE),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildFormatSelector() {
    return Row(
      children:
          TimelapseFormat.values.map((fmt) {
            final isSelected = fmt == _format;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: fmt != TimelapseFormat.values.last ? 8 : 0,
                ),
                child: _buildChip(
                  label: fmt.label,
                  subtitle: fmt.codec,
                  isSelected: isSelected,
                  onTap: () => setState(() => _format = fmt),
                  icon: fmt.icon,
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildChip({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7B2FBE) : const Color(0xFF2A2A4A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF9B59B6) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(height: 4),
            ],
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected ? Colors.white60 : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionSwitch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A4A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF9B59B6),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundSelector() {
    final colors = [
      Colors.white,
      Colors.black,
      const Color(0xFFF5F5DC), // Beige
      const Color(0xFF1A1A2E), // Dark blue
      const Color(0xFFF0E6D3), // Parchment
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A4A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.format_color_fill, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Background',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          ...colors.map(
            (color) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => setState(() => _backgroundColor = color),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          _backgroundColor == color
                              ? const Color(0xFF9B59B6)
                              : Colors.white24,
                      width: _backgroundColor == color ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimates(double durationSec, double sizeMb) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A4A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A5A)),
      ),
      child: Row(
        children: [
          _buildEstimateItem(
            Icons.timer_outlined,
            '~${durationSec.toStringAsFixed(0)}s',
            'Duration',
          ),
          Container(width: 1, height: 32, color: Colors.white12),
          _buildEstimateItem(
            Icons.storage_outlined,
            '~${sizeMb.toStringAsFixed(1)} MB',
            'File size',
          ),
          Container(width: 1, height: 32, color: Colors.white12),
          _buildEstimateItem(
            Icons.speed_outlined,
            '${_config.totalFrames(widget.totalEventCount)}',
            'Frames',
          ),
        ],
      ),
    );
  }

  Widget _buildEstimateItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF9B59B6), size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7B2FBE), Color(0xFF9B59B6), Color(0xFFAB69C6)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B2FBE).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _startExport,
          icon: const Icon(Icons.movie_creation, size: 20),
          label: const Text(
            'Export Timelapse',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // EXPORT PROGRESS
  // ============================================================================

  Widget _buildExportProgress() {
    return Column(
      children: [
        const SizedBox(height: 32),
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _progress,
                strokeWidth: 6,
                backgroundColor: const Color(0xFF2A2A4A),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF9B59B6)),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _status,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 32),
        TextButton.icon(
          onPressed: () {
            _isCancelled = true;
            setState(() {});
          },
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancel'),
          style: TextButton.styleFrom(foregroundColor: Colors.white54),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ============================================================================
  // EXPORT COMPLETE
  // ============================================================================

  Widget _buildExportComplete() {
    return Column(
      children: [
        const SizedBox(height: 32),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            color: Color(0xFF2ECC71),
            size: 48,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Timelapse Ready!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _format == TimelapseFormat.mp4
              ? 'Your creative process as a video'
              : 'Your creative process as a GIF',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.share,
                label: 'Share',
                gradient: const [Color(0xFF7B2FBE), Color(0xFF9B59B6)],
                onTap: _shareExport,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.save_alt,
                label: 'Save',
                gradient: const [Color(0xFF2A2A4A), Color(0xFF3A3A5A)],
                onTap: () => Navigator.of(context).pop(_exportedFile),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // EXPORT LOGIC
  // ============================================================================

  Future<void> _startExport() async {
    setState(() {
      _isExporting = true;
      _isCancelled = false;
      _progress = 0.0;
      _status = 'Preparing...';
    });

    final service = TimeTravelExportService();
    final result = await service.exportTimelapse(
      engine: widget.engine,
      config: _config,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _status = status;
          });
        }
      },
      isCancelled: () => _isCancelled,
    );

    if (mounted) {
      setState(() {
        _isExporting = false;
        _exportedFile = result;
        if (result == null && !_isCancelled) {
          // Export failed — reset to config
          _status = '';
        }
      });
    }
  }

  Future<void> _shareExport() async {
    if (_exportedFile != null) {
      await TimeTravelExportService.shareVideo(_exportedFile!);
    }
  }
}
