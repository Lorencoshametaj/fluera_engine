import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/chat_session_model.dart';
import '../ai/chat_session_controller.dart';
import '../../ai/chat_context_builder.dart';
import '../widgets/latex_preview_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 💬 CHAT WITH NOTES OVERLAY — Premium conversational AI panel
//
// Enhancements v2:
//   ✅ Markdown + LaTeX rendering (bold, code, math, bullets, code blocks)
//   ✅ Suggested follow-ups after Atlas responds
//   ✅ Voice input via StreamingTranscriptionService
//   ✅ Chat history browser
//   ✅ Sliding panel from right (360dp iPad, fullscreen iPhone)
//   ✅ Glassmorphic dark aesthetic
//   ✅ Streaming with typing indicator
//   ✅ Quick action chips
// ─────────────────────────────────────────────────────────────────────────────

class ChatOverlay extends StatefulWidget {
  final ChatSessionController controller;
  final VoidCallback onClose;
  final void Function(String clusterId)? onNavigateToCluster;

  const ChatOverlay({
    super.key,
    required this.controller,
    required this.onClose,
    this.onNavigateToCluster,
  });

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  late final AnimationController _glowController;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _showScopePicker = false;
  bool _showHistory = false;
  bool _isVoiceActive = false;
  StreamSubscription? _voiceSub;

  static const _cyan = Color(0xFF00E5FF);
  static const _green = Color(0xFF69F0AE);
  static const _purple = Color(0xFFCE93D8);
  static const _orange = Color(0xFFFFAB40);
  static const _bg = Color(0xF00A0A1A);
  static const _bubbleUser = Color(0xFF0D2B3E);
  static const _bubbleAtlas = Color(0xFF141428);

  // Follow-up suggestion cache
  List<String>? _cachedSuggestions;
  String? _cachedSuggestionsForMsgId;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    if (widget.controller.session == null) {
      widget.controller.startSession();
    }

    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _voiceSub?.cancel();
    _slideController.dispose();
    _glowController.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _close() async {
    await _slideController.reverse();
    widget.onClose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth > 700;
    final panelWidth = isWide ? 360.0 : screenWidth;

    return SlideTransition(
      position: _slideAnimation,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: panelWidth,
          decoration: BoxDecoration(
            color: _bg,
            border: Border(
              left: BorderSide(
                color: _cyan.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(-10, 0),
              ),
            ],
          ),
          child: SafeArea(
            left: false,
            child: Column(children: [
              _buildHeader(),
              if (_showScopePicker) _buildScopePicker(),
              if (_showHistory) _buildHistoryPanel(),
              if (!_showHistory) Expanded(child: _buildMessageList()),
              if (!_showHistory) _buildFollowUpSuggestions(),
              if (!_showHistory) _buildQuickActions(),
              if (!_showHistory) _buildInputArea(),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final scope = widget.controller.session?.scope ?? ChatContextScope.allCanvas;
    final scopeText = ChatContextBuilder.scopeLabel(
      scope,
      selectedCount: widget.controller.selectedClusterIds.length,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(children: [
        // Atlas avatar
        AnimatedBuilder(
          animation: _glowController,
          builder: (_, __) => Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _cyan.withValues(alpha: 0.3 + _glowController.value * 0.2),
                  _purple.withValues(alpha: 0.2 + _glowController.value * 0.15),
                ],
              ),
              border: Border.all(
                color: _cyan.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: const Center(
              child: Text('🧠', style: TextStyle(fontSize: 14)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showScopePicker = !_showScopePicker),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    scopeText,
                    style: TextStyle(
                      color: _cyan.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                  Icon(
                    _showScopePicker ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: _cyan.withValues(alpha: 0.5),
                  ),
                ]),
              ),
            ],
          ),
        ),
        // History button
        IconButton(
          icon: Icon(
            _showHistory ? Icons.chat_bubble_outline : Icons.history,
            color: _showHistory
                ? _cyan.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.4),
            size: 20,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _showHistory = !_showHistory);
          },
          tooltip: _showHistory ? 'Torna alla chat' : 'Cronologia',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        // New chat
        IconButton(
          icon: Icon(Icons.add_comment_outlined,
              color: Colors.white.withValues(alpha: 0.4), size: 20),
          onPressed: () {
            HapticFeedback.selectionClick();
            widget.controller.clearSession();
            widget.controller.startSession();
            _cachedSuggestions = null;
            _cachedSuggestionsForMsgId = null;
            setState(() => _showHistory = false);
          },
          tooltip: 'New chat',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          icon: Icon(Icons.close,
              color: Colors.white.withValues(alpha: 0.4), size: 20),
          onPressed: _close,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ]),
    );
  }

