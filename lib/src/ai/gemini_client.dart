// ============================================================================
// 🤖 GEMINI CLIENT — abstraction over Gemini API access.
//
// Two implementations:
//
//   • DirectGeminiClient  — uses google_generative_ai with API key in-app.
//                           Fastest, simplest, but the key is in the binary.
//
//   • ProxiedGeminiClient — routes every call through a Supabase Edge
//                           Function that holds the Gemini API key
//                           server-side. Required for production; adds
//                           ~50-100ms latency.
//
// `atlas_ai_service.dart` holds only references to the abstract [GeminiClient]
// and is oblivious to which implementation it's talking to.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

/// Unified Gemini response. Mirrors the fields we actually consume from
/// `google_generative_ai.GenerateContentResponse`: the final assistant text
/// and the usage metadata.
class FGeminiResponse {
  final String? text;
  final FGeminiUsageMetadata? usageMetadata;

  const FGeminiResponse({this.text, this.usageMetadata});
}

class FGeminiUsageMetadata {
  final int? totalTokenCount;
  final int? promptTokenCount;
  final int? candidatesTokenCount;
  const FGeminiUsageMetadata({
    this.totalTokenCount,
    this.promptTokenCount,
    this.candidatesTokenCount,
  });
}

/// Contract every Gemini backend implements. [featureTag] is propagated to
/// the server-side quota ledger when the proxy is in use.
abstract class GeminiClient {
  /// Human-readable model identifier (e.g. "gemini-2.5-flash-lite"). Used
  /// for per-model cost breakdown in telemetry.
  String get modelName;

  Future<FGeminiResponse> generateContent(
    List<Content> contents, {
    required String featureTag,
    int estimate = 1000,
  });

