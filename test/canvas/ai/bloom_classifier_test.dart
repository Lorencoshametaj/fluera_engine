import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/bloom_classifier.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_model.dart';

ExamQuestion _q(String text) => ExamQuestion(
      id: 't',
      questionText: text,
      type: ExamQuestionType.openEnded,
      correctAnswer: '',
      explanation: '',
      sourceClusterId: 'c',
      sourceText: '',
    );

void main() {
  group('BloomClassifier — Italian', () {
    test('Remember: definisci', () {
      expect(BloomClassifier.classify('Definisci la legge di Ohm.'),
          BloomLevel.remember);
    });
    test('Remember: cos\'è (interrogative)', () {
      expect(BloomClassifier.classify('Cos\'è la mitosi?'),
          BloomLevel.remember);
    });
    test('Remember: elenca', () {
      expect(BloomClassifier.classify('Elenca i pianeti del sistema solare.'),
          BloomLevel.remember);
    });
    test('Remember: quale + quando', () {
      expect(BloomClassifier.classify('Quale anno è iniziata la Seconda Guerra Mondiale?'),
          BloomLevel.remember);
    });

    test('Understand: spiega', () {
      expect(BloomClassifier.classify('Spiega come funziona la pompa sodio-potassio.'),
          BloomLevel.understand);
    });
    test('Understand: descrivi', () {
      expect(BloomClassifier.classify('Descrivi il ciclo di Krebs.'),
          BloomLevel.understand);
    });
    test('Understand: riassumi', () {
      expect(BloomClassifier.classify('Riassumi le tre leggi di Newton.'),
          BloomLevel.understand);
    });
    test('Understand: perché', () {
      expect(BloomClassifier.classify('Perché il cielo appare azzurro?'),
          BloomLevel.understand);
    });

    test('Apply: calcola', () {
      expect(BloomClassifier.classify('Calcola la forza netta su un oggetto di 5 kg con accelerazione 3 m/s^2.'),
          BloomLevel.apply);
    });
    test('Apply: applica', () {
      expect(BloomClassifier.classify('Applica la legge di Coulomb a due cariche di 1 µC distanti 10 cm.'),
          BloomLevel.apply);
    });
    test('Apply: risolvi', () {
      expect(BloomClassifier.classify('Risolvi l\'equazione 2x + 5 = 13.'),
          BloomLevel.apply);
    });
    test('Apply: dato (data + premise)', () {
      expect(BloomClassifier.classify('Dato un triangolo con base 6 e altezza 4, determina l\'area.'),
          BloomLevel.apply);
    });

    test('Analyze: confronta', () {
      expect(BloomClassifier.classify('Confronta meiosi e mitosi.'),
          BloomLevel.analyze);
    });
    test('Analyze: analizza', () {
      expect(BloomClassifier.classify('Analizza le cause della rivoluzione francese.'),
          BloomLevel.analyze);
    });
    test('Analyze: distingui', () {
      expect(BloomClassifier.classify('Distingui tra mitocondri e cloroplasti.'),
          BloomLevel.analyze);
    });
    test('Analyze: in che modo', () {
      expect(BloomClassifier.classify('In che modo la temperatura influenza la velocità di reazione?'),
          BloomLevel.analyze);
    });

    test('Evaluate: valuta', () {
      expect(BloomClassifier.classify('Valuta l\'efficacia del modello atomico di Bohr.'),
          BloomLevel.evaluate);
    });
    test('Evaluate: giustifica', () {
      expect(BloomClassifier.classify('Giustifica l\'uso del PIL come misura del benessere.'),
          BloomLevel.evaluate);
    });
    test('Evaluate: pro e contro', () {
      expect(BloomClassifier.classify('Discuti i pro e contro dell\'energia nucleare.'),
          BloomLevel.evaluate);
    });

    test('Create: progetta', () {
      expect(BloomClassifier.classify('Progetta un esperimento per misurare la velocità della luce.'),
          BloomLevel.create);
    });
    test('Create: proponi', () {
      expect(BloomClassifier.classify('Proponi una soluzione al problema dell\'inquinamento plastico.'),
          BloomLevel.create);
    });
    test('Create: formula un\'ipotesi', () {
      expect(BloomClassifier.classify('Formula un\'ipotesi sul comportamento dei buchi neri.'),
          BloomLevel.create);
    });
  });

  group('BloomClassifier — English', () {
    test('Remember: define', () {
      expect(BloomClassifier.classify('Define photosynthesis.'),
          BloomLevel.remember);
    });
    test('Remember: list', () {
      expect(BloomClassifier.classify('List the noble gases.'),
          BloomLevel.remember);
    });
    test('Remember: what is', () {
      expect(BloomClassifier.classify('What is the speed of light?'),
          BloomLevel.remember);
    });

    test('Understand: explain', () {
      expect(BloomClassifier.classify('Explain how vaccines work.'),
          BloomLevel.understand);
    });
    test('Understand: why', () {
      expect(BloomClassifier.classify('Why does ice float on water?'),
          BloomLevel.understand);
    });

    test('Apply: calculate', () {
      expect(BloomClassifier.classify('Calculate the area of a circle with radius 4.'),
          BloomLevel.apply);
    });
    test('Apply: solve', () {
      expect(BloomClassifier.classify('Solve for x: 3x - 7 = 14.'),
          BloomLevel.apply);
    });
    test('Apply: given', () {
      expect(BloomClassifier.classify('Given a 10 kg box on a 30° incline, determine the friction force.'),
          BloomLevel.apply);
    });

    test('Analyze: compare', () {
      expect(BloomClassifier.classify('Compare DNA replication in prokaryotes and eukaryotes.'),
          BloomLevel.analyze);
    });
    test('Analyze: how does', () {
      expect(BloomClassifier.classify('How does temperature affect enzyme activity?'),
          BloomLevel.analyze);
    });

    test('Evaluate: critique', () {
      expect(BloomClassifier.classify('Critique the use of GDP as a measure of national success.'),
          BloomLevel.evaluate);
    });
    test('Evaluate: defend', () {
      expect(BloomClassifier.classify('Defend the position that artificial intelligence will benefit education.'),
          BloomLevel.evaluate);
    });

    test('Create: design', () {
      expect(BloomClassifier.classify('Design a circuit to dim an LED.'),
          BloomLevel.create);
    });
    test('Create: propose', () {
      expect(BloomClassifier.classify('Propose a method to filter microplastics from drinking water.'),
          BloomLevel.create);
    });
  });

  group('BloomClassifier — Spanish', () {
    test('Remember: define', () {
      expect(BloomClassifier.classify('Define la fotosíntesis.'),
          BloomLevel.remember);
    });
    test('Understand: explica', () {
      expect(BloomClassifier.classify('Explica cómo funcionan las vacunas.'),
          BloomLevel.understand);
    });
    test('Apply: calcula', () {
      expect(BloomClassifier.classify('Calcula el área de un triángulo de base 5 y altura 3.'),
          BloomLevel.apply);
    });
    test('Analyze: compara', () {
      expect(BloomClassifier.classify('Compara la mitosis y la meiosis.'),
          BloomLevel.analyze);
    });
    test('Evaluate: evalúa', () {
      expect(BloomClassifier.classify('Evalúa el impacto del cambio climático en los ecosistemas árticos.'),
          BloomLevel.evaluate);
    });
    test('Create: diseña', () {
      expect(BloomClassifier.classify('Diseña un experimento para medir la gravedad.'),
          BloomLevel.create);
    });
  });

  group('BloomClassifier — French', () {
    test('Remember: définis', () {
      expect(BloomClassifier.classify('Définis la photosynthèse.'),
          BloomLevel.remember);
    });
    test('Understand: pourquoi', () {
      expect(BloomClassifier.classify('Pourquoi la glace flotte-t-elle sur l\'eau?'),
          BloomLevel.understand);
    });
    test('Apply: calcule', () {
      expect(BloomClassifier.classify('Calcule la force exercée sur un objet de 10 kg.'),
          BloomLevel.apply);
    });
    test('Analyze: compare', () {
      expect(BloomClassifier.classify('Compare la mitose et la méiose.'),
          BloomLevel.analyze);
    });
    test('Evaluate: évalue', () {
      expect(BloomClassifier.classify('Évalue les avantages et inconvénients de l\'énergie nucléaire.'),
          BloomLevel.evaluate);
    });
    test('Create: conçois', () {
      expect(BloomClassifier.classify('Conçois un système de filtrage de l\'eau.'),
          BloomLevel.create);
    });
  });

  group('BloomClassifier — edge cases', () {
    test('Empty text falls back to Remember', () {
      expect(BloomClassifier.classify(''), BloomLevel.remember);
    });
    test('No verb-key match falls back to Remember', () {
      expect(BloomClassifier.classify('Il sole sorge a est.'), BloomLevel.remember);
    });
    test('Mixed verbs: deepest wins (analyze + remember → analyze)', () {
      // The verb-key heuristic is whole-token: clitic forms like
      // "confrontala" don't match `confronta`. Using a plain conjugation
      // here. (Documented limitation — non-blocking for V1.)
      expect(
        BloomClassifier.classify(
            'Definisci la mitosi e confronta con la meiosi.'),
        BloomLevel.analyze,
      );
    });
    test('Mixed verbs: create + apply → create', () {
      expect(
        BloomClassifier.classify(
            'Calcola la dose richiesta e progetta un protocollo di somministrazione.'),
        BloomLevel.create,
      );
    });
    test('Word boundary: "applicazione" does not match "apply" verb-key', () {
      // "applica" appears as word, but only as substring of "applicazioni";
      // the matcher should NOT pick it up if the text is just the noun.
      expect(
        BloomClassifier.classify('Le applicazioni industriali sono diverse.'),
        BloomLevel.remember, // no other verb hits
      );
    });
    test('Case insensitive', () {
      expect(BloomClassifier.classify('CALCOLA il volume.'), BloomLevel.apply);
      expect(BloomClassifier.classify('SPIEGA il fenomeno.'),
          BloomLevel.understand);
    });
  });

  group('BloomClassifier — batch helpers', () {
    test('classifyAll populates bloomLevel field on each question', () {
      final qs = [
        _q('Definisci la mitosi.'),
        _q('Calcola la velocità.'),
        _q('Progetta un esperimento.'),
      ];
      BloomClassifier.classifyAll(qs);
      expect(qs[0].bloomLevel, BloomLevel.remember);
      expect(qs[1].bloomLevel, BloomLevel.apply);
      expect(qs[2].bloomLevel, BloomLevel.create);
    });

    test('distribution counts each level', () {
      final qs = [
        _q('Definisci X.'), // remember
        _q('Definisci Y.'), // remember
        _q('Calcola Z.'), // apply
        _q('Progetta W.'), // create
      ];
      final dist = BloomClassifier.distribution(qs);
      expect(dist[BloomLevel.remember], 2);
      expect(dist[BloomLevel.apply], 1);
      expect(dist[BloomLevel.create], 1);
      expect(dist[BloomLevel.understand], 0);
    });

    test('deepRatio: 2 of 4 are apply+ → 0.5', () {
      final qs = [
        _q('Definisci X.'), // remember
        _q('Spiega Y.'), // understand
        _q('Calcola Z.'), // apply
        _q('Progetta W.'), // create
      ];
      expect(BloomClassifier.deepRatio(qs), 0.5);
    });

    test('higherOrderRatio: only analyze+ count', () {
      final qs = [
        _q('Definisci X.'), // remember
        _q('Calcola Y.'), // apply (NOT counted)
        _q('Confronta A e B.'), // analyze
        _q('Valuta i pro e contro.'), // evaluate
      ];
      expect(BloomClassifier.higherOrderRatio(qs), 0.5);
    });

    test('deepRatio: empty list returns 0', () {
      expect(BloomClassifier.deepRatio(<ExamQuestion>[]), 0);
    });
  });

  group('BloomLevel — display + ordering', () {
    test('isDeep starts at apply', () {
      expect(BloomLevel.remember.isDeep, isFalse);
      expect(BloomLevel.understand.isDeep, isFalse);
      expect(BloomLevel.apply.isDeep, isTrue);
      expect(BloomLevel.analyze.isDeep, isTrue);
      expect(BloomLevel.evaluate.isDeep, isTrue);
      expect(BloomLevel.create.isDeep, isTrue);
    });

    test('Italian labels are non-empty + unique', () {
      final labels = BloomLevel.values.map((l) => l.italianLabel).toSet();
      expect(labels.length, BloomLevel.values.length);
      for (final l in labels) {
        expect(l, isNotEmpty);
      }
    });

    test('index reflects depth ordering', () {
      expect(BloomLevel.remember.index < BloomLevel.understand.index, isTrue);
      expect(BloomLevel.understand.index < BloomLevel.apply.index, isTrue);
      expect(BloomLevel.apply.index < BloomLevel.analyze.index, isTrue);
      expect(BloomLevel.analyze.index < BloomLevel.evaluate.index, isTrue);
      expect(BloomLevel.evaluate.index < BloomLevel.create.index, isTrue);
    });
  });
}
