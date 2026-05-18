// ============================================================================
// 🧹 CLEAN-OCR PROMPT — Multilang bootstrap (Bundle A, 2026-05-17)
//
// 16 prompt cells (Tier 1+2: en, it, es, pt, fr, de, ja, ko, hi, ar, zh,
// ru, nl, sv, pl, tr) for cleaning up MyScript handwriting OCR output
// before it feeds the cluster title / concept pipeline. Each cell is a
// language-specific template with examples of OCR errors typical of
// the language's script and morphology.
//
// Validation status:
//   - IT, EN: production-native (developer-written, curated against real
//     handwriting errors observed on Xiaomi 2026-05)
//   - 14 others (Phase 2, 2026-05-17): written natively with examples
//     of script-specific OCR errors typical of each language. Status
//     remains `aiBootstrap` until a human native speaker reviews each
//     cell post-ship (memory: `feedback_socratic_all_16_langs_goal`).
//
// Each cell MUST contain the placeholder `{input}` which the registry
// replaces with the trimmed MyScript OCR text at call time.
// ============================================================================

import 'super_node_theme_bootstrap.dart' show BackgroundAiValidationStatus;

/// Per-language validation status for the cleanOcr bootstrap cells.
/// Mirrors the pattern in `super_node_theme_bootstrap.dart`.
const Map<String, BackgroundAiValidationStatus> cleanOcrValidationStatus = {
  'en': BackgroundAiValidationStatus.productionNative,
  'it': BackgroundAiValidationStatus.productionNative,
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

/// 16 cleanOcr cells. Each value contains the `{input}` placeholder
/// replaced by the trimmed MyScript text at runtime.
const Map<String, String> _bootstrapCleanOcrCells = {
  // ─────────────────────────────────────────────────────────────────────
  // 🇮🇹 IT — production-native (curated from real handwriting OCR errors)
  // ─────────────────────────────────────────────────────────────────────
  'it': '''Pulisci questa trascrizione OCR di scrittura a mano in italiano. Correggi SOLO errori OCR ovvi:
1. Lettere confuse: d/e, m/n, l/i, rn/m, p/t (es. "Riposo" ≠ "Rito"), c/e
2. **FUSIONI con particelle/preposizioni — molto comuni in italiano**:
   - "LEGGITI NEWTON" → "LEGGI DI NEWTON"
   - "ASCAUSA" → "A CAUSA"
   - "PRIMOPRINCIPIO" → "PRIMO PRINCIPIO"
   - "DELLO/DELLA/DEGLI" attaccato → separa quando sensato
3. Parole frammentate: "FISI CA" → "FISICA", "Primalele" → "prima legge"
4. Maiuscole rotte: "SECUNDA" → "SECONDA", "TERMODINA MICA" → "TERMODINAMICA"
5. Refusi ovvi su parole italiane comuni del lessico scientifico/accademico
6. Frammenti OCR che assomigliano vagamente a notazione matematica MA sono in un contesto di parole italiane → ricostruisci la parola:
   - "Corpo a R' to" → "Corpo a Riposo" (NON "R^{2}", NON "R²")
   - "Sper. mento" → "Esperimento" (NON una variabile)
   - "f orza" o "f. orza" → "forza" (NON la funzione f)

**REGOLA CRITICA — anti-LaTeX hallucination:**
NON convertire MAI testo italiano ambiguo in formule LaTeX/Unicode (R^{2}, x_t, β', etc.) a meno che il contesto circostante sia CHIARAMENTE matematico (numeri, segni =, operatori, simboli greci già presenti). In dubbio, ricostruisci la PAROLA italiana o lascia inalterato — MAI inventare una formula.

PRESERVA formule SOLO quando già evidenti come tali: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG. Una sequenza tipo "R' to" in mezzo a "Corpo a … prima legge Newton" NON è una formula, è OCR rotto di "Riposo".

NON cambiare il significato. NON aggiungere parole nuove. NON commentare. NON tradurre. Se il testo è già corretto, rispondi identico. Output: SOLO il testo pulito.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇬🇧 EN — production-native
  // ─────────────────────────────────────────────────────────────────────
  'en': '''Clean up this handwriting OCR transcription in English. Fix ONLY obvious OCR errors:
1. Confused letters: d/e, m/n, l/i, rn/m, p/t, c/e
2. **FUSIONS with articles/prepositions — common when OCR drops spaces**:
   - "NEWTONSLAWS" → "NEWTON'S LAWS"
   - "BECAUSEOF" → "BECAUSE OF"
   - "FIRSTPRINCIPLE" → "FIRST PRINCIPLE"
3. Fragmented words: "PHYSI CS" → "PHYSICS", "Firstlaw" → "first law"
4. Broken capitalisation: "THERMO DYNAMICS" → "THERMODYNAMICS"
5. Common scientific/academic English vocabulary typos
6. OCR fragments that vaguely resemble mathematical notation but are in a context of English words → reconstruct the word:
   - "Body at R' st" → "Body at Rest" (NOT "R^{2}", NOT "R²")
   - "Exper. ment" → "Experiment" (NOT a variable)
   - "f orce" or "f. orce" → "force" (NOT the function f)

**CRITICAL RULE — anti-LaTeX hallucination:**
NEVER convert ambiguous English text into LaTeX/Unicode formulas (R^{2}, x_t, β', etc.) unless the surrounding context is CLEARLY mathematical (numbers, = signs, operators, Greek symbols already present). When in doubt, reconstruct the English WORD or leave unchanged — NEVER invent a formula.

PRESERVE formulas ONLY when they are clearly formulas: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG. A sequence like "R' st" in the middle of "Body at … Newton's first law" is NOT a formula, it's broken OCR of "Rest".

Do NOT change the meaning. Do NOT add new words. Do NOT comment. Do NOT translate. If the text is already correct, reply identically. Output: ONLY the cleaned text.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇪🇸 ES — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'es': '''Limpia esta transcripción OCR de escritura a mano en español. Corrige SOLO errores OCR obvios:
1. Letras confundidas: d/e, m/n, l/i, rn/m, c/e
2. **FUSIONES con artículos/preposiciones — comunes cuando el OCR elimina espacios**:
   - "LEYDENEWTON" → "LEY DE NEWTON"
   - "ELDEL" → "EL DEL"
   - "PORQUE" attaccato → separa cuando tenga sentido
3. Palabras fragmentadas: "FÍSI CA" → "FÍSICA", "Primeralei" → "primera ley"
4. Mayúsculas rotas: "TERMODI NÁMICA" → "TERMODINÁMICA"
5. Acentos perdidos en vocabulario científico/académico común
6. Fragmentos OCR que parecen notación matemática PERO están en un contexto de palabras españolas → reconstruye la palabra:
   - "Cuerpo en R' so" → "Cuerpo en Reposo" (NO "R^{2}", NO "R²")
   - "Exper. mento" → "Experimento" (NO una variable)
   - "f uerza" o "f. uerza" → "fuerza" (NO la función f)

**REGLA CRÍTICA — anti-LaTeX hallucination:**
NUNCA conviertas texto español ambiguo en fórmulas LaTeX/Unicode (R^{2}, x_t, β', etc.) a menos que el contexto circundante sea CLARAMENTE matemático (números, signos =, operadores, símbolos griegos ya presentes). En caso de duda, reconstruye la PALABRA española o deja inalterado — NUNCA inventes una fórmula.

PRESERVA fórmulas SOLO cuando son claramente fórmulas: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

NO cambies el significado. NO añadas palabras nuevas. NO comentes. NO traduzcas. Si el texto ya es correcto, responde idéntico. Salida: SOLO el texto limpio.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇵🇹 PT — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'pt': '''Limpe esta transcrição OCR de escrita à mão em português. Corrija APENAS erros OCR óbvios:
1. Letras confundidas: d/e, m/n, l/i, rn/m, c/e
2. **FUSÕES com artigos/preposições — comuns quando o OCR remove espaços**:
   - "LEIDENEWTON" → "LEI DE NEWTON"
   - "ODONEWTON" → "O DO NEWTON"
   - "PORQUE" attaccato → separe quando fizer sentido
3. Palavras fragmentadas: "FÍSI CA" → "FÍSICA", "Primeiralei" → "primeira lei"
4. Maiúsculas quebradas: "TERMODI NÂMICA" → "TERMODINÂMICA"
5. Acentos perdidos em vocabulário científico/acadêmico comum (PT-BR e PT-PT)
6. Fragmentos OCR que parecem notação matemática MAS estão em contexto de palavras portuguesas → reconstrua a palavra:
   - "Corpo em R' so" → "Corpo em Repouso" (NÃO "R^{2}", NÃO "R²")
   - "Exper. mento" → "Experimento" (NÃO uma variável)
   - "f orça" ou "f. orça" → "força" (NÃO a função f)

**REGRA CRÍTICA — anti-LaTeX hallucination:**
NUNCA converta texto português ambíguo em fórmulas LaTeX/Unicode (R^{2}, x_t, β', etc.) a menos que o contexto seja CLARAMENTE matemático (números, sinais =, operadores, símbolos gregos já presentes). Em caso de dúvida, reconstrua a PALAVRA portuguesa ou deixe inalterado — NUNCA invente uma fórmula.

PRESERVE fórmulas APENAS quando são claramente fórmulas: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

NÃO mude o significado. NÃO adicione palavras novas. NÃO comente. NÃO traduza. Se o texto já está correto, responda idêntico. Saída: APENAS o texto limpo.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇫🇷 FR — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'fr': '''Nettoie cette transcription OCR d'écriture à la main en français. Corrige UNIQUEMENT les erreurs OCR évidentes :
1. Lettres confondues : d/e, m/n, l/i, rn/m, c/e
2. **FUSIONS avec articles/élisions — fréquentes quand l'OCR supprime les espaces et apostrophes** :
   - "LOISDENEWTON" → "LOIS DE NEWTON"
   - "LDEL" → "L'DE L'" puis sépare correctement (apostrophes restaurées)
   - "PARCEQUE" → "PARCE QUE"
3. Mots fragmentés : "PHYSI QUE" → "PHYSIQUE", "Premièreloi" → "première loi"
4. Majuscules cassées : "THERMODY NAMIQUE" → "THERMODYNAMIQUE"
5. Accents perdus dans le vocabulaire scientifique/académique courant (é, è, à, ê, etc.)
6. Fragments OCR qui ressemblent vaguement à de la notation mathématique MAIS sont dans un contexte de mots français → reconstruis le mot :
   - "Corps au R' os" → "Corps au Repos" (PAS "R^{2}", PAS "R²")
   - "Expér. ence" → "Expérience" (PAS une variable)
   - "f orce" ou "f. orce" → "force" (PAS la fonction f)

**RÈGLE CRITIQUE — anti-LaTeX hallucination :**
Ne convertis JAMAIS du texte français ambigu en formules LaTeX/Unicode (R^{2}, x_t, β', etc.) sauf si le contexte est CLAIREMENT mathématique (nombres, signes =, opérateurs, symboles grecs déjà présents). En cas de doute, reconstruis le MOT français ou laisse inchangé — n'invente JAMAIS une formule.

PRÉSERVE les formules UNIQUEMENT quand elles sont clairement des formules : F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

NE change PAS le sens. N'ajoute PAS de nouveaux mots. NE commente PAS. NE traduis PAS. Si le texte est déjà correct, réponds identique. Sortie : UNIQUEMENT le texte nettoyé.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇩🇪 DE — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'de': '''Bereinige diese OCR-Transkription von Handschrift auf Deutsch. Korrigiere NUR offensichtliche OCR-Fehler:
1. Verwechselte Buchstaben: d/e, m/n, l/i, rn/m, c/e
2. **ZUSAMMENGESETZTE NOMEN — sehr häufig im Deutschen, OCR trennt sie oft falsch**:
   - "WÄRMELEHRE" korrekt (nicht "WÄRME LEHRE")
   - "GESCHWINDIG KEIT" → "GESCHWINDIGKEIT"
   - "NEWTONSCHE GE SETZE" → "NEWTONSCHE GESETZE"
3. Fragmentierte Wörter: "PHY SIK" → "PHYSIK", "Erstesgesetz" → "erstes Gesetz"
4. Gebrochene Großschreibung: "THERMODY NAMIK" → "THERMODYNAMIK"
5. Verlorene Umlaute (ä, ö, ü, ß) in wissenschaftlichem/akademischem Vokabular
6. OCR-Fragmente, die wie mathematische Notation aussehen, ABER in einem Kontext deutscher Wörter stehen → rekonstruiere das Wort:
   - "Körper in R' he" → "Körper in Ruhe" (NICHT "R^{2}", NICHT "R²")
   - "Exper. ment" → "Experiment" (NICHT eine Variable)
   - "K raft" oder "K. raft" → "Kraft" (NICHT die Funktion K)

**KRITISCHE REGEL — anti-LaTeX hallucination:**
Konvertiere NIEMALS mehrdeutigen deutschen Text in LaTeX/Unicode-Formeln (R^{2}, x_t, β', etc.), es sei denn, der umgebende Kontext ist KLAR mathematisch (Zahlen, =-Zeichen, Operatoren, griechische Symbole bereits vorhanden). Im Zweifelsfall rekonstruiere das deutsche WORT oder lasse es unverändert — erfinde NIEMALS eine Formel.

BEWAHRE Formeln NUR auf, wenn sie eindeutig Formeln sind: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

Ändere NICHT die Bedeutung. Füge KEINE neuen Wörter hinzu. Kommentiere NICHT. Übersetze NICHT. Wenn der Text bereits korrekt ist, antworte identisch. Ausgabe: NUR der bereinigte Text.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇯🇵 JA — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ja': '''この日本語の手書きOCR転写をクリーンアップしてください。明らかなOCRエラーのみを修正してください：
1. 混同された文字：
   - 漢字の誤認識（似た形の漢字）：「力」と「刀」、「日」と「目」、「土」と「士」など
   - ひらがな/カタカナの混同：「い」と「り」、「シ」と「ツ」、「ソ」と「ン」など
2. **助詞・送り仮名の誤分割 — 日本語OCRで非常に一般的**：
   - 「ニュートンノ法則」→「ニュートンの法則」（カタカナ「ノ」とひらがな「の」の誤認識）
   - 「第一法則は」を「第一法則|は」と切らない
3. 分断された単語：「物 理学」→「物理学」、「熱力 学」→「熱力学」
4. 漢字とかなの混同：科学/学術的な日本語の一般的な誤字
5. 数式に似たOCR断片が日本語の単語の文脈にある場合 → 単語を再構成：
   - 「物体は R' 止」→「物体は静止」（「R^{2}」ではない、「R²」ではない）
   - 「実 験」→「実験」（変数ではない）
   - 「f 力」または「f. 力」→「力」（関数fではない）

**重要なルール — anti-LaTeX hallucination：**
周囲の文脈が明らかに数学的（数字、=記号、演算子、ギリシャ文字がすでに存在）でない限り、曖昧な日本語テキストをLaTeX/Unicode数式（R^{2}, x_t, β'など）に変換しないでください。疑わしい場合は、日本語の単語を再構成するか、変更せずに残してください — 数式を発明しないでください。

数式が明らかに数式である場合のみ保持：F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG。

意味を変えないでください。新しい単語を追加しないでください。コメントしないでください。翻訳しないでください。テキストがすでに正しい場合は、そのまま返信してください。出力：クリーンアップされたテキストのみ。

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇰🇷 KO — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ko': '''이 한국어 손글씨 OCR 전사를 정리하세요. 명백한 OCR 오류만 수정하세요:
1. 혼동된 문자:
   - 자모 혼동: ㄱ/ㅋ, ㄷ/ㅌ, ㅂ/ㅍ, ㅏ/ㅑ, ㅓ/ㅕ 등
   - 받침 누락 또는 잘못된 받침
2. **조사 분리 오류 — 한국어 OCR에서 매우 일반적**:
   - "뉴턴의법칙" → "뉴턴의 법칙"
   - "물리학에서는" 같은 긴 어절을 잘못 분리하지 마세요
3. 분할된 단어: "물 리학" → "물리학", "열역 학" → "열역학"
4. 한자/한글 혼합 오류: 과학/학술 한국어의 일반적인 오타
5. 수학 표기법처럼 보이는 OCR 단편이 한국어 단어 문맥에 있을 때 → 단어를 재구성:
   - "물체가 R' 지" → "물체가 정지" ("R^{2}" 아님, "R²" 아님)
   - "실 험" → "실험" (변수 아님)
   - "f 힘" 또는 "f. 힘" → "힘" (함수 f 아님)

**중요 규칙 — anti-LaTeX hallucination:**
주변 문맥이 명확하게 수학적(숫자, = 기호, 연산자, 그리스 문자가 이미 존재)이 아닌 한, 모호한 한국어 텍스트를 LaTeX/Unicode 수식(R^{2}, x_t, β' 등)으로 변환하지 마세요. 의심스러울 때는 한국어 단어를 재구성하거나 변경하지 마세요 — 수식을 발명하지 마세요.

수식이 명확하게 수식일 때만 보존: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

의미를 바꾸지 마세요. 새로운 단어를 추가하지 마세요. 주석을 달지 마세요. 번역하지 마세요. 텍스트가 이미 올바르면 동일하게 답하세요. 출력: 정리된 텍스트만.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇮🇳 HI — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'hi': '''इस हिन्दी हस्तलिखित OCR प्रतिलेखन को साफ करें। केवल स्पष्ट OCR त्रुटियाँ ठीक करें:
1. भ्रमित अक्षर:
   - समान दिखने वाले अक्षर: ब/भ, द/ध, ट/ठ, र/त आदि
   - मात्रा भ्रम: ि/ी, ु/ू, े/ै, ो/ौ
2. **संधि और मात्रा त्रुटियाँ — हिन्दी OCR में बहुत आम**:
   - "न्यूटनकेनियम" → "न्यूटन के नियम"
   - "प्रथमनियम" → "प्रथम नियम"
   - संयुक्ताक्षर (ligatures) टूटे हुए: "क्ष" को "क + ष" न रखें
3. विभाजित शब्द: "भौ तिकी" → "भौतिकी", "ऊष्म गतिकी" → "ऊष्मागतिकी"
4. विसर्ग (ः), अनुस्वार (ं), चन्द्रबिंदु (ँ) खोए हुए — सामान्य वैज्ञानिक/शैक्षणिक शब्दावली में पुनर्स्थापित करें
5. गणितीय संकेतन जैसे दिखने वाले OCR टुकड़े हिन्दी शब्दों के संदर्भ में हों → शब्द का पुनर्निर्माण करें:
   - "वस्तु R' था" → "वस्तु विरामावस्था" ("R^{2}" नहीं, "R²" नहीं)
   - "प्रयो ग" → "प्रयोग" (चर नहीं)
   - "f बल" या "f. बल" → "बल" (फलन f नहीं)

**महत्वपूर्ण नियम — anti-LaTeX hallucination:**
जब तक आसपास का संदर्भ स्पष्ट रूप से गणितीय न हो (संख्याएँ, = चिह्न, ऑपरेटर, ग्रीक प्रतीक पहले से मौजूद), अस्पष्ट हिन्दी पाठ को LaTeX/Unicode सूत्रों (R^{2}, x_t, β' आदि) में कभी न बदलें। संदेह होने पर, हिन्दी शब्द का पुनर्निर्माण करें या अपरिवर्तित छोड़ें — सूत्र का आविष्कार कभी न करें।

सूत्रों को केवल तभी संरक्षित करें जब वे स्पष्ट रूप से सूत्र हों: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG।

अर्थ न बदलें। नए शब्द न जोड़ें। टिप्पणी न करें। अनुवाद न करें। यदि पाठ पहले से सही है, समान उत्तर दें। आउटपुट: केवल साफ किया गया पाठ।

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇸🇦 AR — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ar': '''نظّف هذه النسخة الـ OCR لخط اليد بالعربية. صحّح فقط أخطاء OCR الواضحة:
1. حروف مختلطة:
   - النقاط: ب/ت/ث، ج/ح/خ، د/ذ، ر/ز، س/ش، ص/ض، ط/ظ، ع/غ، ف/ق
   - أشكال متصلة/منفصلة: الأشكال الأولية، الوسطية، النهائية، المعزولة
   - الألف بأشكاله: ا، أ، إ، آ
2. **التشكيل والحركات الناقصة — الـ OCR غالبًا ما يحذفها**:
   - "قانون نيوتن الاول" → "قانون نيوتن الأول"
   - استعد الهمزات (ء، أ، إ، ؤ، ئ) عند الحاجة
3. كلمات مجزأة بسبب فواصل خاطئة: "الفي زياء" → "الفيزياء"
4. حروف كبيرة/متشكلة مكسورة في المفردات العلمية/الأكاديمية الشائعة
5. أجزاء OCR تبدو كرموز رياضية لكنها في سياق كلمات عربية → أعد بناء الكلمة:
   - "الجسم في R' كون" → "الجسم في سكون" (ليس "R^{2}"، ليس "R²")
   - "تجر بة" → "تجربة" (ليس متغيرًا)
   - "f قوة" أو "f. قوة" → "قوة" (ليست الدالة f)

**قاعدة حرجة — anti-LaTeX hallucination:**
لا تحوّل أبدًا نصًا عربيًا غامضًا إلى صيغ LaTeX/Unicode (R^{2}، x_t، β' وغيرها) إلا إذا كان السياق المحيط رياضيًا بوضوح (أرقام، علامات =، عوامل، رموز يونانية موجودة بالفعل). عند الشك، أعد بناء الكلمة العربية أو اتركها دون تغيير — لا تخترع صيغة أبدًا.

احفظ الصيغ فقط عندما تكون صيغًا واضحة: F=ma، E=mc²، ∫f(x)dx، H₂O، x²+y²، pH، ΔG.

لا تغيّر المعنى. لا تضف كلمات جديدة. لا تعلّق. لا تترجم. إذا كان النص صحيحًا بالفعل، أجب بنفسه. الإخراج: النص المُنظّف فقط.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇨🇳 ZH — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'zh': '''清理这份中文手写OCR转录。仅修正明显的OCR错误：
1. 混淆的字符：
   - 形似汉字：「力」与「刀」、「日」与「目」、「土」与「士」、「未」与「末」
   - 简繁混用（仅在用户写的字符确实错误时修正，不要主动转换）
2. **偏旁部首误识 — 中文手写OCR非常常见**：
   - 「物王里」→「物理」
   - 「热力孛」→「热力学」
3. 分割错误的词：「物 理」→「物理」、「热力 学」→「热力学」、「牛顿 定律」保持空格还是合并取决于上下文
4. 标点混淆：中文逗号「，」与英文逗号「,」、句号「。」与「.」等
5. 数学符号样式的OCR碎片在中文词语的上下文中 → 重建词语：
   - 「物体在R' 止」→「物体在静止」（不是「R^{2}」，不是「R²」）
   - 「实 验」→「实验」（不是变量）
   - 「f 力」或「f. 力」→「力」（不是函数f）

**关键规则 — anti-LaTeX hallucination：**
除非周围上下文明显是数学性的（已经存在数字、= 号、运算符、希腊符号），否则绝不要把模糊的中文文本转换成 LaTeX/Unicode 公式（R^{2}, x_t, β' 等）。有疑问时，重建中文词语或保持不变 — 绝不要发明公式。

仅当公式明显是公式时保留：F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG。

不要改变意思。不要添加新词。不要评论。不要翻译。如果文本已经正确，原样回复。输出：仅清理后的文本。

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇷🇺 RU — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'ru': '''Очисти эту OCR-транскрипцию рукописного текста на русском. Исправь ТОЛЬКО очевидные ошибки OCR:
1. Перепутанные буквы:
   - Похожие кириллические: и/й, ё/е, ц/щ, ш/щ, н/п, в/ь
   - Кириллические/латинские смешения: а/a, о/o, р/p, с/c, х/x (только когда ясно, что должна быть кириллица)
2. **ПОТЕРЯННЫЕ Ё, Ь, Ъ — очень распространены в OCR**:
   - "законыНьютона" → "законы Ньютона"
   - "ЭНЕРГИЯ" сохрани заглавные если они в оригинале
3. Фрагментированные слова: "ФИЗИ КА" → "ФИЗИКА", "Первыйзакон" → "Первый закон"
4. Сломанная капитализация: "ТЕРМОДИ НАМИКА" → "ТЕРМОДИНАМИКА"
5. Распространённые опечатки в научной/академической русской лексике
6. Фрагменты OCR, похожие на математическую запись, НО в контексте русских слов → восстанови слово:
   - "Тело в R' кое" → "Тело в Покое" (НЕ "R^{2}", НЕ "R²")
   - "Экспер. мент" → "Эксперимент" (НЕ переменная)
   - "f ила" или "f. ила" → "сила" (НЕ функция f)

**КРИТИЧЕСКОЕ ПРАВИЛО — anti-LaTeX hallucination:**
НИКОГДА не преобразуй неоднозначный русский текст в формулы LaTeX/Unicode (R^{2}, x_t, β' и т.д.), если окружающий контекст не ЯВНО математический (числа, знаки =, операторы, греческие символы уже присутствуют). При сомнении восстанови РУССКОЕ СЛОВО или оставь без изменений — НИКОГДА не выдумывай формулу.

СОХРАНЯЙ формулы ТОЛЬКО когда они явно являются формулами: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

НЕ меняй смысл. НЕ добавляй новых слов. НЕ комментируй. НЕ переводи. Если текст уже правильный, отвечай идентично. Вывод: ТОЛЬКО очищенный текст.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇳🇱 NL — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'nl': '''Maak deze OCR-transcriptie van handschrift in het Nederlands schoon. Corrigeer ALLEEN duidelijke OCR-fouten:
1. Verwarde letters: d/e, m/n, l/i, rn/m, c/e, ij/y
2. **SAMENGESTELDE WOORDEN — typisch Nederlands, OCR splitst ze vaak verkeerd**:
   - "WARMTELEER" correct (niet "WARMTE LEER")
   - "WET VAN NEWTON" niet samenvoegen tot "WETVANNEWTON"
   - "OMDAT" attaccato → scheid wanneer zinvol
3. Gefragmenteerde woorden: "FY SICA" → "FYSICA", "Eerstewet" → "eerste wet"
4. Hoofdletters kapot: "THERMODY NAMICA" → "THERMODYNAMICA"
5. Diakritische tekens (ë, ï, ö) verloren in wetenschappelijke/academische woordenschat
6. OCR-fragmenten die op wiskundige notatie lijken MAAR in een context van Nederlandse woorden staan → reconstrueer het woord:
   - "Lichaam in R' st" → "Lichaam in Rust" (NIET "R^{2}", NIET "R²")
   - "Exper. ment" → "Experiment" (NIET een variabele)
   - "k racht" of "k. racht" → "kracht" (NIET de functie k)

**KRITIEKE REGEL — anti-LaTeX hallucination:**
Zet NOOIT dubbelzinnige Nederlandse tekst om in LaTeX/Unicode-formules (R^{2}, x_t, β', enz.) tenzij de omringende context DUIDELIJK wiskundig is (getallen, =-tekens, operatoren, Griekse symbolen al aanwezig). Bij twijfel reconstrueer je het Nederlandse WOORD of laat je het ongewijzigd — verzin NOOIT een formule.

BEHOUD formules ALLEEN als ze duidelijk formules zijn: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

Verander de betekenis NIET. Voeg GEEN nieuwe woorden toe. Plaats GEEN commentaar. Vertaal NIET. Als de tekst al correct is, antwoord identiek. Uitvoer: ALLEEN de schoongemaakte tekst.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇸🇪 SV — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'sv': '''Rensa upp denna handskrifts-OCR-transkription på svenska. Korrigera ENDAST uppenbara OCR-fel:
1. Förväxlade bokstäver: d/e, m/n, l/i, rn/m, c/e, å/a, ä/a, ö/o
2. **SAMMANSATTA ORD — typiska för svenska, OCR delar dem ofta felaktigt**:
   - "VÄRMELÄRA" korrekt (inte "VÄRME LÄRA")
   - "NEWTONS LAGAR" inte slå samman till "NEWTONSLAGAR"
3. Fragmenterade ord: "FY SIK" → "FYSIK", "Förstalagen" → "första lagen"
4. Trasiga versaler: "TERMODY NAMIK" → "TERMODYNAMIK"
5. Förlorade å/ä/ö i vetenskaplig/akademisk vokabulär
6. OCR-fragment som ser ut som matematisk notation MEN är i ett sammanhang av svenska ord → rekonstruera ordet:
   - "Kropp i R' a" → "Kropp i Vila" (INTE "R^{2}", INTE "R²")
   - "Exper. ment" → "Experiment" (INTE en variabel)
   - "k raft" eller "k. raft" → "kraft" (INTE funktionen k)

**KRITISK REGEL — anti-LaTeX hallucination:**
Konvertera ALDRIG tvetydig svensk text till LaTeX/Unicode-formler (R^{2}, x_t, β', etc.) om inte den omgivande kontexten är TYDLIGT matematisk (siffror, =-tecken, operatorer, grekiska symboler redan närvarande). Vid tvivel rekonstruera det SVENSKA ORDET eller lämna oförändrat — uppfinn ALDRIG en formel.

BEVARA formler ENDAST när de tydligt är formler: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

Ändra INTE betydelsen. Lägg INTE till nya ord. Kommentera INTE. Översätt INTE. Om texten redan är korrekt, svara identiskt. Utdata: ENDAST den rensade texten.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇵🇱 PL — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'pl': '''Oczyść tę transkrypcję OCR pisma odręcznego w języku polskim. Popraw TYLKO oczywiste błędy OCR:
1. Mylone litery:
   - Polskie znaki: ą/a, ę/e, ć/c, ł/l, ń/n, ó/o, ś/s, ź/z, ż/z
   - Podobne litery: d/e, m/n, l/i, rn/m, c/e
2. **UTRATA OGONKÓW i KRESEK — bardzo częsta w OCR**:
   - "prawa Newtona" — przywróć polskie znaki diakrytyczne, gdzie potrzeba
   - "Pierwszezasada" → "Pierwsza zasada"
3. Fragmentowane słowa: "FI ZYKA" → "FIZYKA", "Pierwszezasada" → "Pierwsza zasada"
4. Zepsute wielkie litery: "TERMODY NAMIKA" → "TERMODYNAMIKA"
5. Częste literówki w polskim słownictwie naukowym/akademickim
6. Fragmenty OCR wyglądające jak notacja matematyczna, ALE w kontekście polskich słów → zrekonstruuj słowo:
   - "Ciało w R' ku" → "Ciało w Spoczynku" (NIE "R^{2}", NIE "R²")
   - "Eksp. ment" → "Eksperyment" (NIE zmienna)
   - "s iła" lub "s. iła" → "siła" (NIE funkcja s)

**KRYTYCZNA ZASADA — anti-LaTeX hallucination:**
NIGDY nie konwertuj niejednoznacznego polskiego tekstu na wzory LaTeX/Unicode (R^{2}, x_t, β', itp.), chyba że otaczający kontekst jest WYRAŹNIE matematyczny (liczby, znaki =, operatory, greckie symbole już obecne). W razie wątpliwości zrekonstruuj POLSKIE SŁOWO lub pozostaw bez zmian — NIGDY nie wymyślaj wzoru.

ZACHOWUJ wzory TYLKO gdy są wyraźnie wzorami: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

NIE zmieniaj znaczenia. NIE dodawaj nowych słów. NIE komentuj. NIE tłumacz. Jeśli tekst jest już poprawny, odpowiedz identycznie. Wyjście: TYLKO oczyszczony tekst.

Input: {input}
Output:''',

  // ─────────────────────────────────────────────────────────────────────
  // 🇹🇷 TR — ai-bootstrap (native content, pending review)
  // ─────────────────────────────────────────────────────────────────────
  'tr': '''Bu Türkçe el yazısı OCR transkripsiyonunu temizle. SADECE açık OCR hatalarını düzelt:
1. Karıştırılan harfler:
   - Türkçe karakterler: ı/i (noktasız/noktalı), ş/s, ç/c, ğ/g, ü/u, ö/o
   - Benzer harfler: d/e, m/n, l/i, rn/m, c/e
2. **EKLERİN AYRILMASI — Türkçe OCR'da çok yaygın (Türkçe sondan eklemeli)**:
   - "Newton'unkanunları" → "Newton'un kanunları"
   - "Birincikanun" → "Birinci kanun"
   - Kesme işaretini (') doğru yere geri koy
3. Parçalanmış kelimeler: "FİZ İK" → "FİZİK", "Termo dinamik" → "Termodinamik"
4. Bozulmuş büyük harfler: "TERMODİ NAMİK" → "TERMODİNAMİK"
5. Bilimsel/akademik Türkçede kaybolan ş, ç, ğ, ı, ü, ö karakterleri
6. Matematiksel gösterim gibi görünen OCR parçaları, ANCAK Türkçe kelimelerin bağlamında → kelimeyi yeniden oluştur:
   - "Cisim R' urgun" → "Cisim Durgun" ("R^{2}" değil, "R²" değil)
   - "Den. ney" → "Deney" (bir değişken değil)
   - "k uvvet" veya "k. uvvet" → "kuvvet" (k fonksiyonu değil)

**KRİTİK KURAL — anti-LaTeX hallucination:**
Çevredeki bağlam AÇIKÇA matematiksel olmadıkça (sayılar, = işaretleri, operatörler, Yunan sembolleri zaten mevcut), belirsiz Türkçe metni ASLA LaTeX/Unicode formüllerine (R^{2}, x_t, β' vb.) dönüştürme. Şüphe duyduğunda Türkçe KELİMEYİ yeniden oluştur veya değiştirme — ASLA bir formül uydurma.

Formülleri SADECE açıkça formül olduklarında koru: F=ma, E=mc², ∫f(x)dx, H₂O, x²+y², pH, ΔG.

Anlamı DEĞİŞTİRME. Yeni kelime EKLEME. Yorum YAPMA. ÇEVİRME. Metin zaten doğruysa, aynı şekilde yanıtla. Çıktı: SADECE temizlenmiş metin.

Input: {input}
Output:''',
};

/// Fetch the cleanOcr template for [langCode]. Returns `null` for
/// unsupported codes — callers fall back to the English cell.
String? bootstrapCleanOcrCellFor(String langCode) =>
    _bootstrapCleanOcrCells[langCode];

/// Returns the validation status of the cleanOcr cell for [langCode].
/// Defaults to [BackgroundAiValidationStatus.aiBootstrap] for unknown
/// codes (safe pessimistic default).
BackgroundAiValidationStatus cleanOcrStatusFor(String langCode) =>
    cleanOcrValidationStatus[langCode] ??
    BackgroundAiValidationStatus.aiBootstrap;
