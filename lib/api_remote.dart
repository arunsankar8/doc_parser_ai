import 'dart:convert';

import 'package:http/http.dart' as http;

const model = 'gemini-3.6-flash';
const basePath = "https://generativelanguage.googleapis.com/v1beta/models/";
const endpointStreaming = '$model:streamGenerateContent?alt=sse';
const endpointCountTokens = '$model:countTokens';

// Gemini Standard tier pricing, per 1M tokens (USD), effective through
// 2026-12-31. Source: ai.google.dev/pricing — re-check before 2027-01-01,
// prices roughly double after that.
const inputPricePerMillion = 0.75;
const outputPricePerMillion = 3.75;

/// Usage numbers Gemini reports back with a response — read this after the
/// stream finishes to see what a request actually cost, vs. the countTokens
/// estimate you had before sending.
///
/// thoughtsTokens are the model's internal reasoning tokens (Gemini 3.x
/// "thinking" models generate these before the visible answer). They're
/// invisible in the response text but billed at the OUTPUT rate — Gemini's
/// own pricing page says so explicitly ("Output price, including thinking
/// tokens"). Leaving them out of outputCost would silently undercount the
/// real bill, sometimes by more than the visible answer itself costs.
class UsageInfo {
  final int promptTokens;
  final int candidatesTokens;
  final int thoughtsTokens;
  UsageInfo({
    required this.promptTokens,
    required this.candidatesTokens,
    this.thoughtsTokens = 0,
  });

  double get inputCost => (promptTokens / 1000000) * inputPricePerMillion;
  double get outputCost =>
      ((candidatesTokens + thoughtsTokens) / 1000000) * outputPricePerMillion;
  double get totalCost => inputCost + outputCost;
}

/// Streams a generateContent response for [parts] (e.g. [documentText,
/// question] as separate content parts). [onUsage] is called once, if the
/// stream carries a usageMetadata block — usually alongside the final chunk.
Stream<String> streamLlmApiResponse(
  List<String> parts, {
  void Function(UsageInfo)? onUsage,
}) async* {
  final client = http.Client();
  try {
    var request = createRequestHeader(
      parts,
      endpointStreaming,
      includeSystemInstruction: true,
    );

    final response = await client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, body);
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 30));

    String? finishReason;
    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final payload = line.substring(6);

      final json = jsonDecode(payload) as Map<String, dynamic>;

      final usage = json['usageMetadata'] as Map<String, dynamic>?;
      if (usage != null && onUsage != null) {
        onUsage(
          UsageInfo(
            promptTokens: usage['promptTokenCount'] as int? ?? 0,
            candidatesTokens: usage['candidatesTokenCount'] as int? ?? 0,
            thoughtsTokens: usage['thoughtsTokenCount'] as int? ?? 0,
          ),
        );
      }

      if (json['candidates'] != null &&
          (json['candidates'] as List).isNotEmpty == true) {
        if (json['candidates']?[0]?['finishReason'] != null) {
          if (json['candidates']?[0]?['finishReason'] == 'STOP') {
            finishReason = 'STOP';
          } else {
            finishReason = json['candidates']?[0]?['finishReason'];
          }
          var text = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
          if (text != null && (text as String).isNotEmpty) {
            yield text;
          }
        } else if (json['candidates']?[0]?['content']?['parts']?[0]?['text'] !=
            null) {
          yield json['candidates']?[0]?['content']?['parts']?[0]?['text']
              as String;
        }
      } else {
        continue;
      }
    }
    if (finishReason == null) {
      yield '...[ Connection Dropped ]';
    } else if (finishReason != 'STOP') {
      yield '...[ Stopped : $finishReason ]';
    }
  } finally {
    client.close();
  }
}

/// Calls Gemini's countTokens endpoint for [parts] and returns the token
/// count. countTokens is NOT streaming — it's a plain request/response, one
/// JSON object back, same shape you tested with curl in Slice 1.
Future<int> requestTokenCount(List<String> parts) async {
  final client = http.Client();
  try {
    var request = createRequestHeader(
      parts,
      endpointCountTokens,
      includeSystemInstruction: false,
    );

    final response = await client.send(request);

    final body = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, body);
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['totalTokens'] as int;
  } finally {
    client.close();
  }
}

/// Builds the POST request for [endpoint], with one content part per string
/// in [parts]. Pass a single-element list for a plain question; pass
/// [documentText, question] to send a document alongside a question about
/// it — same "contents: [{ parts: [...] }]" shape either way, just more
/// parts in the list.
http.Request createRequestHeader(
  List<String> parts,
  String endpoint, {
  bool includeSystemInstruction = false,
}) {
  final request = http.Request('POST', Uri.parse(basePath + endpoint));
  const apiKey = String.fromEnvironment('GEMINI_KEY');
  if (apiKey.isEmpty) {
    throw ApiException(100, 'no api key');
  }
  request.headers.addAll({
    'x-goog-api-key': apiKey,
    'content-type': 'application/json',
  });
  var body = {
    if (includeSystemInstruction)
      "systemInstruction": {
        "parts": [
          {
            "text": "Answer only using the provided document. If the answer isn't in it, say so.",
          },
        ],
      },
    "contents": [
      {
        "parts": [
          for (final part in parts) {"text": part},
        ],
      },
    ],
  };
  request.body = jsonEncode(body);
  return request;
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  String get userMessage => switch (statusCode) {
    100 => "No Api Key",
    401 => 'Invalid API key',
    429 => 'Rate limited — try again in a moment',
    >= 500 => 'Service unavailable — try again',
    _ => 'Something went wrong ($statusCode)',
  };
}

enum ApiStatus { idle, streaming, failed, completed }
