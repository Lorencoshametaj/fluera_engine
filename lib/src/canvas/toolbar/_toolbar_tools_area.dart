part of 'professional_canvas_toolbar.dart';

// ============================================================================
// 🛠️ TOOLS AREA — Pen types, colors, width, opacity, shapes
// Extracted from professional_canvas_toolbar.dart
// ============================================================================

extension _ToolsAreaBuilder on _ProfessionalCanvasToolbarState {
  Widget _buildToolsArea(BuildContext context, bool isDark) {
    final l10n = NebulaLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Prima riga: strumenti principali
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // 🖊️ TIPO PENNA
              _buildPenTypeSection(isDark, l10n),

              const SizedBox(width: 12),

              // 🎨 PALETTE COLORI
              _buildColorSection(isDark, l10n),

              const SizedBox(width: 12),

              // 📏 LARGHEZZA
              _buildWidthSection(isDark, l10n),

              const SizedBox(width: 12),

              // 🔲 OPACITÀ
              _buildOpacitySection(isDark, l10n),

              const SizedBox(width: 12),

              // 🔷 TOGGLE FORME GEOMETRICHE
              _buildShapesToggleButton(isDark, l10n),
            ],
          ),
        ),

        // Seconda riga: forme geometriche (only if espanse) with animation slide-in
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child:
              _isShapesExpanded
                  ? AnimatedOpacity(
                    opacity: _isShapesExpanded ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.03),
                        border: Border(
                          top: BorderSide(
                            color: Colors.deepPurple.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: _buildShapeSection(isDark),
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildPenTypeSection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_pen,
      icon: Icons.edit_rounded,
      isDark: isDark,
      child: Row(
        children: [
          // 🎨 Preset-based brush selector
          ToolbarBrushStrip(
            presets: widget.brushPresets,
            selectedPresetId: widget.selectedPresetId,
            isPenActive: !widget.isEraserActive && !widget.isLassoActive,
            onPresetSelected: (preset) {
              HapticFeedback.selectionClick();
              // Disattiva gomma e lasso when attiva la penna
              if (widget.isEraserActive) {
                widget.onEraserToggle();
              }
              if (widget.isLassoActive) {
                widget.onLassoToggle();
              }
              // Apply preset (pen type, width, color, settings)
              widget.onPresetSelected?.call(preset);
            },
            onLongPress: () {
              // 🏛️ Long-press → Open brush settings popup anchored to strip
              HapticFeedback.mediumImpact();
              if (widget.onBrushSettingsPressed != null) {
                final box = context.findRenderObject() as RenderBox;
                final pos = box.localToGlobal(Offset.zero);
                final rect = pos & box.size;
                widget.onBrushSettingsPressed!(rect);
              }
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // 🖐️ Pan Mode Button (to the left of the eraser)
          ToolbarPanModeButton(
            isActive: widget.isPanModeActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPanModeToggle();
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // 🖊️ Stylus Mode Button (to the right of gesture)
          ToolbarStylusModeButton(
            isActive: widget.isStylusModeActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onStylusModeToggle();
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          ToolbarEraserButton(
            isActive: widget.isEraserActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onEraserToggle();
            },
            isDark: isDark,
          ),
          // 🎚️ Eraser size slider (appears when eraser is active)
          if (widget.isEraserActive &&
              widget.onEraserRadiusChanged != null) ...[
            const SizedBox(width: 8),
            ToolbarEraserSizeSlider(
              radius: widget.eraserRadius,
              onChanged: widget.onEraserRadiusChanged!,
              isDark: isDark,
            ),
            // 🔀 Whole/Partial toggle
            if (widget.onEraseWholeStrokeChanged != null) ...[
              const SizedBox(width: 4),
              ToolbarEraseModeToggle(
                isWholeStroke: widget.eraseWholeStroke,
                onChanged: widget.onEraseWholeStrokeChanged!,
                isDark: isDark,
              ),
            ],
          ],
          const SizedBox(width: 12),
          // Lasso nascosto in editing mode
          if (!widget.isImageEditingMode) ...[
            ToolbarLassoButton(
              isActive: widget.isLassoActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onLassoToggle();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            // 📏 Ruler toggle
            ToolbarRulerButton(
              isActive: widget.isRulerActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onRulerToggle?.call();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            // ✒️ Vector Pen Tool toggle
            if (widget.onPenToolToggle != null) ...[
              ToolbarPenToolButton(
                isActive: widget.isPenToolActive,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onPenToolToggle?.call();
                },
                isDark: isDark,
              ),
              const SizedBox(width: 12),
            ],
          ],
          // Digital text, image picker, recording e view recordings nascosti in editing mode
          if (!widget.isImageEditingMode) ...[
            ToolbarDigitalTextButton(
              isActive: widget.isDigitalTextActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onDigitalTextToggle();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            ToolbarImagePickerButton(
              isActive: widget.isImagePickerActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onImagePickerPressed();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            if (!widget.hideRecordingControlWhenActive ||
                !widget.isRecordingActive)
              ToolbarRecordingButton(
                isActive: widget.isRecordingActive,
                duration: widget.recordingDuration,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onRecordingPressed();
                },
                isDark: isDark,
              ),
            const SizedBox(width: 12),
            ToolbarViewRecordingsButton(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onViewRecordingsPressed();
              },
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShapeSection(bool isDark) {
    return ToolbarToolSection(
      title: NebulaLocalizations.of(context).proCanvas_shapes.toUpperCase(),
      icon: Icons.category_rounded,
      isDark: isDark,
      child: ToolbarShapeTypeSelector(
        selectedType: widget.selectedShapeType,
        onChanged: (type) {
          HapticFeedback.selectionClick();
          widget.onShapeTypeChanged(type);
        },
        isDark: isDark,
      ),
    );
  }

  Widget _buildColorSection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_color,
      icon: Icons.palette_rounded,
      isDark: isDark,
      child: ToolbarColorPalette(
        colors: _customColors,
        selectedColor: widget.selectedColor,
        onChanged: (color) {
          HapticFeedback.selectionClick();
          widget.onColorChanged(color);
        },
        onLongPress: _showColorPicker,
        isDark: isDark,
      ),
    );
  }

  Widget _buildWidthSection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_thickness,
      icon: Icons.line_weight,
      isDark: isDark,
      child: ToolbarWidthSlider(
        value: widget.selectedWidth,
        onChanged: widget.onWidthChanged,
        isDark: isDark,
      ),
    );
  }

  Widget _buildOpacitySection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_opacity,
      icon: Icons.opacity_rounded,
      isDark: isDark,
      child: ToolbarOpacitySlider(
        value: widget.selectedOpacity,
        onChanged: widget.onOpacityChanged,
        isDark: isDark,
      ),
    );
  }

  Widget _buildShapesToggleButton(bool isDark, NebulaLocalizations l10n) {
    return Tooltip(
      message: l10n.proCanvas_geometricShapes,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isShapesExpanded = !_isShapesExpanded;
              // 🔄 When closing the shapes section, automatically return to brush
              if (!_isShapesExpanded) {
                widget.onShapeTypeChanged(ShapeType.freehand);
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient:
                  _isShapesExpanded
                      ? LinearGradient(
                        colors: [
                          Colors.deepPurple.withValues(alpha: 0.2),
                          Colors.deepPurple.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                      : null,
              color:
                  _isShapesExpanded
                      ? null
                      : (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.05,
                      ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    _isShapesExpanded
                        ? Colors.deepPurple.withValues(alpha: 0.6)
                        : (isDark ? Colors.white : Colors.black).withValues(
                          alpha: 0.1,
                        ),
                width: _isShapesExpanded ? 2.5 : 1,
              ),
              boxShadow:
                  _isShapesExpanded
                      ? [
                        BoxShadow(
                          color: Colors.deepPurple.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: _isShapesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.category_rounded,
                    size: 22,
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  style: TextStyle(
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                    fontWeight:
                        _isShapesExpanded ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  child: Text(NebulaLocalizations.of(context).proCanvas_shapes),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isShapesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
