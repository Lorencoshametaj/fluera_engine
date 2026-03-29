import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/chat_context_builder.dart';
import 'package:fluera_engine/src/canvas/ai/chat_session_model.dart';

void main() {
  group('ChatContextBuilder.buildContext', () {
    final mockClusterTexts = {
      'c1': 'Integrali definiti e indefiniti',
      'c2': 'Teorema fondamentale del calcolo',
      'c3': 'Derivate e funzioni continue',
      'c4': '', // empty cluster
    };

    final mockTitles = {
      'c1': 'Integrali',
      'c2': 'Teorema Fondamentale',
    };

    test('allCanvas scope includes all non-empty clusters', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: mockClusterTexts,
        clusterTitles: mockTitles,
        scope: ChatContextScope.allCanvas,
      );

      expect(context, contains('STUDENT NOTES'));
      expect(context, contains('Integrali definiti'));
      expect(context, contains('Teorema fondamentale'));
      expect(context, contains('Derivate'));
      // Empty cluster (c4) should not appear
      expect(context, isNot(contains('Note 4')));
    });

    test('selectedClusters scope filters correctly', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: mockClusterTexts,
        clusterTitles: mockTitles,
        scope: ChatContextScope.selectedClusters,
        selectedClusterIds: {'c1', 'c3'},
      );

      expect(context, contains('Integrali definiti'));
      expect(context, contains('Derivate'));
      expect(context, isNot(contains('Teorema fondamentale')));
    });

    test('currentViewport scope filters by visible IDs', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: mockClusterTexts,
        clusterTitles: mockTitles,
        scope: ChatContextScope.currentViewport,
        visibleClusterIds: {'c2'},
      );

      expect(context, contains('Teorema fondamentale'));
      expect(context, isNot(contains('Integrali definiti')));
      expect(context, isNot(contains('Derivate')));
    });

    test('activePdf scope includes PDF content', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: mockClusterTexts,
        scope: ChatContextScope.activePdf,
        pdfTexts: {
          '1': 'Capitolo 1: Analisi Matematica',
          '2': 'Capitolo 2: Calcolo Integrale',
        },
      );

      expect(context, contains('PDF CONTENT'));
      expect(context, contains('Capitolo 1'));
      expect(context, contains('Capitolo 2'));
      // Cluster content should NOT be included for activePdf scope
      expect(context, isNot(contains('STUDENT NOTES')));
    });

    test('includes semantic titles when available', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: mockClusterTexts,
        clusterTitles: mockTitles,
        scope: ChatContextScope.allCanvas,
      );

      expect(context, contains('Integrali'));
      expect(context, contains('Teorema Fondamentale'));
    });

    test('includes audio transcripts', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: {'c1': 'Note scritte'},
        audioTranscripts: {'c1': 'Trascrizione audio del professore'},
        scope: ChatContextScope.allCanvas,
      );

      expect(context, contains('Audio transcript'));
      expect(context, contains('Trascrizione audio'));
    });

    test('returns fallback message when no content available', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: {},
        scope: ChatContextScope.allCanvas,
      );

      expect(context, contains('No notes available'));
    });

    test('empty selection returns fallback', () {
      final context = ChatContextBuilder.buildContext(
        clusterTexts: mockClusterTexts,
        scope: ChatContextScope.selectedClusters,
        selectedClusterIds: {}, // nothing selected
      );

      expect(context, contains('No notes available'));
    });
  });

  group('ChatContextBuilder.buildConversationHistory', () {
    test('formats messages with role labels', () {
      final messages = [
        ChatMessage(id: 'm1', role: ChatMessageRole.user, text: 'What is DNA?'),
        ChatMessage(id: 'm2', role: ChatMessageRole.atlas, text: 'DNA is a molecule...'),
      ];

      final history = ChatContextBuilder.buildConversationHistory(messages);

      expect(history, contains('CONVERSATION HISTORY'));
      expect(history, contains('STUDENT: What is DNA?'));
      expect(history, contains('ATLAS: DNA is a molecule'));
    });

    test('skips system messages', () {
      final messages = [
        ChatMessage(id: 's1', role: ChatMessageRole.system, text: 'System context'),
        ChatMessage(id: 'u1', role: ChatMessageRole.user, text: 'Hello'),
      ];

      final history = ChatContextBuilder.buildConversationHistory(messages);

      expect(history, isNot(contains('System context')));
      expect(history, contains('STUDENT: Hello'));
    });

    test('returns empty string for empty messages', () {
      final history = ChatContextBuilder.buildConversationHistory([]);
      expect(history, isEmpty);
    });

    test('respects maxMessages limit', () {
      final messages = List.generate(
        30,
        (i) => ChatMessage(
          id: 'msg_$i',
          role: ChatMessageRole.user,
          text: 'Message $i',
        ),
      );

      final history = ChatContextBuilder.buildConversationHistory(
        messages,
        maxMessages: 5,
      );

      expect(history, contains('Message 25'));
      expect(history, contains('Message 29'));
      expect(history, isNot(contains('Message 0')));
      expect(history, isNot(contains('Message 24')));
    });
  });

  group('ChatContextBuilder.scopeLabel', () {
    test('allCanvas label', () {
      final label = ChatContextBuilder.scopeLabel(ChatContextScope.allCanvas);
      expect(label, contains('Tutto il canvas'));
    });

    test('selectedClusters label includes count', () {
      final label = ChatContextBuilder.scopeLabel(
        ChatContextScope.selectedClusters,
        selectedCount: 5,
      );
      expect(label, contains('5'));
      expect(label, contains('cluster'));
    });

    test('currentViewport label', () {
      final label = ChatContextBuilder.scopeLabel(ChatContextScope.currentViewport);
      expect(label, contains('Vista'));
    });

    test('activePdf label with custom name', () {
      final label = ChatContextBuilder.scopeLabel(
        ChatContextScope.activePdf,
        pdfName: 'Analisi.pdf',
      );
      expect(label, contains('Analisi.pdf'));
    });

    test('activePdf label with default name', () {
      final label = ChatContextBuilder.scopeLabel(ChatContextScope.activePdf);
      expect(label, contains('PDF'));
    });
  });
}
