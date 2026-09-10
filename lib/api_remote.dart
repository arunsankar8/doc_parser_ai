import 'dart:convert';

import 'package:http/http.dart' as http;

const model = 'gemini-3.6-flash';
const basePath = "https://generativelanguage.googleapis.com/v1beta/models/";
const endpointStreaming = '$model:streamGenerateContent?alt=sse';
const endpointountTokens = '$model:countTokens';

Stream<String> streamLlmApiResponse(String prompt) async* {
  final client = http.Client();
  try {
    var request = createRequestHeader(prompt, endpointStreaming);

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

Future<dynamic> requestTokenCount(String prompt) async {
  final client = http.Client();
  try {
    var request = createRequestHeader(prompt, endpointStreaming);

    final response = await client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, body);
    }
  } finally {
    client.close();
  }
}

http.Request createRequestHeader(String prompt, String endpoint) {
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
    "contents": [
      {
        "parts": [
          {"text": prompt},
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
