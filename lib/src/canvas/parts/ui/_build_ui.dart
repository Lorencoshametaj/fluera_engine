part of '../../fluera_canvas_screen.dart';

/// 📦 Build UI — orchestrator that delegates to:
///   • [_ui_toolbar.dart]      → _buildToolbar()
///   • [_ui_canvas_layer.dart] → _buildCanvasArea()
///   • [_ui_eraser.dart]       → _buildEraserOverlays()
///   • [_ui_overlays.dart]     → _buildRemoteOverlays(), _buildStandardOverlays(), _buildToolOverlays()
///   • [_ui_menus.dart]        → _buildMenus()
extension on _FlueraCanvasScreenState {
  // ============================================================================
  // BUILD — Main entry point
  // ============================================================================

  Widget _buildImpl(BuildContext context) {
    // 🎨 Eagerly load brush presets (async, no-op if already loaded)
    if (!_presetsLoaded) {
      _brushPresetManager.load().then((_) {
        if (mounted) {
          _presetsLoaded = true;
          setState(() {});
        }
      });
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // ✒️ Delegate key events to pen tool when active
        if (_toolController.isPenToolMode) {
          final consumed = _penTool.handleKeyEvent(event, _penToolContext);
          if (consumed) {
            setState(() {});
            return KeyEventResult.handled;
          }
        }

        // 📊 Tabular keyboard shortcuts (only on key down)
        if (event is KeyDownEvent &&
            _tabularTool.hasSelection &&
            _tabularTool.hasCellSelection) {
          final isCtrl =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;

          // Ctrl+C → Copy
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
            _copySelection();
            return KeyEventResult.handled;
          }
          // Ctrl+V → Paste
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
            _pasteAtSelection();
            return KeyEventResult.handled;
          }
          // Ctrl+X → Cut
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
            _cutSelection();
            return KeyEventResult.handled;
          }
          // Ctrl+B → Bold
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyB) {
            _toggleBold();
            return KeyEventResult.handled;
          }
          // Ctrl+I → Italic
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyI) {
            _toggleItalic();
            return KeyEventResult.handled;
          }

          // Delete / Backspace → Clear cells
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _clearSelectedCells();
            return KeyEventResult.handled;
          }

          // Arrow keys → Navigate
          if (!isCtrl) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _moveUp();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _moveDownNav();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _moveLeft();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _moveRightNav();
              return KeyEventResult.handled;
            }
          }

          // Escape → Deselect cell
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _tabularTool.deselectCell();
            setState(() {});
            return KeyEventResult.handled;
          }
        }

        // 📊 Escape to deselect table
        if (event is KeyDownEvent &&
            _tabularTool.hasSelection &&
            !_tabularTool.hasCellSelection &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _tabularTool.deselectTabular();
          setState(() {});
          return KeyEventResult.handled;
        }

        // 🧭 Navigation keyboard shortcuts
        if (event is KeyDownEvent) {
          final isCtrl =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          final isShift = HardwareKeyboard.instance.isShiftPressed;

          // Ctrl+Shift+1 → Fit all content
          if (isCtrl &&
              isShift &&
              event.logicalKey == LogicalKeyboardKey.digit1) {
            CameraActions.fitAllContent(
              _canvasController,
              _layerController.sceneGraph,
              MediaQuery.of(context).size,
            );
            return KeyEventResult.handled;
          }

          // Ctrl+0 → Return to origin
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit0) {
            CameraActions.returnToOrigin(
              _canvasController,
              MediaQuery.of(context).size,
            );
            return KeyEventResult.handled;
          }

          // Ctrl+M → Toggle minimap
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyM) {
            setState(() {
              _showMinimap = !_showMinimap;
            });
            return KeyEventResult.handled;
          }

          // 🔍 Ctrl+F → Toggle handwriting search
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyF) {
            setState(() {
              _showHandwritingSearch = !_showHandwritingSearch;
              if (!_showHandwritingSearch) {
                _hwSearchResults = [];
                _hwSearchActiveIndex = 0;
              }
            });
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false, // Prevents canvas UI (minimap, etc) from jumping when keyboard opens
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              // Main content: toolbar + canvas
              Column(
                children: [
                  // 🛠️ Professional Toolbar (slides away in wheel mode)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: _useRadialWheel
                        ? const SizedBox.shrink()
                        : _toolbarHost,
                  ),

                  // 🎨 Canvas + Navigation Overlays
                  Expanded(
                    child: Stack(
                      children: [
                        RepaintBoundary(
                          key: _canvasRepaintBoundaryKey,
                          child: _buildCanvasArea(context),
                        ),

                        // ✛ Navigation: Origin crosshair at (0,0)
                        Positioned.fill(
                          child: OriginCrosshair(
                            controller: _canvasController,
                            viewportSize: MediaQuery.of(context).size,
                            canvasBackground: _canvasBackgroundColor,
                          ),
                        ),

                        // 🧭 Navigation: Content Radar (directional indicators)
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: false,
                            child: ContentRadarOverlay(
                              controller: _canvasController,
                              boundsTracker: _contentBoundsTracker,
                              viewportSize: MediaQuery.of(context).size,
                              canvasBackground: _canvasBackgroundColor,
                            ),
                          ),
                        ),

                        // 🗺️ Navigation: Minimap (bottom-right)
                        // Auto-hides when no content exists on the canvas.
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: ValueListenableBuilder<List>(
                            valueListenable: _contentBoundsTracker.regions,
                            builder: (context, regions, child) {
                              final hasContent = regions.isNotEmpty;
                              return CanvasMinimap(
                                controller: _canvasController,
                                boundsTracker: _contentBoundsTracker,
                                layerController: _layerController,
                                viewportSize: MediaQuery.of(context).size,
                                visible: _showMinimap && hasContent,
                                canvasBackground: _canvasBackgroundColor,
                                isDrawing: _isDrawingNotifier,
                                currentStroke: _currentStrokeNotifier,
                                currentStrokeColor: _effectiveColor,
                                remoteCursors: _realtimeEngine?.remoteCursors,
                              );
                            },
                          ),
                        ),

                        // 🔍 Navigation: Zoom Level Indicator (bottom-left)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          child: ZoomLevelIndicator(
                            controller: _canvasController,
                            viewportSize: MediaQuery.of(context).size,
                            canvasBackground: _canvasBackgroundColor,
                            showGridActive: _showDotGrid,
                            onLongPress: () {
                              setState(() => _showDotGrid = !_showDotGrid);
                            },
                            isMinimapVisible: _showMinimap,
                            onToggleMinimap: () {
                              setState(() => _showMinimap = !_showMinimap);
                            },
                            onToggleRotationLock: () {
                              HapticFeedback.selectionClick();
                              _canvasController.rotationLocked =
                                  !_canvasController.rotationLocked;
                            },
                          ),
                        ),

                        // ↩ Navigation: "Return to content" FAB (centered, bottom)
                        Positioned(
                          bottom: 24,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: ReturnToContentFab(
                              controller: _canvasController,
                              boundsTracker: _contentBoundsTracker,
                              layerController: _layerController,
                              viewportSize: MediaQuery.of(context).size,
                              canvasBackground: _canvasBackgroundColor,
                            ),
                          ),
                        ),

                        // 🔍 Handwriting Search Overlay (inside canvas stack = below toolbar)
                        if (_showHandwritingSearch)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: HandwritingSearchOverlay(
                              canvasId: _canvasId,
                              textElements: _digitalTextElements,
                              knowledgeFlowController: _knowledgeFlowController,
                              getViewportRect: () {
                                final s = _canvasController.scale;
                                final o = _canvasController.offset;
                                final vp = MediaQuery.of(context).size;
                                return Rect.fromLTWH(
                                  -o.dx / s,
                                  -o.dy / s,
                                  vp.width / s,
                                  vp.height / s,
                                );
                              },
                              onNavigate: (result) {
                                // 🔍 Navigate to search result: optimal pan + zoom
                                final viewportSize = MediaQuery.of(context).size;
                                final center = result.bounds.center;
                                final currentScale = _canvasController.scale;

                                // Compute optimal scale: result should fill ~50% of viewport width
                                final resultW = result.bounds.width.clamp(10.0, double.infinity);
                                final resultH = result.bounds.height.clamp(10.0, double.infinity);
                                final scaleForWidth = (viewportSize.width * 0.5) / resultW;
                                final scaleForHeight = (viewportSize.height * 0.4) / resultH;
                                final optimalScale = scaleForWidth < scaleForHeight
                                    ? scaleForWidth
                                    : scaleForHeight;
                                // Clamp to reasonable range and add 20% padding
                                final targetScale = (optimalScale * 0.8).clamp(0.5, 4.0);

                                // Check if zoom change is needed (result too small or too large on screen)
                                final resultScreenW = resultW * currentScale;
                                final needsZoom = resultScreenW < 100 || resultScreenW > 400;

                                final useScale = needsZoom ? targetScale : currentScale;

                                // Pan to center the result at the (potentially new) scale
                                final targetOffset = Offset(
                                  viewportSize.width / 2 - center.dx * useScale,
                                  viewportSize.height / 2 - center.dy * useScale,
                                );
                                _canvasController.animateOffsetTo(targetOffset);

                                // Zoom if needed
                                if (needsZoom && (targetScale - currentScale).abs() > 0.1) {
                                  _canvasController.animateZoomTo(
                                    targetScale,
                                    Offset(viewportSize.width / 2, viewportSize.height / 2),
                                  );
                                }

                                setState(() {
                                  _hwSearchActiveIndex = _hwSearchResults.indexOf(result);
                                });
                              },
                              onDismiss: () {
                                setState(() {
                                  _showHandwritingSearch = false;
                                  _hwSearchResults = [];
                                  _hwSearchActiveIndex = 0;
                                });
                              },
                              onResultsChanged: (results) {
                                setState(() {
                                  _hwSearchResults = results;
                                  _hwSearchActiveIndex = results.isNotEmpty ? 0 : -1;
                                });
                              },
                            ),
                          ),

                        // 🔍 Handwriting Search Highlights on canvas
                        if (_hwSearchResults.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _canvasController,
                                builder: (context, _) {
                                  return HandwritingSearchHighlights(
                                    results: _hwSearchResults,
                                    activeIndex: _hwSearchActiveIndex,
                                    canvasOffset: _canvasController.offset,
                                    canvasScale: _canvasController.scale,
                                  );
                                },
                              ),
                            ),
                          ),

                        // 🔍 Echo Search: Query Pen neon glow overlay
                        if (_isEchoSearchMode && _echoSearchController != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ValueListenableBuilder<int>(
                                valueListenable: _uiRebuildNotifier,
                                builder: (context, _, __) {
                                  return EchoSearchPenOverlay(
                                    controller: _echoSearchController!,
                                    canvasOffset: _canvasController.offset,
                                    canvasScale: _canvasController.scale,
                                  );
                                },
                              ),
                            ),
                          ),

                        // 📤 Multi-Page Export Overlay
                        if (_isMultiPageEditMode)
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _canvasController,
                              builder: (context, _) {
                                return InteractivePageGridOverlay(
                                  config: _multiPageConfig,
                                  canvasScale: _canvasController.scale,
                                  canvasOffset: _canvasController.offset,
                                  onConfigChanged: _onMultiPageConfigChanged,
                                  onPanCanvas: _onMultiPageAutoPan,
                                  onScaleCanvas: (focalPoint, frameRatio) {
                                    final currentScale = _canvasController.scale;
                                    final newScale = (currentScale * frameRatio).clamp(0.05, 5.0);
                                    // Zoom around focal point — as the focal point
                                    // moves with the fingers, this naturally pans too.
                                    final focalCanvas = (focalPoint - _canvasController.offset) / currentScale;
                                    final newOffset = focalPoint - focalCanvas * newScale;
                                    _canvasController.updateTransform(
                                      offset: newOffset,
                                      scale: newScale,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // 🌀 Rotation Angle Indicator → now integrated into ZoomLevelIndicator

              // 📤 Multi-Page Export Bottom Bar
              if (_isMultiPageEditMode)
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildMultiPageExportBottomBar(context),
                  ),
                ),


              // 📲 Echo Search: Swipe-down from top edge to activate
              if (!_isEchoSearchMode)
                _buildEchoSearchSwipeZone(),

              // 🔍 Echo Search HUD Badge (phase indicator + navigation)
              if (_isEchoSearchMode) ...[
                // 🔮 Entry animation (expanding ring)
                Positioned.fill(
                  child: _buildEchoSearchEntryAnimation(),
                ),
                // HUD badge (RepaintBoundary isolates its repaints)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  right: 16,
                  child: RepaintBoundary(
                    child: _buildEchoSearchHudBadge(),
                  ),
                ),
              ],

              // ✍️ Smart Ink Overlay — tap-to-reveal recognized handwriting
              ValueListenableBuilder<int>(
                valueListenable: _uiRebuildNotifier,
                builder: (context, _, __) {
                  final smartInk = buildSmartInkOverlay(context);
                  if (smartInk == null) return const SizedBox.shrink();
                  return smartInk;
                },
              ),
              // 🎯 Context Menus & Panels (above everything)
              // Wrapped in ValueListenableBuilder so menus rebuild when
              // _uiRebuildNotifier fires (e.g. lasso selection completion).
              ValueListenableBuilder<int>(
                valueListenable: _uiRebuildNotifier,
                builder: (context, _, __) => Stack(
                  children: _buildMenus(context),
                ),
              ),

              // 🔮 Atlas Holographic Response Cards — rendered ABOVE menus
              for (int i = 0; i < _atlasCards.length; i++)
                AtlasResponseCard(
                  key: ValueKey('atlas_card_${_atlasCards[i].id}'),
                  cardId: _atlasCards[i].id,
                  position: _atlasCards[i].position,
                  responseText: _atlasCards[i].text,
                  accentColor: _effectiveSelectedColor,
                  // 🌟 Self-rating (proactive cards only)
                  showSelfRating: _atlasCards[i].sourceClusterId != null ||
                      _atlasCards[i].showSelfRating,
                  masteredConcepts: _sessionMastered,
                  onSessionSummary: _atlasCards[i].sourceClusterId != null
                      ? _showSessionSummary
                      : null,
                  // ✏️ Active recall — Verifica chip trigger
                  onVerify: _atlasCards[i].sourceClusterId != null
                      ? () {
                          final card = _atlasCards[i];
                          final srcId = card.sourceClusterId!;
                          // Pick first un-mastered gap concept
                          final concept = card.gapChips
                              .where((g) => !_sessionMastered.contains(g))
                              .firstOrNull ?? card.gapChips.firstOrNull;
                          if (concept != null) _openVerifyCard(concept, srcId);
                        }
                      : null,
                  // ✏️ Verify mode: verifyQuestion + evaluation callback
                  verifyQuestion: _atlasCards[i].verifyQuestion,
                  verifyCandidates: _atlasCards[i].verifyQuestion == null
                      ? () {
                          // Sort by SR urgency: soonest next-review = most failed = first
                          final farFuture = DateTime.now().add(const Duration(days: 365));
                          final unsorted = _atlasCards[i].gapChips
                              .where((g) => !_sessionMastered.contains(g))
                              .toList();
                          unsorted.sort((a, b) {
                            final da = _reviewSchedule[a]?.nextReview ?? farFuture;
                            final db = _reviewSchedule[b]?.nextReview ?? farFuture;
                            return da.compareTo(db); // nearest review = highest priority
                          });
                          return unsorted;
                        }()
                      : null,
                  onVerifySubmit: (_atlasCards[i].verifyQuestion != null ||
                      _atlasCards[i].gapChips.isNotEmpty)
                      ? (concept, answer, mode) => _onVerifyAnswer(
                            _atlasCards[i].id, concept, answer, mode)
                      : null,
                  onVerifyReset: () {
                    setState(() {
                      final c = _atlasCards.where((c) => c.id == _atlasCards[i].id).firstOrNull;
                      if (c != null) c.text = '';
                    });
                  },

                  onSelfRate: (rating) {
                    final card = _atlasCards[i];
                    if (rating == 1) {
                      // 🟢 Lo so già → dismiss, mark mastered + schedule 7d review
                      final gaps = card.gapChips;
                      for (final g in gaps) {
                        _sessionMastered.add(g);
                        final existing = _reviewSchedule[g] ?? SrsCardData.newCard();
                        _reviewSchedule[g] = FsrsScheduler.review(existing, quality: 2, confidence: 5);
                      }
                      _saveSpacedRepetition(); // persist to disk
                      setState(() => _atlasCards.removeWhere((c) => c.id == card.id));
                    } else {
                      // 🔴🟡 Keep card, store rating for chip behavior
                      setState(() => card.selfRating = rating);
                    }
                  },
                  // 💡 Gap chips for proactive cards
                  gapChips: _atlasCards[i].gapChips.isNotEmpty
                      ? _atlasCards[i].gapChips
                      : null,
                  onGapChipTap: _atlasCards[i].sourceClusterId != null
                      ? (concept) {
                          final srcId = _atlasCards[i].sourceClusterId!;
                          _sessionExplored.add(concept);
                          // FSRS: use adaptive scheduler for gap chip taps
                          final existing = _reviewSchedule[concept];
                          if (existing == null) {
                            // First visit: create new card
                            _reviewSchedule[concept] = FsrsScheduler.review(
                              SrsCardData.newCard(), quality: 1,
                            );
                          } else if (existing.isDue) {
                            // Revisit when due: review with partial quality
                            _reviewSchedule[concept] = FsrsScheduler.review(
                              existing, quality: 1,
                            );
                          }
                          _saveSpacedRepetition(); // persist to disk
                          // Always give direct explanation — no Socratic mode
                          _createNodeFromGap(concept, srcId);
                        }
                      : null,
                  onCornell: _atlasCards[i].sourceClusterId != null
                      ? (concept) => _generateCornellQuestion(
                            concept, _atlasCards[i].sourceClusterId!)
                      : null,
                  onPreLettura: _atlasCards[i].sourceClusterId != null
                      ? () => _generatePreLettura(_atlasCards[i].sourceClusterId!)
                      : null,
                  onNavigateCluster: _atlasCards[i].sourceClusterId != null
                      ? () {
                          _navigateToCluster(_atlasCards[i].sourceClusterId!);
                        }
                      : null,
                  onClusterHide: _atlasCards[i].sourceClusterId != null
                      ? () => _clusterHide(_atlasCards[i].sourceClusterId!)
                      : null,
                  onFeynman: _atlasCards[i].sourceClusterId != null
                      ? (concept) => _feynmanMode(
                            concept, _atlasCards[i].sourceClusterId!)
                      : null,
                  verifyInitialMode: _atlasCards[i].verifyInitialMode,
                  onStemExercise: _atlasCards[i].sourceClusterId != null
                      ? () => _generateStemExercise(_atlasCards[i].sourceClusterId!)
                      : null,
                  onDashboard: () => _showStudyDashboard(),
                  onInterleave: () => _openInterleavedVerify(),
                  onExport: () => _exportStudyData(),
                  onBookmark: (text) {
                    HapticFeedback.mediumImpact();
                    debugPrint('⭐ Bookmarked: ${text.length > 60 ? '${text.substring(0, 57)}...' : text}');
                  },
                  stackIndex: i,
                  totalCards: _atlasCards.length,
                  conversationHistory: _atlasCards[i].conversationHistory,
                  onDismiss: () {
                    final id = _atlasCards[i].id;
                    final srcId = _atlasCards[i].sourceClusterId;
                    if (mounted) {
                      // 🌟 Auto-hide: keep status as 'seen' so dot disappears
                      if (srcId != null) {
                        // dot won't show because filter only renders ready/pending
                        _saveSeenClusters(); // persist to disk
                        // ➡️ Hint: point to the nearest OTHER ready dot
                        final screenCenter = Offset(
                          MediaQuery.of(context).size.width / 2,
                          MediaQuery.of(context).size.height / 2,
                        );
                        final otherReady = _proactiveCache.entries
                            .where((e) =>
                                e.key != srcId &&
                                e.value.status == ProactiveStatus.ready)
                            .map((e) {
                              final c = _clusterCache
                                  .where((c) => c.id == e.key)
                                  .firstOrNull;
                              return c == null
                                  ? null
                                  : _canvasController.canvasToScreen(c.centroid);
                            })
                            .whereType<Offset>()
                            .toList();
                        if (otherReady.isNotEmpty) {
                          otherReady.sort((a, b) =>
                              (a - screenCenter).distanceSquared.compareTo(
                                  (b - screenCenter).distanceSquared));
                          _nextDotHintTimer?.cancel();
                          setState(() => _nextDotHintTarget = otherReady.first);
                          _nextDotHintTimer = Timer(const Duration(seconds: 3), () {
                            if (mounted) setState(() => _nextDotHintTarget = null);
                          });
                        }
                      }
                      setState(() => _atlasCards.removeWhere((c) => c.id == id));
                    }
                  },
                  onDismissAll: () {
                    if (mounted) {
                      HapticFeedback.mediumImpact();
                      setState(() => _atlasCards.clear());
                    }
                  },
                  onGoDeeper: (chain) {
                    final pos = _atlasCards[i].position;
                    final id = _atlasCards[i].id;
                    if (mounted) {
                      setState(() => _atlasCards.removeWhere((c) => c.id == id));
                    }
                    _goDeeper(chain, pos);
                  },
                  onFollowUp: (question) {
                    final ctx = _atlasCards[i].text;
                    final pos = _atlasCards[i].position;
                    _followUpFromCard(question, ctx, pos);
                  },
                  onSearchWeb: (topic) {
                    final query = Uri.encodeComponent(topic);
                    final url = 'https://www.google.com/search?q=$query';
                    Clipboard.setData(ClipboardData(text: url));
                    HapticFeedback.lightImpact();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('🔗 ${topic.length > 40 ? '${topic.substring(0, 37)}...' : topic}'),
                        duration: const Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(label: 'Apri', textColor: const Color(0xFF00E5FF), onPressed: () {
                          // Use the same share channel that already exists natively
                          const MethodChannel('fluera/share').invokeMethod('openUrl', {'url': url});
                        }),
                      ));
                    }
                  },
                  onSaveAsNote: (text) {
                    final id = _atlasCards[i].id;
                    _saveAtlasResponseAsNote(text);
                    if (mounted) {
                      setState(() => _atlasCards.removeWhere((c) => c.id == id));
                    }
                  },
                  onRetry: () {
                    _analyzeSelection();
                  },
                  onExtractLatex: (latexSources) {
                    if (latexSources.isEmpty) return;

                    // Position: selection center, or center of current viewport
                    final selBounds = _lassoTool.getSelectionBounds();
                    final double baseX;
                    final double baseY;
                    if (selBounds != null) {
                      baseX = selBounds.center.dx;
                      baseY = selBounds.bottom + 40;
                    } else {
                      // Use center of visible canvas area
                      final screenCenter = Offset(
                        MediaQuery.of(context).size.width / 2,
                        MediaQuery.of(context).size.height / 2,
                      );
                      final canvasCenter = _canvasController.screenToCanvas(screenCenter);
                      baseX = canvasCenter.dx;
                      baseY = canvasCenter.dy;
                    }

                    debugPrint('🧮 Extracting ${latexSources.length} formulas at ($baseX, $baseY)');
                    for (final src in latexSources) { debugPrint('  → "$src"'); }

                    final rootGroup = _layerController.sceneGraph.rootNode;
                    for (int f = 0; f < latexSources.length; f++) {
                      final node = LatexNode(
                        id: NodeId(generateUid()),
                        latexSource: latexSources[f],
                        fontSize: 24.0,
                        color: const Color(0xFF00E5FF),
                      );
                      // Compute layout so the renderer has draw commands (not just placeholder)
                      try {
                        final ast = LatexParser.parse(latexSources[f]);
                        debugPrint('  📐 AST type: ${ast.runtimeType}');
                        final layout = LatexLayoutEngine.layout(
                          ast, fontSize: 24.0, color: const Color(0xFF00E5FF),
                        );
                        debugPrint('  📐 Layout: ${layout.commands.length} cmds, size=${layout.size}');
                        node.cachedLayout = layout;
                      } catch (e, st) {
                        debugPrint('⚠️ LaTeX parse/layout error: $e\n$st');
                      }
                      node.localTransform.setTranslationRaw(
                        baseX - 60, baseY + f * 80, 0,
                      );
                      _commandHistory.execute(
                        AddLatexNodeCommand(parent: rootGroup, latexNode: node),
                      );
                    }

                    _layerController.sceneGraph.bumpVersion();
                    setState(() {});
                    _autoSaveCanvas();
                    HapticFeedback.heavyImpact();

                    // Navigate camera to show the newly created node
                    final screenSize = MediaQuery.of(context).size;
                    final targetOffset = Offset(
                      screenSize.width / 2 - baseX * _canvasController.scale,
                      screenSize.height / 2 - baseY * _canvasController.scale,
                    );
                    _canvasController.animateOffsetTo(targetOffset);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('🧮 ${latexSources.length == 1 ? "Formula estratta!" : "${latexSources.length} formule estratte!"}'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  },
                ),

              // 🔷 Shape recognition toast
              _buildShapeRecognitionToast(),

              // 💡 PROACTIVE GAP DOTS — appear near clusters when AI has analyzed them
              // Driven by _uiRebuildNotifier so they update when analysis completes.
              ..._proactiveCache.entries
                  .where((e) =>
                      e.value.status == ProactiveStatus.ready ||
                      e.value.status == ProactiveStatus.pending)
                  .map((e) {
                    // Find matching cluster for screen position
                    final cluster = _clusterCache
                        .where((c) => c.id == e.key)
                        .firstOrNull;
                    if (cluster == null) return const SizedBox.shrink();
                    final screenPos = _canvasController
                        .canvasToScreen(cluster.centroid);
                    return AnimatedBuilder(
                      animation: _canvasController,
                      builder: (_, __) {
                        final pos = _canvasController
                            .canvasToScreen(cluster.centroid);
                        final gapCount = e.value.gaps.length;
                        final allMastered = gapCount > 0 &&
                            e.value.gaps.every(
                                (g) => _sessionMastered.contains(g));
                        return ProactiveClusterDot(
                          key: ValueKey('dot_${e.key}'),
                          screenPosition: pos,
                          entry: e.value,
                          gapCount: gapCount,
                          allMastered: allMastered,
                          onTap: () => _showProactiveCard(cluster),
                        );
                      },
                    );
                  })
                  .toList(),


              // 🙈 HIDDEN CLUSTER OVERLAY — frosted glass over clusters in _hiddenClusters
              ..._hiddenClusters.map((clusterId) {
                final cluster = _clusterCache
                    .where((c) => c.id == clusterId)
                    .firstOrNull;
                if (cluster == null) return const SizedBox.shrink();
                return AnimatedBuilder(
                  animation: _canvasController,
                  builder: (_, __) {
                    final pos = _canvasController
                        .canvasToScreen(cluster.centroid);
                    final scale = _canvasController.scale;
                    final size = 120.0 * scale.clamp(0.3, 2.0);
                    return Positioned(
                      left: pos.dx - size / 2,
                      top: pos.dy - size / 2,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _revealCluster(clusterId);
                        },
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            // Opaque overlay — much cheaper than BackdropFilter
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFF48FB1).withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🙈', style: TextStyle(fontSize: 28)),
                                SizedBox(height: 4),
                                Text('Tap per rivelare',
                                  style: TextStyle(
                                    color: Color(0xFFF48FB1),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),

              // 👻 Ghost shape suggestion overlay
              _buildGhostSuggestionOverlay(),

              // ➡️ Next-dot hint — pulsing arrow toward nearest ready dot (3s auto-dismiss)
              if (_nextDotHintTarget != null)
                Positioned(
                  left: _nextDotHintTarget!.dx - 16,
                  top: _nextDotHintTarget!.dy - 36,
                  child: IgnorePointer(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 300),
                      builder: (_, v, __) => Opacity(
                        opacity: v * 0.85,
                        child: const Text(
                          '↓',
                          style: TextStyle(
                            fontSize: 22,
                            color: Color(0xFF00E5FF),
                            shadows: [Shadow(
                              color: Color(0xFF00E5FF),
                              blurRadius: 12,
                            )],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),


              // 🔄 Wheel/Toolbar toggle pill (auto-hides after 4s)
              Positioned(
                top: _useRadialWheel ? 16 : null,
                bottom: _useRadialWheel ? null : 80,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _wheelPillVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: IgnorePointer(
                    ignoring: !_wheelPillVisible,
                    child: GestureDetector(
                      onTap: _toggleWheelMode,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _useRadialWheel
                              ? const Color(0xFF1E88E5).withValues(alpha: 0.92)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _useRadialWheel
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_useRadialWheel
                                  ? const Color(0xFF1E88E5)
                                  : Colors.black).withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Animated icon rotation
                            TweenAnimationBuilder<double>(
                              tween: Tween(end: _useRadialWheel ? 1.0 : 0.0),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutBack,
                              builder: (_, val, child) => Transform.rotate(
                                angle: val * 3.14159,
                                child: child,
                              ),
                              child: Icon(
                                _useRadialWheel
                                    ? Icons.dashboard_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _useRadialWheel ? 'Toolbar' : 'Wheel',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 🔘 Small dot indicator (visible when pill is hidden)
              if (!_wheelPillVisible)
                Positioned(
                  top: _useRadialWheel ? 22 : null,
                  bottom: _useRadialWheel ? null : 88,
                  right: 22,
                  child: GestureDetector(
                    onTap: _showWheelPill,
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: _useRadialWheel
                            ? const Color(0xFF1E88E5).withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),

              // 2️⃣ Toast confirmation overlay
              if (_wheelModeToastVisible && _wheelModeToast != null)
                Positioned(
                  top: _useRadialWheel ? 60 : null,
                  bottom: _useRadialWheel ? null : 130,
                  left: 0, right: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _wheelModeToastVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _wheelModeToast!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),



              // 🎬 Loading overlay (splash screen during initialization)
              _buildLoadingOverlay(),

              // ⏱️ Time Travel overlay (timeline + controls)
              if (_isTimeTravelMode && _timeTravelEngine != null)
                TimeTravelTimelineWidget(
                  engine: _timeTravelEngine!,
                  onExit: _exitTimeTravelMode,
                  onExportRequested: _exportTimelapse,
                  onNewBranch: _createBranchFromCurrentPosition,
                  onBranchExplorer: _openBranchExplorer,
                  onRecoverRequested: () {
                    // Recover current state elements into the present
                    final layers = _timeTravelEngine!.currentLayers;
                    final strokes =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.strokes)
                            .toList();
                    final shapes =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.shapes)
                            .toList();
                    final images =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.images)
                            .toList();
                    final texts =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.texts)
                            .toList();
                    _recoverElementsFromPast(strokes, shapes, images, texts);
                  },
                  activeBranchName: _activeBranchName,
                ),

              // 🧠 Conscious Architecture: debug overlay (debug builds only)
              // if (kDebugMode) const ConsciousDebugOverlay(),

              // 🏎️ Performance Monitor: now managed as a global OverlayEntry
              // (see CanvasPerformanceMonitor.showGlobalOverlay) so it persists
              // across Navigator routes (ImageViewer, PDF Reader, LaTeX, etc.).
            ],
          ),
        ),
      ),
    ); // Focus + Scaffold
  }

  /// Resolve the currently active PDF document for toolbar interaction.
  ///
  /// Uses [_activePdfDocumentId] if set and found, otherwise falls back to
  /// the first [PdfDocumentNode] in the layer tree.
  PdfDocumentNode? get _activePdfDocument {
    if (_activePdfDocumentId != null) {
      final found = _findPdfDocumentById(_activePdfDocumentId!);
      if (found != null) return found;
    }
    return _findFirstPdfDocument();
  }

  /// Find the first [PdfDocumentNode] in the layer tree.
  PdfDocumentNode? _findFirstPdfDocument() {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) return child;
      }
    }
    return null;
  }

  /// Find all [PdfDocumentNode]s in the layer tree.
  List<PdfDocumentNode> _findAllPdfDocuments() {
    final docs = <PdfDocumentNode>[];
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) docs.add(child);
      }
    }
    return docs;
  }

  /// Find a specific [PdfDocumentNode] by its document ID.
  PdfDocumentNode? _findPdfDocumentById(String documentId) {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode && child.id == documentId) return child;
      }
    }
    return null;
  }

  /// 📐 Helper: builds a styled PopupMenuItem for the Quick Format Picker.
  PopupMenuItem<ExportPageFormat> _formatMenuItem(
    ExportPageFormat format, String title, String subtitle,
  ) {
    final isSelected = _multiPageConfig.pageFormat == format;
    return PopupMenuItem<ExportPageFormat>(
      value: format,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: isSelected ? const Color(0xFF007AFF) : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(
                color: Colors.white, 
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              )),
              Text(subtitle, style: const TextStyle(
                color: Colors.white54, fontSize: 11,
              )),
            ],
          ),
        ],
      ),
    );
  }

  /// 📤 Multi-Page Export Toolbar / Confirmation Bar
  ///
  /// This floating bar provides actions to commit or cancel the multi-page
  /// selections made via the [InteractivePageGridOverlay].
  Widget _buildMultiPageExportBottomBar(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 32,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🔍 Cluster Navigation (only when multiple clusters detected)
                  if (_exportClusters.length > 1) ...[
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white, size: 18),
                      tooltip: 'Cluster Prec.',
                      onPressed: _prevExportCluster,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                    ),
                    GestureDetector(
                      onTap: _frameAllClusters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _currentClusterIndex >= 0
                              ? const Color(0xFF007AFF).withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _currentClusterIndex >= 0
                              ? '${_currentClusterIndex + 1}/${_exportClusters.length}'
                              : 'All',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white, size: 18),
                      tooltip: 'Cluster Succ.',
                      onPressed: _nextExportCluster,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 2),
                    Container(width: 1, height: 20, color: Colors.white24),
                    const SizedBox(width: 2),
                  ],
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    tooltip: 'Add Page',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _addMultiPagePage();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 20),
                    tooltip: 'Remove Page',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _removeMultiPagePage();
                    },
                  ),
              const SizedBox(width: 4),
              GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  final RenderBox button = context.findRenderObject() as RenderBox;
                  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                  final position = button.localToGlobal(
                    Offset(button.size.width / 2, 0),
                    ancestor: overlay,
                  );
                  showMenu<ExportPageFormat>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      position.dx - 80,
                      position.dy - 320,
                      position.dx + 80,
                      position.dy,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    color: Colors.grey[900],
                    items: [
                      _formatMenuItem(ExportPageFormat.a4Portrait, 'A4 Portrait', '210×297mm'),
                      _formatMenuItem(ExportPageFormat.a4Landscape, 'A4 Landscape', '297×210mm'),
                      _formatMenuItem(ExportPageFormat.a3Portrait, 'A3 Portrait', '297×420mm'),
                      _formatMenuItem(ExportPageFormat.letterPortrait, 'Letter', '8.5×11in'),
                      _formatMenuItem(ExportPageFormat.letterLandscape, 'Letter Land.', '11×8.5in'),
                    ],
                  ).then((format) {
                    if (format != null && mounted) {
                      _onMultiPageFormatChanged(format);
                      HapticFeedback.selectionClick();
                      // Re-frame with the new format
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _autoFrameMultiPage();
                      });
                    }
                  });
                },
                child: IconButton(
                  icon: Icon(
                     _multiPageConfig.mode == MultiPageMode.uniform 
                        ? Icons.grid_view_rounded 
                        : Icons.crop_free_rounded, 
                     color: Colors.white,
                  ),
                  tooltip: 'Tap: Griglia/Libera • Long: Formato',
                  onPressed: _toggleMultiPageMode,
                ),
              ),
              IconButton(
                icon: Icon(
                   _exportConfig.background == ExportBackground.transparent 
                      ? Icons.layers_clear 
                      : Icons.layers, 
                   color: Colors.white,
                ),
                tooltip: 'Sfondo (Trasparente/Template)',
                onPressed: _toggleExportBackground,
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent),
                tooltip: 'Auto-Frame Content',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _autoFrameMultiPage();
                },
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 24,
                color: Colors.white24,
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _exitMultiPageEditMode(saveChanges: false);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _confirmMultiPageEdit();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF), // iOS Blue
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(
                  'Export ${_multiPageConfig.pageCount} Pages',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}
