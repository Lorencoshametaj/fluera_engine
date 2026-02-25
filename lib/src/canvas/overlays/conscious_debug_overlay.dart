import 'package:flutter/material.dart';

import '../../core/engine_scope.dart';
import '../../core/conscious_architecture.dart';
import '../../core/adaptive_profile.dart';
import '../../rendering/optimization/anticipatory_tile_prefetch.dart';
import '../../systems/intelligence_adapters.dart';

/// 🧠 CONSCIOUS ARCHITECTURE DEBUG OVERLAY
///
/// A compact debug panel that visualizes the state of all intelligence
/// subsystems at runtime. Toggle via the developer menu or a gesture.
///
/// Shows:
/// - Registered subsystem names and active/inactive status
/// - AdaptiveProfile metrics (drawing ratio, zoom rate, dominant tool)
/// - AnticipatoryTilePrefetch margins [L, T, R, B]
/// - SmartSnap adapted threshold
/// - Last context push timestamp
class ConsciousDebugOverlay extends StatelessWidget {
  const ConsciousDebugOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    ConsciousArchitecture arch;
    try {
      arch = EngineScope.current.consciousArchitecture;
    } catch (_) {
      return const SizedBox.shrink();
    }

    final subsystems = arch.subsystems;
    final profile = arch.find<AdaptiveProfile>();
    final prefetch = arch.find<AnticipatoryTilePrefetch>();
    final snapAdapter = arch.find<SmartSnapAdapter>();

    return Positioned(
      right: 8,
      bottom: 80,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Colors.white70,
              height: 1.4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                const Row(
                  children: [
                    Text('🧠', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 4),
                    Text(
                      'CONSCIOUS ARCH',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 8),

                // Subsystem list
                ...subsystems.map(
                  (s) => Row(
                    children: [
                      Icon(
                        s.isActive ? Icons.check_circle : Icons.cancel,
                        size: 10,
                        color: s.isActive ? Colors.greenAccent : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${s.layer.name.toUpperCase()} ${s.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Profile metrics
                if (profile != null && profile.isActive) ...[
                  const Divider(color: Colors.white24, height: 8),
                  Text(
                    'draw: ${(profile.drawingRatio * 100).toStringAsFixed(0)}%  '
                    'zoom: ${profile.zoomChangeRate.toStringAsFixed(1)}/m',
                  ),
                  Text('tool: ${profile.dominantTool ?? '—'}'),
                  Text(
                    'β=${profile.recommendedFilterBeta.toStringAsFixed(4)}  '
                    'pf=${profile.recommendedTilePrefetch}',
                  ),
                ],

                // Prefetch margins
                if (prefetch != null && prefetch.isActive) ...[
                  const Divider(color: Colors.white24, height: 8),
                  Builder(
                    builder: (_) {
                      final m = prefetch.margins;
                      return Text(
                        'margins [${m[0].toStringAsFixed(1)}, '
                        '${m[1].toStringAsFixed(1)}, '
                        '${m[2].toStringAsFixed(1)}, '
                        '${m[3].toStringAsFixed(1)}]  '
                        'bias=${prefetch.prefetchMarginBias.toStringAsFixed(1)}',
                      );
                    },
                  ),
                ],

                // Snap threshold
                if (snapAdapter != null && snapAdapter.isActive) ...[
                  Text(
                    'snap: ${snapAdapter.snapThreshold.toStringAsFixed(1)}px',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
