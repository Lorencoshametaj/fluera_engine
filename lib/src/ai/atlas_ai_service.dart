import 'dart:convert';
import 'dart:ui' as ui;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'ai_provider.dart';
import 'atlas_action.dart';

/// Google Gemini implementation of [AiProvider].
///
/// Uses the `google_generative_ai` package to communicate with Gemini.
/// Configured with a system prompt that instructs Gemini to act as "Atlas",
/// the spatial AI assistant, and to respond exclusively in structured JSON.
///
/// The API key is passed directly instead of using dotenv, making this
/// work cleanly in both package and app contexts.
class GeminiProvider implements AiProvider {
  GenerativeModel? _model;
  GenerativeModel? _streamModel; // For streaming (no JSON constraint)
  bool _initialized = false;

  /// The API key to use for Gemini.
  /// Set via [initialize] or constructor.
  final String? _apiKey;

  /// Create a GeminiProvider.
  ///
  /// If [apiKey] is provided, it will be used directly.
  /// Otherwise, pass it via [initialize].
  GeminiProvider({String? apiKey}) : _apiKey = apiKey;

  @override
  String get name => 'Gemini Flash';

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final key = _apiKey;
    if (key == null || key.isEmpty) {
      throw Exception(
        'Atlas Error: API Key non fornita. '
        'Passa la chiave API al costruttore di GeminiProvider.',
      );
    }

    _model = GenerativeModel(
      model: 'gemini-3.1-flash-lite-preview',
      apiKey: key,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(_systemPrompt),
    );

    // Streaming model — no JSON constraint, for real-time text output
    final langCode = ui.PlatformDispatcher.instance.locale.languageCode;
    const langMap = {'it': 'Italian', 'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German', 'pt': 'Portuguese', 'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese', 'ar': 'Arabic', 'ru': 'Russian'};
    final langName = langMap[langCode] ?? 'English';

    _streamModel = GenerativeModel(
      model: 'gemini-3.1-flash-lite-preview',
      apiKey: key,
      systemInstruction: Content.system(
        'You are ATLAS, an advanced spatial intelligence AI. '
        'Respond directly with the analysis text. No JSON wrapping. '
        'You MUST always respond in $langName.',
      ),
    );

    _initialized = true;
    print('🌌 Atlas AI ($name) inizializzato con successo.');
  }

  @override
  Future<AtlasResponse> askAtlas(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async {
    if (!_initialized || _model == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

    // Compute bounding box of all nodes in context
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in canvasContext) {
      final pos = node['posizione'] as Map<String, dynamic>?;
      final dim = node['dimensioni'] as Map<String, dynamic>?;
      if (pos != null) {
        final nx = (pos['x'] as num?)?.toDouble() ?? 0;
        final ny = (pos['y'] as num?)?.toDouble() ?? 0;
        final nw = (dim?['larghezza'] as num?)?.toDouble() ?? 100;
        final nh = (dim?['altezza'] as num?)?.toDouble() ?? 50;
        if (nx < minX) minX = nx;
        if (ny < minY) minY = ny;
        if (nx + nw > maxX) maxX = nx + nw;
        if (ny + nh > maxY) maxY = ny + nh;
      }
    }

    final payload = jsonEncode({
      'comando_utente': userPrompt,
      'area_selezione': {
        'x_min': minX.isFinite ? minX.roundToDouble() : 0,
        'y_min': minY.isFinite ? minY.roundToDouble() : 0,
        'x_max': maxX.isFinite ? maxX.roundToDouble() : 800,
        'y_max': maxY.isFinite ? maxY.roundToDouble() : 600,
        'centro_x': minX.isFinite ? ((minX + maxX) / 2).roundToDouble() : 400,
        'centro_y': minY.isFinite ? ((minY + maxY) / 2).roundToDouble() : 300,
      },
      'nodi_nel_contesto': canvasContext,
    });

    try {
      print('🚀 Invio mappa spaziale ad Atlas ($name)...');
      final response = await _model!.generateContent([Content.text(payload)]);

      if (response.text != null) {
        final rawText = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final json = jsonDecode(rawText) as Map<String, dynamic>;
        final actions = AtlasAction.parseAll(json);
        final explanation = json['spiegazione'] as String?
            ?? json['explanation'] as String?;

        return AtlasResponse(
          actions: actions,
          explanation: explanation,
          rawJson: json,
        );
      }
    } catch (e) {
      print('❌ Errore Atlas ($name): $e');
    }

    return const AtlasResponse.empty();
  }

  @override
  Stream<String> askAtlasStream(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async* {
    if (!_initialized || _streamModel == null) {
      throw StateError('Atlas not initialized. Call initialize() first.');
    }

    // Build a simple payload (no JSON wrapping needed for streaming)
    final payload = '$userPrompt\n\nCONTEXT: ${canvasContext.isNotEmpty ? canvasContext.first['contenuto'] ?? '' : ''}';

    try {
      final responses = _streamModel!.generateContentStream(
        [Content.text(payload)],
      );
      await for (final response in responses) {
        if (response.text != null && response.text!.isNotEmpty) {
          yield response.text!;
        }
      }
    } catch (e) {
      print('❌ Atlas streaming error ($name): $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _model = null;
    _streamModel = null;
    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // System prompt
  // ---------------------------------------------------------------------------

  static const String _systemPrompt = '''
Sei Atlas, assistente AI di un Canvas. Esegui il comando dell'utente sui nodi selezionati. Rispondi SOLO con JSON.

## FORMATO OUTPUT
{"spiegazione": "...", "azioni": [...]}

## AZIONI
- crea_nodo: {"tipo": "crea_nodo", "contenuto": "...", "x": N, "y": N, "colore": "neon_cyan"}
- sposta_nodo: {"tipo": "sposta_nodo", "nodo_id": "ID_ESISTENTE", "x": N, "y": N}
- raggruppa: {"tipo": "raggruppa", "nodi": ["ID1", "ID2"]}

## POSIZIONAMENTO
Nuovi nodi: x = centro_x, y = y_max + 80 (poi +160, +240...). Mai sovrapporre.

## ESEMPI

Comando: "converti la scrittura a mano in testo digitale"
Nodi: [scrittura "CIAO", scrittura "COME STAI"]
✅ CORRETTO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "CIAO COME STAI", "x": 400, "y": 600, "colore": "neon_cyan"}]}
❌ SBAGLIATO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "Analisi della comunicazione testuale...", ...}]}

Comando: "rispondi al contenuto"
Nodi: [scrittura "CIAO"]
✅ CORRETTO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "Ciao! Come posso aiutarti?", "x": 400, "y": 600, "colore": "neon_green"}]}
❌ SBAGLIATO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "Creare un sistema di messaggistica...", ...}]}

Comando: "organizza in mappa"
✅ CORRETTO: sposta_nodo per riordinare i nodi in griglia
❌ SBAGLIATO: crea_nodo con descrizioni dei nodi

## REGOLE
1. Per "converti": COPIA il testo esatto, non riformularlo.
2. Per "rispondi": rispondi come un umano, max 1 frase.
3. Per "organizza/allinea": usa sposta_nodo, NON creare nodi nuovi.
4. MAI creare nodi che DESCRIVONO i nodi ("I nodi contengono...", "Analisi...", "Trasformazione...").
5. ID: usa SOLO gli id dal campo "id" dei nodi_nel_contesto.
6. Max 1-2 azioni. Colori: neon_cyan, neon_green, neon_orange, neon_purple.
''';
}