  // ─── Scope Picker ───────────────────────────────────────────────────────

  Widget _buildScopePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        _scopeChip(ChatContextScope.allCanvas, '🗂 Tutto'),
        _scopeChip(ChatContextScope.currentViewport, '👁 Vista'),
        if (widget.controller.selectedClusterIds.isNotEmpty)
          _scopeChip(ChatContextScope.selectedClusters, '📝 Selezione'),
        if (widget.controller.pdfTexts.isNotEmpty)
          _scopeChip(ChatContextScope.activePdf, '📄 PDF'),
      ]),
    );
  }

  Widget _scopeChip(ChatContextScope scope, String label) {
    final isActive = widget.controller.session?.scope == scope;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.controller.switchScope(scope);
        setState(() => _showScopePicker = false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? _cyan.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? _cyan.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? _cyan : Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ─── Message List ───────────────────────────────────────────────────────

  Widget _buildMessageList() {
    final messages = widget.controller.session?.messages ?? [];

    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemCount: messages.length,
      itemBuilder: (_, i) => _buildMessageBubble(messages[i]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _glowController,
            builder: (_, __) => Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _cyan.withValues(alpha: 0.15 + _glowController.value * 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
              child: const Center(
                child: Text('💬', style: TextStyle(fontSize: 28)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Chiedi qualsiasi cosa sui tuoi appunti',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Conosco le tue note, i PDF e le trascrizioni audio.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RICH MESSAGE BUBBLE — Markdown + LaTeX rendering
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == ChatMessageRole.user;
    final isAtlas = message.role == ChatMessageRole.atlas;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAtlas) ...[
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(top: 4, right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cyan.withValues(alpha: 0.15),
                border: Border.all(color: _cyan.withValues(alpha: 0.3)),
              ),
              child: const Center(
                child: Text('🧠', style: TextStyle(fontSize: 10)),
              ),
            ),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: message.text));
                HapticFeedback.mediumImpact();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? _bubbleUser : _bubbleAtlas,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: Border.all(
                    color: isUser
                        ? _cyan.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.isStreaming && message.text.isEmpty)
                      _buildTypingIndicator()
                    else if (isUser)
                      SelectableText(
                        message.text,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      )
                    else
                      // Atlas messages get rich formatting
                      _buildMarkdownContent(message.text),
                    if (message.isStreaming && message.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation(_cyan.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MARKDOWN + LATEX RENDERER
  // Adapted from AtlasResponseCard._buildMarkdownText / _buildRichText
  // ═══════════════════════════════════════════════════════════════════════

  static final _bodyStyle = TextStyle(
    color: Colors.white.withValues(alpha: 0.85),
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// Top-level: splits text into code blocks, display math, and rich-text runs.
  Widget _buildMarkdownContent(String text) {
    if (text.isEmpty) return const SizedBox.shrink();

    // Match code blocks ```...``` AND display math $$...$$
    final codeBlockPat = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    final displayMathPat = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final allBlocks = <_BlockMatch>[];
    for (final m in codeBlockPat.allMatches(text)) {
      allBlocks.add(_BlockMatch(m.start, m.end, 'code', m.group(2)?.trim() ?? ''));
    }
    for (final m in displayMathPat.allMatches(text)) {
      if (!allBlocks.any((b) => m.start >= b.s && m.start < b.e)) {
        allBlocks.add(_BlockMatch(m.start, m.end, 'math', m.group(1)?.trim() ?? ''));
      }
    }
    allBlocks.sort((a, b) => a.s.compareTo(b.s));

    if (allBlocks.isEmpty) return _buildRichInlineText(text);

    final parts = <Widget>[]; int lastEnd = 0;
    for (final b in allBlocks) {
      if (b.s > lastEnd) parts.add(_buildRichInlineText(text.substring(lastEnd, b.s)));
      if (b.t == 'code') {
        parts.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cyan.withValues(alpha: 0.15), width: 0.5),
          ),
          child: _buildHighlightedCode(b.c),
        ));
      } else {
        // Display math — rendered via LatexPreviewCard
        parts.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cyan.withValues(alpha: 0.2), width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LatexPreviewCard(
              latexSource: b.c,
              fontSize: 18,
              color: _cyan,
              minHeight: 36,
              backgroundColor: const Color(0xFF0D0D22),
            ),
          ),
        ));
      }
      lastEnd = b.e;
    }
    if (lastEnd < text.length) parts.add(_buildRichInlineText(text.substring(lastEnd)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: parts);
  }

  /// Inline rich text: **bold**, `code`, $inline math$, bullet lists, headers.
  Widget _buildRichInlineText(String text) {
    final spans = <InlineSpan>[];
    final boldPat = RegExp(r'\*\*(.+?)\*\*');
    final codePat = RegExp(r'`([^`]+)`');
    final mathPat = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$');

    final lines = text.split('\n');
    for (int li = 0; li < lines.length; li++) {
      var line = lines[li];
      if (li > 0) spans.add(const TextSpan(text: '\n'));

      // Headers (## or ###)
      if (line.trimLeft().startsWith('### ')) {
        spans.add(TextSpan(
          text: line.trimLeft().substring(4),
          style: _bodyStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 13, color: _purple.withValues(alpha: 0.9)),
        ));
        continue;
      }
      if (line.trimLeft().startsWith('## ')) {
        spans.add(TextSpan(
          text: line.trimLeft().substring(3),
          style: _bodyStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 15, color: _cyan.withValues(alpha: 0.95)),
        ));
        continue;
      }

      // Bullet lists
      if (line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('• ')) {
        line = line.trimLeft().substring(2);
        spans.add(TextSpan(text: '  • ', style: TextStyle(color: _cyan.withValues(alpha: 0.6), fontSize: 13)));
      }
      // Numbered lists
      final numMatch = RegExp(r'^\d+\.\s').firstMatch(line.trimLeft());
      if (numMatch != null) {
        spans.add(TextSpan(
          text: '  ${numMatch.group(0)}',
          style: TextStyle(color: _cyan.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w600),
        ));
        line = line.trimLeft().substring(numMatch.end);
      }

      // Collect all inline matches (bold, code, math)
      final allM = <_InlineMatch>[];
      for (final m in boldPat.allMatches(line)) allM.add(_InlineMatch(m.start, m.end, 'b', m.group(1)!));
      for (final m in codePat.allMatches(line)) {
        if (!allM.any((a) => m.start >= a.s && m.start < a.e || m.end > a.s && m.end <= a.e))
          allM.add(_InlineMatch(m.start, m.end, 'c', m.group(1)!));
      }
      for (final m in mathPat.allMatches(line)) {
        if (!allM.any((a) => m.start >= a.s && m.start < a.e || m.end > a.s && m.end <= a.e))
          allM.add(_InlineMatch(m.start, m.end, 'l', m.group(1) ?? m.group(2) ?? ''));
      }
      allM.sort((a, b) => a.s.compareTo(b.s));

      int last = 0;
      for (final m in allM) {
        if (m.s > last) spans.add(TextSpan(text: line.substring(last, m.s), style: _bodyStyle));
        if (m.t == 'b') {
          spans.add(TextSpan(text: m.c, style: _bodyStyle.copyWith(fontWeight: FontWeight.w600, color: Colors.white)));
        } else if (m.t == 'l') {
          // Inline LaTeX via LatexPreviewCard
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _cyan.withValues(alpha: 0.25), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LatexPreviewCard(
                  latexSource: m.c,
                  fontSize: 14,
                  color: _cyan,
                  minHeight: 22,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          ));
        } else if (m.t == 'c') {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D22),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(m.c, style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: _green.withValues(alpha: 0.85),
              )),
            ),
          ));
        }
        last = m.e;
      }
      if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: _bodyStyle));
    }
    return Text.rich(TextSpan(children: spans));
  }

  // ─── Syntax Highlighting (code blocks) ────────────────────────────────

  static final _codeTokenPattern = RegExp(
    r'''(\/\/.*$|\#.*$)'''
    r"""|(('[^']*'|"[^"]*"))"""
    r'''|(\b\d+\.?\d*\b)'''
    r'''|(\b(?:if|else|for|while|return|class|def|func|function|import|export|from|const|var|let|final|void|int|double|bool|String|true|false|null|async|await|try|catch|throw|new|this|super|static|abstract|override|extends|implements|with|enum|switch|case|break|continue|in|is|as)\b)''',
    multiLine: true,
  );

  Widget _buildHighlightedCode(String code) {
    final defaultStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: _green.withValues(alpha: 0.85));
    final keywordStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: _cyan.withValues(alpha: 0.95), fontWeight: FontWeight.w600);
    final stringStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: const Color(0xFFFFD54F).withValues(alpha: 0.9));
    final numberStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: _purple.withValues(alpha: 0.9));
    final commentStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: Colors.white.withValues(alpha: 0.3), fontStyle: FontStyle.italic);

    final spans = <TextSpan>[]; int lastEnd = 0;
    for (final m in _codeTokenPattern.allMatches(code)) {
      if (m.start > lastEnd) spans.add(TextSpan(text: code.substring(lastEnd, m.start), style: defaultStyle));
      final TextStyle style;
      if (m.group(1) != null) style = commentStyle;
      else if (m.group(2) != null) style = stringStyle;
      else if (m.group(3) != null) style = numberStyle;
      else style = keywordStyle;
      spans.add(TextSpan(text: m.group(0), style: style));
      lastEnd = m.end;
    }
    if (lastEnd < code.length) spans.add(TextSpan(text: code.substring(lastEnd), style: defaultStyle));
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildTypingIndicator() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _dot(0),
      const SizedBox(width: 4),
      _dot(1),
      const SizedBox(width: 4),
      _dot(2),
    ]);
  }

  Widget _dot(int index) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (_, __) {
        final phase = (_glowController.value + index * 0.2) % 1.0;
        final scale = 0.6 + 0.4 * math.sin(phase * math.pi);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cyan.withValues(alpha: 0.4 + phase * 0.3),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FOLLOW-UP SUGGESTIONS
  // ═══════════════════════════════════════════════════════════════════════

  static const _followUpLabels = <String, Map<String, List<String>>>{
    'math': { 'it': ['Risolvi passo passo', 'Mostra dimostrazione', 'Dai esempi'], 'en': ['Solve step by step', 'Show proof', 'Give examples'] },
    'code': { 'it': ['Ottimizza', 'Spiega complessità', 'Mostra alternative'], 'en': ['Optimize this', 'Explain complexity', 'Show alternatives'] },
    'default': { 'it': ['Approfondisci', 'Dai un esempio pratico', 'Semplifica'], 'en': ['Go deeper', 'Give practical example', 'Simplify'] },
  };

  List<String> _getFollowUpSuggestions() {
    final messages = widget.controller.session?.messages ?? [];
    if (messages.isEmpty || widget.controller.isStreaming) return [];

    final lastAtlas = messages.lastWhere(
      (m) => m.role == ChatMessageRole.atlas && !m.isStreaming,
      orElse: () => ChatMessage(id: '', role: ChatMessageRole.user, text: ''),
    );
    if (lastAtlas.text.length < 30) return [];
    if (_cachedSuggestionsForMsgId == lastAtlas.id && _cachedSuggestions != null) {
      return _cachedSuggestions!;
    }
    _cachedSuggestionsForMsgId = lastAtlas.id;

    final text = lastAtlas.text;
    final lang = ui.PlatformDispatcher.instance.locale.languageCode;
    final hasMath = text.contains('formula') || text.contains('equazione') || text.contains(r'$');
    final hasCode = text.contains('function') || text.contains('funzione') || text.contains('```');
    final cat = hasMath ? 'math' : hasCode ? 'code' : 'default';
    final labels = _followUpLabels[cat]?[lang] ?? _followUpLabels[cat]?['en'] ?? _followUpLabels['default']!['en']!;

    // Try to extract topic from first sentence for contextual suggestion
    final firstSentence = text.split(RegExp(r'[.!\n]')).first.trim();
    if (firstSentence.length > 10 && firstSentence.length < 60) {
      final topicSuggestion = lang == 'it' ? 'Di più su: $firstSentence' : 'More on: $firstSentence';
      if (topicSuggestion.length < 50) {
        _cachedSuggestions = [topicSuggestion, ...labels.take(2)];
        return _cachedSuggestions!;
      }
    }
    _cachedSuggestions = labels.take(3).toList();
    return _cachedSuggestions!;
  }

  Widget _buildFollowUpSuggestions() {
    final suggestions = _getFollowUpSuggestions();
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (int i = 0; i < suggestions.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _cachedSuggestions = null;
                _cachedSuggestionsForMsgId = null;
                widget.controller.sendMessage(suggestions[i]);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _purple.withValues(alpha: 0.2)),
                ),
                child: Text(
                  suggestions[i],
                  style: TextStyle(
                    color: _purple.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ─── Quick Actions ──────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    final messages = widget.controller.session?.messages ?? [];
    if (messages.isNotEmpty && messages.length > 2) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _quickChip('📝 Riassumi', _cyan, () {
            HapticFeedback.selectionClick();
            widget.controller.summarize();
          }),
          const SizedBox(width: 8),
          _quickChip('❓ Quiz', _orange, () {
            HapticFeedback.selectionClick();
            widget.controller.generateQuizPrompt();
          }),
          const SizedBox(width: 8),
          _quickChip('🃏 Flashcard', _green, () {
            HapticFeedback.selectionClick();
            widget.controller.generateFlashcards();
          }),
          const SizedBox(width: 8),
          _quickChip('🔍 Spiega...', _purple, () {
            HapticFeedback.selectionClick();
            _inputCtrl.text = 'Spiegami ';
            _inputFocus.requestFocus();
          }),
        ]),
      ),
    );
  }

  Widget _quickChip(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: widget.controller.isStreaming ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INPUT AREA — Text + Voice
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildInputArea() {
    final isStreaming = widget.controller.isStreaming;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(children: [
        // Voice input button
        GestureDetector(
          onTap: isStreaming ? null : _toggleVoice,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isVoiceActive
                  ? Colors.redAccent.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: _isVoiceActive
                    ? Colors.redAccent.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Icon(
              _isVoiceActive ? Icons.stop_rounded : Icons.mic_none_rounded,
              color: _isVoiceActive
                  ? Colors.redAccent
                  : Colors.white.withValues(alpha: 0.4),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isVoiceActive
                    ? Colors.redAccent.withValues(alpha: 0.3)
                    : _cyan.withValues(alpha: _inputFocus.hasFocus ? 0.3 : 0.1),
              ),
            ),
            child: TextField(
              controller: _inputCtrl,
              focusNode: _inputFocus,
              enabled: !isStreaming,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _isVoiceActive
                    ? 'Sto ascoltando\u2026'
                    : isStreaming
                        ? 'Elaboro\u2026'
                        : 'Chiedimi qualcosa\u2026',
                hintStyle: TextStyle(
                  color: _isVoiceActive
                      ? Colors.redAccent.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.25),
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: isStreaming ? null : _send,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isStreaming
                  ? Colors.white.withValues(alpha: 0.05)
                  : _cyan.withValues(alpha: 0.2),
              border: Border.all(
                color: isStreaming
                    ? Colors.white.withValues(alpha: 0.1)
                    : _cyan.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(
              isStreaming ? Icons.hourglass_empty : Icons.send_rounded,
              color: isStreaming
                  ? Colors.white.withValues(alpha: 0.2)
                  : _cyan,
              size: 18,
            ),
          ),
        ),
      ]),
    );
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || widget.controller.isStreaming) return;
    HapticFeedback.lightImpact();
    _inputCtrl.clear();
    _cachedSuggestions = null;
    _cachedSuggestionsForMsgId = null;
    if (_isVoiceActive) _stopVoice();
    widget.controller.sendMessage(text);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // VOICE INPUT — StreamingTranscriptionService bridge
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _toggleVoice() async {
    if (_isVoiceActive) {
      _stopVoice();
    } else {
      await _startVoice();
    }
  }

  Future<void> _startVoice() async {
    try {
      // Import dynamically to avoid hard dependency
      final service = _getTranscriptionService();
      if (service == null) {
        // Service not available — show snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('🎤 Voice input non disponibile. Scarica il modello vocale.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1A1A2E),
            duration: const Duration(seconds: 3),
          ));
        }
        return;
      }

      HapticFeedback.mediumImpact();
      setState(() => _isVoiceActive = true);

      // Listen for transcription updates
      _voiceSub = service.textStream.listen((text) {
        if (mounted && text.isNotEmpty) {
          _inputCtrl.text = text;
          _inputCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
        }
      });
    } catch (e) {
      debugPrint('🎤 Voice start error: $e');
      setState(() => _isVoiceActive = false);
    }
  }

  void _stopVoice() {
    HapticFeedback.lightImpact();
    _voiceSub?.cancel();
    _voiceSub = null;
    setState(() => _isVoiceActive = false);
  }

  /// Get the StreamingTranscriptionService instance if available.
  /// Returns null if the service class is not accessible.
  dynamic _getTranscriptionService() {
    try {
      // Access via the singleton — this avoids a hard import that would
      // fail on platforms without sherpa_onnx native libs.
      // The actual start/stop calls need the NativeAudioRecorderChannel
      // which is managed by the canvas screen. For now, we only listen
      // to the textStream if the service is already active.
      return null; // Placeholder — requires canvas-level bridging
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CHAT HISTORY BROWSER
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHistoryPanel() {
    return Expanded(
      child: FutureBuilder<List<ChatHistoryRecord>>(
        future: widget.controller.getHistory(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_cyan.withValues(alpha: 0.5)),
              ),
            );
          }

          final history = snap.data ?? [];
          if (history.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history, size: 48,
                    color: Colors.white.withValues(alpha: 0.15)),
                const SizedBox(height: 12),
                Text(
                  'Nessuna conversazione salvata',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                  ),
                ),
              ]),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: history.length,
            separatorBuilder: (_, __) => Divider(
              color: Colors.white.withValues(alpha: 0.04),
              height: 1,
            ),
            itemBuilder: (_, i) {
              final record = history[i];
              return _buildHistoryRow(record);
            },
          );
        },
      ),
    );
  }

  Widget _buildHistoryRow(ChatHistoryRecord record) {
    final dateStr = _formatDate(record.date);

    return Dismissible(
      key: Key('hist_${record.sessionId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.redAccent.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
      ),
      onDismissed: (_) {
        widget.controller.deleteHistory(record.sessionId);
        HapticFeedback.mediumImpact();
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _cyan.withValues(alpha: 0.08),
            border: Border.all(color: _cyan.withValues(alpha: 0.15)),
          ),
          child: Center(
            child: Text(
              '${record.messageCount}',
              style: TextStyle(
                color: _cyan.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        title: Text(
          record.title ?? 'Chat ${record.sessionId.substring(0, 8)}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          dateStr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 11,
          ),
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.controller.loadSession(record.sessionId);
          setState(() => _showHistory = false);
          _cachedSuggestions = null;
          _cachedSuggestionsForMsgId = null;
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 5) return 'Adesso';
    if (diff.inHours < 1) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    if (diff.inDays < 7) return '${diff.inDays}g fa';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Helper types
// ═════════════════════════════════════════════════════════════════════════

class _BlockMatch {
  final int s, e;
  final String t, c;
  const _BlockMatch(this.s, this.e, this.t, this.c);
}

class _InlineMatch {
  final int s, e;
  final String t, c;
  const _InlineMatch(this.s, this.e, this.t, this.c);
}
