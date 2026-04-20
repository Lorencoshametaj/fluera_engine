part of 'pdf_reader_screen.dart';

// =============================================================================
// PDF Text Extraction Bottom Sheet (v2)
// =============================================================================

class _PdfTextSheet extends StatefulWidget {
  final int pageIndex;
  final Future<String> textFuture;
  const _PdfTextSheet({required this.pageIndex, required this.textFuture});
  @override
  State<_PdfTextSheet> createState() => _PdfTextSheetState();
}

class _PdfTextSheetState extends State<_PdfTextSheet> {
  bool _copied = false;
  final _searchCtrl = TextEditingController();
  bool _showSearch = false;
  String _query = '';
  bool _atlasLoading = false;
  String _atlasReply = '';
  StreamSubscription<String>? _atlasSub;

  @override
  void dispose() { _searchCtrl.dispose(); _atlasSub?.cancel(); super.dispose(); }

  int _wordCount(String t) => t.trim().isEmpty ? 0 : t.trim().split(RegExp(r'\s+')).length;

  Future<void> _askAtlas(String text) async {
    if (text.isEmpty || _atlasLoading) return;
    setState(() { _atlasLoading = true; _atlasReply = ''; });
    HapticFeedback.lightImpact();
    try {
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) await provider.initialize();
      final prompt = 'Sei ATLAS, un tutor accademico di alto livello. '
        'L\'utente sta leggendo un documento PDF. '
        'Analizza il seguente testo estratto dalla pagina ${widget.pageIndex + 1} e fornisci:\n'
        '1. Un riassunto conciso (max 3 frasi)\n2. I 3 concetti chiave\n3. Una domanda di riflessione\n\n'
        'Rispondi nella stessa lingua del testo.\n\n---\n$text\n---';
      final buffer = StringBuffer();
      final stream = provider.askAtlasStream(prompt, []);
      _atlasSub = stream.timeout(const Duration(seconds: 30), onTimeout: (s) => s.close()).listen(
        (chunk) { buffer.write(chunk); if (mounted) setState(() => _atlasReply = buffer.toString()); },
        onDone: () { if (mounted) setState(() => _atlasLoading = false); },
        onError: (_) { if (mounted) setState(() { _atlasLoading = false; if (_atlasReply.isEmpty) _atlasReply = '⚠️ Errore nella risposta di Atlas.'; }); },
      );
    } catch (e) {
      if (mounted) setState(() { _atlasLoading = false; _atlasReply = '⚠️ Atlas non disponibile: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(initialChildSize: 0.65, minChildSize: 0.35, maxChildSize: 0.95, builder: (ctx, scrollCtrl) {
      return FutureBuilder<String>(future: widget.textFuture, builder: (context, snap) {
        final isLoading = snap.connectionState != ConnectionState.done;
        final text = snap.data ?? '';
        final hasText = text.isNotEmpty;
        return Container(
          decoration: const BoxDecoration(color: Color(0xFF12122A), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 12, 8), child: Row(children: [
              const Icon(Icons.text_snippet_rounded, color: Color(0xFF80DEEA), size: 18), const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pagina ${widget.pageIndex + 1} — Testo estratto', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                if (!isLoading && hasText) Text('${_wordCount(text)} parole · ${text.length} caratteri', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
              IconButton(onPressed: () => setState(() { _showSearch = !_showSearch; if (!_showSearch) { _searchCtrl.clear(); _query = ''; } }),
                icon: Icon(_showSearch ? Icons.search_off_rounded : Icons.search_rounded, color: _showSearch ? const Color(0xFF80DEEA) : Colors.white38, size: 20), visualDensity: VisualDensity.compact, tooltip: 'Cerca nel testo'),
              if (hasText && !isLoading) GestureDetector(
                onTap: () async { await Clipboard.setData(ClipboardData(text: text)); setState(() => _copied = true); await Future.delayed(const Duration(seconds: 2)); if (mounted) setState(() => _copied = false); },
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: _copied ? const Color(0xFF4CAF50).withValues(alpha: 0.2) : const Color(0xFF80DEEA).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _copied ? const Color(0xFF4CAF50) : const Color(0xFF80DEEA).withValues(alpha: 0.5), width: 0.8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 13, color: _copied ? const Color(0xFF4CAF50) : const Color(0xFF80DEEA)),
                    const SizedBox(width: 4),
                    Text(_copied ? 'Copiato!' : 'Copia', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _copied ? const Color(0xFF4CAF50) : const Color(0xFF80DEEA))),
                  ]))),
            ])),
            AnimatedSize(duration: const Duration(milliseconds: 200), curve: Curves.easeOut,
              child: _showSearch ? Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: TextField(
                controller: _searchCtrl, autofocus: true, onChanged: (v) => setState(() => _query = v.toLowerCase()),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(hintText: 'Cerca nel testo…', hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                  suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 16), onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); }) : null,
                  filled: true, fillColor: Colors.white10, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))) : const SizedBox.shrink()),
            const Divider(color: Colors.white10, height: 1),
            Expanded(child: SingleChildScrollView(controller: scrollCtrl, padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (isLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Column(children: [
                  CircularProgressIndicator(color: Color(0xFF80DEEA), strokeWidth: 2), SizedBox(height: 16),
                  Text('Estrazione in corso…', style: TextStyle(color: Colors.white38, fontSize: 13))])))
                else if (!hasText) const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.text_fields_rounded, color: Colors.white24, size: 40), SizedBox(height: 12),
                  Text('Nessun testo trovato.\nPotrebbe essere un PDF scansionato.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5))]))
                else if (_query.isNotEmpty) ..._buildFilteredParagraphs(text, _query)
                else SelectableText(text, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13.5, height: 1.7, letterSpacing: 0.1)),
                if (!isLoading && hasText) ...[
                  const SizedBox(height: 20), const Divider(color: Colors.white10), const SizedBox(height: 12),
                  if (_atlasReply.isEmpty && !_atlasLoading) _AtlasCta(onTap: () => _askAtlas(text))
                  else _AtlasReplyCard(reply: _atlasReply, isLoading: _atlasLoading),
                ],
              ]))),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ]),
        );
      });
    });
  }

  List<Widget> _buildFilteredParagraphs(String text, String query) {
    final paragraphs = text.split('\n').where((p) => p.trim().isNotEmpty).toList();
    final matches = paragraphs.where((p) => p.toLowerCase().contains(query)).toList();
    if (matches.isEmpty) return [Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Nessun risultato per "$_query".', style: const TextStyle(color: Colors.white38, fontSize: 13)))];
    return [
      Text('${matches.length} risultat${matches.length == 1 ? 'o' : 'i'} per "$_query"', style: const TextStyle(color: Color(0xFF80DEEA), fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      for (final para in matches) _HighlightedParagraph(text: para, query: query),
    ];
  }
}

// ── Highlighted paragraph widget ──
class _HighlightedParagraph extends StatelessWidget {
  final String text; final String query;
  const _HighlightedParagraph({required this.text, required this.query});
  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase(); final spans = <TextSpan>[]; int start = 0;
    while (true) {
      final idx = lower.indexOf(query, start);
      if (idx < 0) { spans.add(TextSpan(text: text.substring(start))); break; }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(text: text.substring(idx, idx + query.length), style: const TextStyle(backgroundColor: Color(0x4480DEEA), color: Color(0xFF80DEEA), fontWeight: FontWeight.w700)));
      start = idx + query.length;
    }
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(width: double.infinity, padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0x2080DEEA))),
      child: RichText(text: TextSpan(style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13, height: 1.6), children: spans))));
  }
}

// ── Atlas CTA button ──
class _AtlasCta extends StatelessWidget {
  final VoidCallback onTap;
  const _AtlasCta({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF80DEEA)], begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))]),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18), SizedBox(width: 8),
        Text('Chiedi all\u2019IA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))])));
  }
}

// ── Atlas reply card ──
class _AtlasReplyCard extends StatelessWidget {
  final String reply; final bool isLoading;
  const _AtlasReplyCard({required this.reply, required this.isLoading});
  @override
  Widget build(BuildContext context) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E1E40), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C63FF), size: 15), const SizedBox(width: 6),
          const Text('Risposta', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600, fontSize: 13)),
          if (isLoading) ...[const SizedBox(width: 8), const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF6C63FF)))],
        ]),
        const SizedBox(height: 8),
        SelectableText(reply.isNotEmpty ? reply : '…', style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13, height: 1.65)),
      ]));
  }
}
