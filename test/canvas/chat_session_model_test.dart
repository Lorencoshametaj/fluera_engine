import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/chat_session_model.dart';

void main() {
  group('ChatMessage', () {
    test('creates with required fields', () {
      final msg = ChatMessage(
        id: 'msg_1',
        role: ChatMessageRole.user,
        text: 'Hello Atlas',
      );
      expect(msg.id, 'msg_1');
      expect(msg.role, ChatMessageRole.user);
      expect(msg.text, 'Hello Atlas');
      expect(msg.isStreaming, false);
      expect(msg.referencedClusterIds, isEmpty);
    });

    test('serialization roundtrip preserves all fields', () {
      final msg = ChatMessage(
        id: 'msg_42',
        role: ChatMessageRole.atlas,
        text: 'Here is the explanation...',
        timestamp: DateTime(2026, 3, 28, 12, 0),
        referencedClusterIds: ['cluster_a', 'cluster_b'],
      );

      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.id, msg.id);
      expect(restored.role, msg.role);
      expect(restored.text, msg.text);
      expect(restored.timestamp, msg.timestamp);
      expect(restored.referencedClusterIds, msg.referencedClusterIds);
    });

    test('fromJson handles missing fields gracefully', () {
      final msg = ChatMessage.fromJson({'text': 'fallback'});
      expect(msg.id, '');
      expect(msg.role, ChatMessageRole.user);
      expect(msg.text, 'fallback');
      expect(msg.referencedClusterIds, isEmpty);
    });

    test('fromJson handles empty map', () {
      final msg = ChatMessage.fromJson({});
      expect(msg.id, '');
      expect(msg.text, '');
      expect(msg.role, ChatMessageRole.user);
    });

    test('toString truncates long text', () {
      final msg = ChatMessage(
        id: 'x',
        role: ChatMessageRole.user,
        text: 'A' * 100,
      );
      expect(msg.toString(), contains('...'));
      expect(msg.toString().length, lessThan(100));
    });

    test('isStreaming can be toggled', () {
      final msg = ChatMessage(
        id: 'x',
        role: ChatMessageRole.atlas,
        text: '',
        isStreaming: true,
      );
      expect(msg.isStreaming, true);
      msg.isStreaming = false;
      expect(msg.isStreaming, false);
    });
  });

  group('ChatSession', () {
    test('creates with defaults', () {
      final session = ChatSession(sessionId: 'test_session');
      expect(session.messages, isEmpty);
      expect(session.scope, ChatContextScope.allCanvas);
      expect(session.title, isNull);
      expect(session.hasUserMessages, false);
    });

    test('contextWindow returns all messages when under limit', () {
      final session = ChatSession(
        sessionId: 's1',
        messages: List.generate(
          5,
          (i) => ChatMessage(
            id: 'msg_$i',
            role: ChatMessageRole.user,
            text: 'Message $i',
          ),
        ),
      );
      expect(session.contextWindow(maxMessages: 20).length, 5);
    });

    test('contextWindow truncates to last N messages', () {
      final session = ChatSession(
        sessionId: 's2',
        messages: List.generate(
          30,
          (i) => ChatMessage(
            id: 'msg_$i',
            role: ChatMessageRole.user,
            text: 'Message $i',
          ),
        ),
      );
      final window = session.contextWindow(maxMessages: 10);
      expect(window.length, 10);
      expect(window.first.id, 'msg_20');
      expect(window.last.id, 'msg_29');
    });

    test('hasUserMessages detects user messages', () {
      final session = ChatSession(sessionId: 's3');
      expect(session.hasUserMessages, false);

      session.messages.add(ChatMessage(
        id: 'a1',
        role: ChatMessageRole.atlas,
        text: 'Welcome!',
      ));
      expect(session.hasUserMessages, false);

      session.messages.add(ChatMessage(
        id: 'u1',
        role: ChatMessageRole.user,
        text: 'Hello',
      ));
      expect(session.hasUserMessages, true);
    });

    test('serialization roundtrip preserves session', () {
      final session = ChatSession(
        sessionId: 'roundtrip_test',
        scope: ChatContextScope.selectedClusters,
        title: 'My Study Session',
        messages: [
          ChatMessage(id: 'm1', role: ChatMessageRole.user, text: 'What is DNA?'),
          ChatMessage(id: 'm2', role: ChatMessageRole.atlas, text: 'DNA is...'),
        ],
      );

      final json = session.toJson();
      final restored = ChatSession.fromJson(json);

      expect(restored.sessionId, session.sessionId);
      expect(restored.scope, ChatContextScope.selectedClusters);
      expect(restored.title, 'My Study Session');
      expect(restored.messages.length, 2);
      expect(restored.messages[0].text, 'What is DNA?');
      expect(restored.messages[1].role, ChatMessageRole.atlas);
    });

    test('fromJson handles empty/corrupted data', () {
      final session = ChatSession.fromJson({});
      expect(session.sessionId, '');
      expect(session.messages, isEmpty);
      expect(session.scope, ChatContextScope.allCanvas);
    });
  });

  group('ChatHistoryRecord', () {
    test('serialization roundtrip', () {
      final record = ChatHistoryRecord(
        sessionId: 'hist_1',
        date: DateTime(2026, 3, 28),
        title: 'Integrali',
        messageCount: 12,
      );

      final json = record.toJson();
      final restored = ChatHistoryRecord.fromJson(json);

      expect(restored.sessionId, 'hist_1');
      expect(restored.title, 'Integrali');
      expect(restored.messageCount, 12);
    });

    test('fromJson handles missing optional fields', () {
      final record = ChatHistoryRecord.fromJson({
        'sessionId': 'x',
        'date': '2026-03-28T00:00:00.000',
        'messageCount': 5,
      });
      expect(record.title, isNull);
      expect(record.messageCount, 5);
    });
  });

  group('ChatContextScope', () {
    test('all values are defined', () {
      expect(ChatContextScope.values.length, 4);
      expect(ChatContextScope.values, contains(ChatContextScope.allCanvas));
      expect(ChatContextScope.values, contains(ChatContextScope.selectedClusters));
      expect(ChatContextScope.values, contains(ChatContextScope.currentViewport));
      expect(ChatContextScope.values, contains(ChatContextScope.activePdf));
    });
  });
}
