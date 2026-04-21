import 'package:flutter/material.dart';
import 'drawing_input_handler.dart';
import 'predicted_touch_service.dart';

/// On-device diagnostic panel for the Apple Pencil 240 Hz path. Wrap this
/// around (or stack it over) any screen that does drawing; it renders two
/// small read-outs in the top-left corner showing:
///
///   - native event rate (events/s, real/s, pred/s) from
///     [PredictedTouchService.debugStatusNotifier]
///   - last-stroke hz/count/duration/native-used from
///     [DrawingInputHandler.debugStrokeNotifier]
///
/// Use it to confirm, on TestFlight, that:
///   - native coalesced samples reach Dart (first line non-empty)
///   - real/s approaches ~240 on fast Apple Pencil scribbles
///   - per-stroke hz matches, and `native=Y` on Pencil strokes
///
/// Remove (or set [visible] to false) once the 240 Hz path is verified.
class PredictedTouchDebugOverlay extends StatelessWidget {
  const PredictedTouchDebugOverlay({
    super.key,
    this.visible = true,
    this.alignment = Alignment.topLeft,
  });

  final bool visible;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable:
                          PredictedTouchService.debugStatusNotifier,
                      builder: (_, v, __) => Text(
                        v.isEmpty ? 'native: (waiting for 1st touch…)' : v,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ValueListenableBuilder<String>(
                      valueListenable:
                          DrawingInputHandler.debugStrokeNotifier,
                      builder: (_, v, __) => Text(
                        v.isEmpty ? 'stroke: (draw something…)' : v,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