  Stream<FGeminiResponse> generateContentStream(
    List<Content> contents, {
    required String featureTag,
    int estimate = 1000,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Direct implementation — wraps google_generative_ai (key in-app, no proxy)
// ─────────────────────────────────────────────────────────────────────────────

class DirectGeminiClient implements GeminiClient {
  final GenerativeModel _model;
  @override
  final String modelName;
  DirectGeminiClient(this._model, {required this.modelName});

  @override
  Future<FGeminiResponse> generateContent(
    List<Content> contents, {
    required String featureTag,
    int estimate = 1000,
  }) async {
    final resp = await _model.generateContent(contents);
    return FGeminiResponse(
      text: resp.text,
      usageMetadata: resp.usageMetadata == null
          ? null
          : FGeminiUsageMetadata(
              totalTokenCount: resp.usageMetadata!.totalTokenCount,
              promptTokenCount: resp.usageMetadata!.promptTokenCount,
              candidatesTokenCount: resp.usageMetadata!.candidatesTokenCount,
            ),
    );
  }

  @override
  Stream<FGeminiResponse> generateContentStream(
    List<Content> contents, {
    required String featureTag,
    int estimate = 1000,
  }) async* {
    await for (final chunk in _model.generateContentStream(contents)) {
      yield FGeminiResponse(
        text: chunk.text,
        usageMetadata: chunk.usageMetadata == null
            ? null
            : FGeminiUsageMetadata(
                totalTokenCount: chunk.usageMetadata!.totalTokenCount,
                promptTokenCount: chunk.usageMetadata!.promptTokenCount,
                candidatesTokenCount:
                    chunk.usageMetadata!.candidatesTokenCount,
              ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Proxied implementation — hits a Supabase Edge Function that owns the key.
//
// Expected Edge Function URL: <SUPABASE_URL>/functions/v1/gemini-proxy
// Expected headers: Authorization: Bearer <user-jwt>, apikey: <anon-key>
// Payload: { model, feature, estimate, stream, systemInstruction, contents,
//            generationConfig }
// ─────────────────────────────────────────────────────────────────────────────

/// Config object passed by the host app when constructing a proxied client.
/// The app owns Supabase auth, so it injects these.
class GeminiProxyConfig {
  /// Fully-qualified URL of the Edge Function, e.g.
  /// `https://abc.supabase.co/functions/v1/gemini-proxy`.
  final String functionUrl;

  /// Supabase anonymous key (`SUPABASE_ANON_KEY`). Required by the Edge
  /// Functions router even when a user JWT is also present.
  final String anonKey;

  /// Async callback that returns the current user's JWT — used in the
  /// `Authorization: Bearer` header. May return null if the user signed
  /// out between construction and call; in that case we throw.
  final Future<String?> Function() accessTokenGetter;

  const GeminiProxyConfig({
    required this.functionUrl,
    required this.anonKey,
    required this.accessTokenGetter,
  });
}

class ProxiedGeminiClient implements GeminiClient {
  @override
  final String modelName;
  final String? _systemInstructionText;
  final Map<String, dynamic>? _generationConfig;
  final GeminiProxyConfig _config;
  final http.Client _http;

  ProxiedGeminiClient({
    required this.modelName,
    String? systemInstructionText,
    Map<String, dynamic>? generationConfig,
    required GeminiProxyConfig config,
    http.Client? httpClient,
  })  : _systemInstructionText = systemInstructionText,
        _generationConfig = generationConfig,
        _config = config,
        _http = httpClient ?? http.Client();

  @override
  Future<FGeminiResponse> generateContent(
    List<Content> contents, {
    required String featureTag,
    int estimate = 1000,
  }) async {
    final token = await _config.accessTokenGetter();
    if (token == null) {
      throw StateError('gemini-proxy: no access token available');
    }

    final response = await _http.post(
      Uri.parse(_config.functionUrl),
      headers: _headers(token),
      body: jsonEncode(_buildBody(
        stream: false,
        featureTag: featureTag,
        estimate: estimate,
        contents: contents,
      )),
    );

    if (response.statusCode == 429) {
      // Server says quota exceeded — surface clearly so callers can map to
      // AiQuotaExceededException if needed.
      throw GeminiProxyQuotaExceededException();
    }
    if (response.statusCode >= 400) {
      throw GeminiProxyException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseGeminiJson(json);
  }

  @override
  Stream<FGeminiResponse> generateContentStream(
    List<Content> contents, {
    required String featureTag,
    int estimate = 1000,
  }) async* {
    final token = await _config.accessTokenGetter();
    if (token == null) {
      throw StateError('gemini-proxy: no access token available');
    }

    final request = http.Request('POST', Uri.parse(_config.functionUrl))
      ..headers.addAll(_headers(token))
      ..body = jsonEncode(_buildBody(
        stream: true,
        featureTag: featureTag,
        estimate: estimate,
        contents: contents,
      ));

    final streamed = await _http.send(request);

    if (streamed.statusCode == 429) {
      throw GeminiProxyQuotaExceededException();
    }
    if (streamed.statusCode >= 400) {
      final body = await streamed.stream.bytesToString();
      throw GeminiProxyException(
        statusCode: streamed.statusCode,
        body: body,
      );
    }

    // Gemini's SSE events are newline-delimited. Each event starts with
    // `data: ` and contains a single JSON chunk. We parse and yield.
    final utf8Lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in utf8Lines) {
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        yield _parseGeminiJson(json);
      } catch (_) {
        // Tolerate malformed chunks — Gemini occasionally emits keep-alives
        // or partial JSON across chunk boundaries. We skip and continue.
      }
    }
  }

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': _config.anonKey,
      };

  Map<String, dynamic> _buildBody({
    required bool stream,
    required String featureTag,
    required int estimate,
    required List<Content> contents,
  }) {
    final body = <String, dynamic>{
      'stream': stream,
      'model': modelName,
      'feature': featureTag,
      'estimate': estimate,
      'contents': contents.map(_encodeContent).toList(),
    };
    if (_systemInstructionText != null) {
      body['systemInstruction'] = _systemInstructionText;
    }
    if (_generationConfig != null) {
      body['generationConfig'] = _generationConfig;
    }
    return body;
  }

  Map<String, dynamic> _encodeContent(Content c) {
    // google_generative_ai Content doesn't expose a simple toJson; we
    // rebuild the minimal Gemini REST shape from the parts we know about
    // (text parts only — that's all atlas_ai_service uses today).
    return {
      if (c.role != null) 'role': c.role,
      'parts': c.parts.map((part) {
        if (part is TextPart) return {'text': part.text};
        // Defensive: anything else stringified so we don't silently drop
        // data. In practice atlas_ai_service only passes TextPart.
        return {'text': part.toString()};
      }).toList(),
    };
  }

  FGeminiResponse _parseGeminiJson(Map<String, dynamic> json) {
    // Extract first candidate's first part text. Matches Gemini REST format.
    String? text;
    final candidates = json['candidates'] as List?;
    if (candidates != null && candidates.isNotEmpty) {
      final first = candidates.first as Map<String, dynamic>?;
      final parts = (first?['content'] as Map?)?['parts'] as List?;
      if (parts != null && parts.isNotEmpty) {
        final t = (parts.first as Map?)?['text'];
        if (t is String) text = t;
      }
    }

    FGeminiUsageMetadata? usage;
    final meta = json['usageMetadata'] as Map<String, dynamic>?;
    if (meta != null) {
      usage = FGeminiUsageMetadata(
        totalTokenCount: (meta['totalTokenCount'] as num?)?.toInt(),
        promptTokenCount: (meta['promptTokenCount'] as num?)?.toInt(),
        candidatesTokenCount:
            (meta['candidatesTokenCount'] as num?)?.toInt(),
      );
    }

    return FGeminiResponse(text: text, usageMetadata: usage);
  }
}

/// Thrown when the Edge Function reports an unexpected HTTP status. Caller
/// usually just wraps/logs this; it's not a user-actionable error.
class GeminiProxyException implements Exception {
  final int statusCode;
  final String body;
  GeminiProxyException({required this.statusCode, required this.body});

  @override
  String toString() => 'GeminiProxyException($statusCode): $body';
}

/// Thrown specifically when the Edge Function returns 429 — the user has
/// exhausted their AI quota server-side. Callers map this to
/// [AiQuotaExceededException] for the unified UI flow.
class GeminiProxyQuotaExceededException implements Exception {
  @override
  String toString() => 'GeminiProxyQuotaExceededException';
}
