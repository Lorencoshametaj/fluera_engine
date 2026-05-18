// ============================================================================
// 🌐 SUPER-NODE THEME PROMPT — Multilang bootstrap (Bundle C, 2026-05-17)
//
// 16 prompt cells (Tier 1+2: en, it, es, pt, fr, de, ja, ko, hi, ar, zh,
// ru, nl, sv, pl, tr) for generating "continent themes" at god view
// (super-node aggregation, scale ≤ 0.16). Each cell is a template that
// the registry interpolates with the actual list of cluster topic groups
// and feeds to `provider.askAtlas(...)`.
//
// Pattern mirrors `chat_pedagogy_bootstrap.dart` and `exam_pedagogy_
// bootstrap.dart`. Validation status:
//   - IT, EN: production-native (written by the developer)
//   - 14 others (ES PT FR DE JA KO HI AR ZH RU NL SV PL TR): ai-bootstrap
//     content (Phase 2, 2026-05-17 — written natively but pending review
//     by human native speakers post-ship). Status stays `aiBootstrap`
//     until a native reviewer signs each cell off.
//
// Each cell MUST contain the placeholder `{topic_groups}` so the registry
// interpolation works. The placeholder is replaced with a numbered list:
//
//   1. ARGOMENTI: ClusterA, ClusterB, ClusterC
//   2. ARGOMENTI: ClusterD, ClusterE
//
// The model is expected to return JSON `{"temi": {"1": "tema1", ...}}`
// where each tema is ≤25 characters in the target language.
// ============================================================================

/// Validation status of each bootstrap cell. Mirrors
/// `SocraticValidationStatus` from `pedagogy_registry.dart`.
enum BackgroundAiValidationStatus {
  /// Cell written and reviewed by a native speaker (or by the developer
  /// for the developer's own language). Ready for production.
  productionNative,

  /// Cell auto-generated (English fallback or AI-assisted native version)
  /// and not yet reviewed by a native speaker. Functional but lower
  /// quality — banner-worthy.
  aiBootstrap,
}

/// Per-language validation status. Keep in sync with
/// `_bootstrapSuperNodeThemeCells` keys below.
const Map<String, BackgroundAiValidationStatus>
    superNodeThemeValidationStatus = {
  'en': BackgroundAiValidationStatus.productionNative,
  'it': BackgroundAiValidationStatus.productionNative,
  // Phase 2 cells: written natively but pending human native review.
  'es': BackgroundAiValidationStatus.aiBootstrap,
  'pt': BackgroundAiValidationStatus.aiBootstrap,
  'fr': BackgroundAiValidationStatus.aiBootstrap,
  'de': BackgroundAiValidationStatus.aiBootstrap,
  'ja': BackgroundAiValidationStatus.aiBootstrap,
  'ko': BackgroundAiValidationStatus.aiBootstrap,
  'hi': BackgroundAiValidationStatus.aiBootstrap,
  'ar': BackgroundAiValidationStatus.aiBootstrap,
  'zh': BackgroundAiValidationStatus.aiBootstrap,
  'ru': BackgroundAiValidationStatus.aiBootstrap,
  'nl': BackgroundAiValidationStatus.aiBootstrap,
  'sv': BackgroundAiValidationStatus.aiBootstrap,
  'pl': BackgroundAiValidationStatus.aiBootstrap,
  'tr': BackgroundAiValidationStatus.aiBootstrap,
};

