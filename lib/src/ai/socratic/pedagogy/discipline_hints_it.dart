// 🇮🇹 Socratic V3.4 — IT discipline hint modules (production_native).
//
// Moduli piccoli (~200-400 chars ciascuno) iniettati come blocco
// "DISCIPLINA:" nel per-call payload (NON nel system prompt). Adatta i
// verbi alla maniera in cui i professori italiani di quella disciplina
// interrogano davvero gli studenti.
//
// Riferimenti: tradotto/adattato dalla sezione "DISCIPLINE-AWARE STEMS"
// del prompt monolitico V3.1 (atlas_ai_service.dart legacy).

import '../../../canvas/ai/socratic/socratic_model.dart' show Discipline;

/// Restituisce il blocco "DISCIPLINA: ..." da iniettare nel payload
/// per la disciplina e lingua IT. Mantenere breve (≤ 400 chars).
String disciplineHintsIt(Discipline d) => switch (d) {
      Discipline.physics => _physicsIt,
      Discipline.math => _mathIt,
      Discipline.chemistry => _chemistryIt,
      Discipline.biology => _biologyIt,
      Discipline.medicine => _medicineIt,
      Discipline.law => _lawIt,
      Discipline.economics => _economicsIt,
      Discipline.philosophy => _philosophyIt,
      Discipline.history => _historyIt,
      Discipline.generic => _genericIt,
    };

const String _physicsIt = '''
DISCIPLINA: fisica.
Verbi tipici dei professori italiani: prevedi, disegna le forze su…,
ragiona per casi limite, traccia il diagramma v-t, applica il bilancio.
Esempi concreti che funzionano: piano inclinato, pendolo semplice,
urti elastici/anelastici, sistemi inerziali e non-inerziali, oscillatori.
Evita "definisci". Preferisci scenari con valori numerici o setup fisico.
''';

const String _mathIt = '''
DISCIPLINA: matematica.
Verbi tipici: dimostra che, trova un controesempio a, mostra l'equivalenza,
spiega perché TEOREMA vale. Esempi concreti: dominio di una funzione,
limite notevole, integrale per sostituzione, induzione. Evita "calcola"
come unico verbo — la matematica è prova, non aritmetica. Premia rigorousness.
''';

const String _chemistryIt = '''
DISCIPLINA: chimica.
Verbi tipici: spiega il meccanismo molecolare, bilancia e motiva,
ragiona ai diversi livelli (molecolare, macroscopico). Esempi: reazione
spontanea/non-spontanea, equilibrio di Le Chatelier, ossidoriduzioni,
acidi-basi di Brønsted. Cerca SEMPRE la causalità molecolare, non il
"perché succede" superficiale.
''';

const String _biologyIt = '''
DISCIPLINA: biologia.
Verbi tipici: spiega il meccanismo a livello molecolare/cellulare/organismo,
perché TRATTO è stato selezionato, quale meccanismo regola
l'omeostasi di X. Esempi: trasporto attivo/passivo, regolazione genica,
selezione naturale, omeostasi glicemica. Evita "elenca" — la biologia
italiana premia il meccanismo, non la tassonomia.
''';

const String _medicineIt = '''
DISCIPLINA: medicina.
Verbi tipici: paziente di X anni con SINTOMO, cosa fai e perché? Cosa
NON ti aspetti di trovare? Cosa ti farebbe cambiare diagnosi? Esempi:
case-based reasoning con illness scripts, anamnesi, esame obiettivo
mirato, diagnosi differenziale. Forward + backward reasoning. Mai
"definisci la malattia X" — sempre paziente concreto.
''';

const String _lawIt = '''
DISCIPLINA: diritto.
Verbi tipici: e se i fatti fossero VARIAZIONE? Quali issue giuridiche
emergono? Su quale autorità si fonda questa conclusione: norma,
giurisprudenza, dottrina? Esempi: ipotesi di reato con variazioni
fattuali, conflitti normativi, interpretazione costituzionale. Mai
chiedere la definizione articolo per articolo — sempre fact pattern.
''';

const String _economicsIt = '''
DISCIPLINA: economia.
Verbi tipici: quale modello applichi e perché? Caso reale (es. crisi
del 2008, COVID, stimolo fiscale): mappalo sul modello. Come distingui
uno shock di domanda da uno di offerta in SCENARIO? Esempi: equilibrio
mercato, externalities, politica monetaria, asimmetrie informative.
Premia model selection + transfer al mondo reale.
''';

const String _philosophyIt = '''
DISCIPLINA: filosofia.
Verbi tipici: cosa intendi esattamente con TERMINE? Riformula POSIZIONE
come premesse + conclusione. Cosa fonda quella premessa? (continua il
regresso). Esempi: ontologia del dovere, problema dell'induzione,
fondamento dell'etica normativa. La domanda filosofica italiana mira
alla disambiguazione concettuale, non al riassunto storico.
''';

const String _historyIt = '''
DISCIPLINA: storia.
Verbi tipici: confronta cause prossime vs strutturali di EVENTO. Chi
ha scritto questa fonte, quando, con quale interesse? In che misura
X ha causato Y? Esempi: unità d'Italia, prima guerra mondiale,
trasformazioni economiche del Trecento, fonti documentarie vs
narrative. Premia analisi multi-causale + critica della fonte.
''';

const String _genericIt = '''
DISCIPLINA: generica (interdisciplinare o segnale ambiguo).
Usa verbi neutri di Bloom (analizza, valuta, costruisci). Evita verbi
discipline-specific che potrebbero suonare fuori contesto. Niente
iniezione misconception (le misconception sono discipline-specific).
Esempi neutri: collegamento concettuale, esempio applicativo, riflessione
critica.
''';
