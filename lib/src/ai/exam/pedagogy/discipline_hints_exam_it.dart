// 🇮🇹 Atlas Exam V3.4 ω — IT discipline hint modules (production_native).
//
// Moduli piccoli (~200-400 chars ciascuno) iniettati come blocco
// "DISCIPLINA:" nel per-call payload del phase `generation` (NON nel
// system prompt). Adatta i verbi Bloom alla maniera in cui i
// professori italiani di quella disciplina interrogano davvero in
// sede d'esame — distinto da come la stessa disciplina è usata in
// Socratic (dialogic, vedi discipline_hints_it.dart in
// lib/src/ai/socratic/pedagogy/).
//
// Esempio differenza Socratic vs Exam per fisica:
//   Socratic: "ragiona per casi limite, traccia il diagramma v-t"
//   Exam: "calcola la forza netta, deriva l'equazione del moto, valuta
//          la stabilità di un sistema"

import '../../../canvas/ai/socratic/socratic_discipline.dart';

/// Restituisce il blocco "DISCIPLINA: ..." per la disciplina e lingua IT.
/// Iniettato come addendum al payload V2 di [ExamPhase.generation].
/// ≤ 400 chars per preservare il budget output.
String disciplineHintsExamIt(Discipline d) => switch (d) {
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
Verbi Bloom-Apply: calcola (forza netta, momento, energia), predici
(traiettoria, posizione t+Δt), applica (Newton II, conservazione).
Verbi Bloom-Analyze: deriva (equazione del moto), distingui
(elastico/anelastico), confronta (sistemi inerziali vs non-inerziali).
Verbi Bloom-Evaluate: valuta la stabilità di un sistema, critica
un'ipotesi modello.
Scenari preferiti: piano inclinato con attrito, urti 1D/2D, oscillatore
armonico, circuiti RLC, termodinamica del ciclo di Carnot.
''';

const String _mathIt = '''
DISCIPLINA: matematica.
Verbi Bloom-Apply: risolvi (equazione, sistema), calcola (limite,
derivata, integrale per parti/sostituzione), applica (regola di
de l'Hôpital, teorema di Lagrange).
Verbi Bloom-Analyze: dimostra (per induzione, per assurdo, contropositivo),
trova un controesempio, mostra l'equivalenza, classifica le discontinuità.
Verbi Bloom-Evaluate: critica una dimostrazione, valuta la generalità
di un teorema.
Mai solo "calcola" come unico verbo — la matematica d'esame è prova.
''';

const String _chemistryIt = '''
DISCIPLINA: chimica.
Verbi Bloom-Apply: bilancia (reazione redox, neutralizzazione), calcola
(molarità, pH, concentrazione), predici (prodotto di reazione).
Verbi Bloom-Analyze: distingui (acido forte/debole, SN1/SN2), spiega
il meccanismo molecolare, classifica i composti per gruppo funzionale.
Verbi Bloom-Evaluate: valuta la spontaneità termodinamica (ΔG),
critica una via di sintesi.
Cerca SEMPRE la causalità molecolare e il livello di rappresentazione
(molecolare/macroscopico/simbolico).
''';

const String _biologyIt = '''
DISCIPLINA: biologia.
Verbi Bloom-Apply: applica (Hardy-Weinberg, leggi di Mendel), predici
(fenotipi F2, esito mutazione), calcola (frequenze alleliche).
Verbi Bloom-Analyze: distingui (mitosi/meiosi, procarioti/eucarioti),
spiega la funzione (organello, sistema), confronta (selezione
naturale vs deriva genetica).
Verbi Bloom-Evaluate: valuta l'evidenza di un'ipotesi evolutiva,
critica un modello sperimentale.
Esempi: ATP-sintasi, regolazione genica, omeostasi, ecosistemi.
''';

const String _medicineIt = '''
DISCIPLINA: medicina.
Verbi Bloom-Apply: diagnostica (sulla base di sintomi/segni), proponi
(terapia di prima linea), applica (criteri DSM, linee guida ESC).
Verbi Bloom-Analyze: distingui (diagnosi differenziale), interpreta
(esami di laboratorio, imaging), valuta la fisiopatologia sottostante.
Verbi Bloom-Evaluate: critica un trattamento, valuta la prognosi,
ragiona sull'evidenza (RCT vs case report).
Scenari clinici concreti con anamnesi + esami + prognosi attesa.
''';

const String _lawIt = '''
DISCIPLINA: diritto.
Verbi Bloom-Apply: applica (norma al caso concreto), qualifica
(fattispecie giuridica), individua (responsabilità).
Verbi Bloom-Analyze: distingui (dolo/colpa, contratto/atto unilaterale),
confronta (precedenti giurisprudenziali), argomenta dalla ratio legis.
Verbi Bloom-Evaluate: valuta la legittimità di un atto, critica
un'interpretazione giurisprudenziale.
Scenari preferiti: casi concreti con elementi di fattispecie chiari +
norme applicabili (codice civile, penale, costituzione).
''';

const String _economicsIt = '''
DISCIPLINA: economia.
Verbi Bloom-Apply: calcola (elasticità, PIL, surplus), applica
(modello di concorrenza perfetta, IS-LM), predici l'effetto di una
politica monetaria/fiscale.
Verbi Bloom-Analyze: distingui (effetto sostituzione vs reddito),
confronta (regimi di mercato), interpreta dati macroeconomici.
Verbi Bloom-Evaluate: valuta una politica economica, critica un
assunto di un modello (mobilità perfetta, razionalità).
Esempi con grafici domanda-offerta + dati numerici realistici.
''';

const String _philosophyIt = '''
DISCIPLINA: filosofia.
Verbi Bloom-Apply: applica (categoria kantiana a un caso, principio
utilitarista), classifica (filosofo per corrente, testo per scuola).
Verbi Bloom-Analyze: confronta (Platone vs Aristotele, Hume vs Kant),
distingui (etica deontologica vs consequenzialista), argomenta dalla
fonte.
Verbi Bloom-Evaluate: critica una tesi, valuta la coerenza interna
di un sistema, costruisci una controargomentazione.
Esempi: dilemma del trolley, paradosso del mentitore, problema mente-corpo.
''';

const String _historyIt = '''
DISCIPLINA: storia.
Verbi Bloom-Apply: data correttamente un evento, applica (categoria
periodizzante a un fatto), localizza (causa prossima vs causa remota).
Verbi Bloom-Analyze: distingui (cause economiche/politiche/sociali),
confronta (Rivoluzione francese vs americana), interpreta una fonte
primaria, individua bias.
Verbi Bloom-Evaluate: valuta l'impatto di un evento, critica una tesi
storiografica, argomenta dall'evidenza documentale.
Evita date sterili: chiedi PERCHÉ + COME, non solo QUANDO.
''';

const String _genericIt = '''
DISCIPLINA: generica.
Verbi Bloom-Apply: applica, calcola, predici, classifica.
Verbi Bloom-Analyze: distingui, confronta, interpreta, deriva.
Verbi Bloom-Evaluate: valuta, critica, argomenta, giustifica.
Senza dominio specifico, privilegia domande che richiedano ragionamento
multi-step e che siano risolvibili dagli appunti del cluster.
Evita domande generiche tipo "Cos'è X?" (Remember-only).
''';