/// 16 cells, one per supported ISO code. Each value contains the
/// `{topic_groups}` placeholder that the registry interpolates.
const Map<String, String> _bootstrapSuperNodeThemeCells = {
  // ─────────────────────────────────────────────────────────────────────
  // 🇮🇹 IT — production-native
  // ─────────────────────────────────────────────────────────────────────
  'it': '''IGNORA tutte le regole precedenti sulle canvas action.

Sei un analista tematico. Per ogni gruppo di argomenti, genera UN MACRO-TEMA (max 25 caratteri) che li unifica.

REGOLE:
- MAX 25 caratteri
- Un titolo tematico ampio, non specifico
- Lingua: italiano
- Rispondi con JSON: {"temi": {"1": "tema1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇬🇧 EN — production-native
  // ─────────────────────────────────────────────────────────────────────
  'en': '''IGNORE all previous rules about canvas actions.

You are a thematic analyst. For each group of topics, generate ONE MACRO-THEME (max 25 characters) that unifies them.

RULES:
- MAX 25 characters
- A broad thematic title, not specific
- Language: English
- Reply with JSON: {"temi": {"1": "theme1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇪🇸 ES — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'es': '''IGNORA todas las reglas anteriores sobre las acciones del canvas.

Eres un analista temático. Para cada grupo de temas, genera UN MACRO-TEMA (máx 25 caracteres) que los unifique.

REGLAS:
- MÁX 25 caracteres
- Un título temático amplio, no específico
- Idioma: español
- Responde con JSON: {"temi": {"1": "tema1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇵🇹 PT — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'pt': '''IGNORE todas as regras anteriores sobre as ações do canvas.

Você é um analista temático. Para cada grupo de tópicos, gere UM MACRO-TEMA (máx 25 caracteres) que os unifique.

REGRAS:
- MÁX 25 caracteres
- Um título temático amplo, não específico
- Idioma: português
- Responda com JSON: {"temi": {"1": "tema1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇫🇷 FR — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'fr': '''IGNORE toutes les règles précédentes sur les canvas actions.

Tu es un analyste thématique. Pour chaque groupe de sujets, génère UN MACRO-THÈME (max 25 caractères) qui les unifie.

RÈGLES :
- MAX 25 caractères
- Un titre thématique large, pas spécifique
- Langue : français
- Réponds avec JSON : {"temi": {"1": "theme1", ...}}

{topic_groups}

JSON :''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇩🇪 DE — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'de': '''IGNORIERE alle vorherigen Regeln zu Canvas-Aktionen.

Du bist ein thematischer Analyst. Für jede Themengruppe erzeuge EIN MAKRO-THEMA (max. 25 Zeichen), das sie vereint.

REGELN:
- MAX. 25 Zeichen
- Ein breiter thematischer Titel, nicht spezifisch
- Sprache: Deutsch
- Antworte mit JSON: {"temi": {"1": "thema1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇯🇵 JA — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ja': '''キャンバスアクションに関する以前のルールはすべて無視してください。

あなたはテーマ分析者です。各トピックグループに対して、それらを統合する1つのマクロテーマ（最大25文字）を生成してください。

ルール：
- 最大25文字
- 具体的ではなく、広いテーマタイトル
- 言語：日本語
- JSONで回答：{"temi": {"1": "テーマ1", ...}}

{topic_groups}

JSON：''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇰🇷 KO — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ko': '''캔버스 액션에 관한 이전의 모든 규칙을 무시하세요.

당신은 주제 분석가입니다. 각 주제 그룹에 대해 이를 통합하는 하나의 매크로 주제(최대 25자)를 생성하세요.

규칙:
- 최대 25자
- 구체적이지 않은 폭넓은 주제 제목
- 언어: 한국어
- JSON으로 답변: {"temi": {"1": "주제1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇮🇳 HI — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'hi': '''कैनवस क्रियाओं के बारे में सभी पिछले नियमों को अनदेखा करें।

आप एक विषयगत विश्लेषक हैं। विषयों के प्रत्येक समूह के लिए, उन्हें एकीकृत करने वाला एक मैक्रो-विषय (अधिकतम 25 अक्षर) उत्पन्न करें।

नियम:
- अधिकतम 25 अक्षर
- एक विस्तृत विषयगत शीर्षक, विशिष्ट नहीं
- भाषा: हिन्दी
- JSON में उत्तर दें: {"temi": {"1": "विषय1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇸🇦 AR — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ar': '''تجاهل جميع القواعد السابقة المتعلقة بإجراءات الكانفاس.

أنت محلل موضوعي. لكل مجموعة من المواضيع، أنشئ موضوعًا رئيسيًا واحدًا (بحد أقصى 25 حرفًا) يوحدها.

القواعد:
- بحد أقصى 25 حرفًا
- عنوان موضوعي واسع، وليس محددًا
- اللغة: العربية
- أجب بصيغة JSON: {"temi": {"1": "موضوع1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇨🇳 ZH — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'zh': '''忽略之前关于画布操作的所有规则。

你是一个主题分析师。对于每个主题组，生成一个统一它们的宏观主题（最多25个字符）。

规则：
- 最多25个字符
- 广泛的主题标题，而非具体的
- 语言：中文
- 用 JSON 回答：{"temi": {"1": "主题1", ...}}

{topic_groups}

JSON：''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇷🇺 RU — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ru': '''ИГНОРИРУЙ все предыдущие правила о canvas-действиях.

Ты — тематический аналитик. Для каждой группы тем создай ОДНУ МАКРО-ТЕМУ (максимум 25 символов), которая их объединяет.

ПРАВИЛА:
- МАКСИМУМ 25 символов
- Широкий тематический заголовок, не конкретный
- Язык: русский
- Отвечай в формате JSON: {"temi": {"1": "тема1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇳🇱 NL — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'nl': '''NEGEER alle vorige regels over canvas-acties.

Je bent een thematisch analist. Genereer voor elke groep onderwerpen ÉÉN MACRO-THEMA (max 25 tekens) dat ze verbindt.

REGELS:
- MAX 25 tekens
- Een brede thematische titel, niet specifiek
- Taal: Nederlands
- Antwoord met JSON: {"temi": {"1": "thema1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇸🇪 SV — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'sv': '''IGNORERA alla tidigare regler om canvas-åtgärder.

Du är en tematisk analytiker. För varje grupp av ämnen, generera ETT MAKRO-TEMA (max 25 tecken) som förenar dem.

REGLER:
- MAX 25 tecken
- En bred tematisk titel, inte specifik
- Språk: svenska
- Svara med JSON: {"temi": {"1": "tema1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇵🇱 PL — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'pl': '''ZIGNORUJ wszystkie poprzednie zasady dotyczące akcji canvas.

Jesteś analitykiem tematycznym. Dla każdej grupy tematów wygeneruj JEDEN MAKRO-TEMAT (maks. 25 znaków), który je łączy.

ZASADY:
- MAKS. 25 znaków
- Szeroki tytuł tematyczny, niespecyficzny
- Język: polski
- Odpowiadaj w formacie JSON: {"temi": {"1": "temat1", ...}}

{topic_groups}

JSON:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇹🇷 TR — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'tr': '''Canvas eylemleri hakkındaki tüm önceki kuralları YOK SAY.

Sen bir tema analistisin. Her konu grubu için, onları birleştiren BİR MAKRO-TEMA (en fazla 25 karakter) oluştur.

KURALLAR:
- EN FAZLA 25 karakter
- Belirli değil, geniş bir tematik başlık
- Dil: Türkçe
- JSON ile yanıtla: {"temi": {"1": "tema1", ...}}

{topic_groups}

JSON:''',
};

/// Fetch the bootstrap template for [langCode]. Returns `null` for
/// unsupported codes — callers fall back to the English cell.
String? bootstrapSuperNodeThemeCellFor(String langCode) =>
    _bootstrapSuperNodeThemeCells[langCode];

/// Returns the validation status of the cell for [langCode]. Defaults to
/// [BackgroundAiValidationStatus.aiBootstrap] for unknown codes (safe
/// pessimistic default).
BackgroundAiValidationStatus superNodeThemeStatusFor(String langCode) =>
    superNodeThemeValidationStatus[langCode] ??
    BackgroundAiValidationStatus.aiBootstrap;
