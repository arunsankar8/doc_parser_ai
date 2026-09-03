import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

const basePath =
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse";
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: BlocProvider(
        create: (context) => AiCubit(),
        child: const MyHomePage(title: 'Flutter Demo Home Page'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: .start,
          crossAxisAlignment: .start,
          children: [
            SizedBox(height: 50),
            const Text('Whats on your mind?', style: TextStyle(fontSize: 18)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: controller,
                style: TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  suffixIcon: BlocBuilder<AiCubit, AICubitState>(
                    builder: (context, state) {
                      return IconButton(
                        onPressed:
                            (state is! AIResponseState ||
                                state.status != ApiStatus.streaming)
                            ? () {
                                context.read<AiCubit>().callApi(
                                  controller.text,
                                );
                              }
                            : null,
                        icon: Icon(Icons.send),
                      );
                    },
                  ),
                ),
              ),
            ),
            SizedBox(height: 50),
            Expanded(
              child: BlocBuilder<AiCubit, AICubitState>(
                builder: (context, state) {
                  if (state is AIResponseState) {
                    return Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            "ans: ",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                (state.text ?? state.error) ??
                                    'Something went wrong',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return Text('');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiCubit extends Cubit<AICubitState> {
  AiCubit() : super(AICubitState());
  String currentValue = '';
  Future<void> callApi(String prompt) async {
    try {
      emit(AIResponseState(text: currentValue, status: ApiStatus.streaming));
      await for (String chunk in streamCompletion(prompt)) {
        currentValue += chunk;
        emit(AIResponseState(text: currentValue, status: ApiStatus.streaming));
      }
      emit(AIResponseState(text: currentValue, status: ApiStatus.completed));
    } on ApiException catch (e) {
      emit(
        AIResponseState(
          text: null,
          error: e.userMessage,
          status: ApiStatus.failed,
        ),
      );
    } on SocketException {
      emit(
        AIResponseState(
          text: currentValue.isEmpty?null:currentValue,
          error: 'No connection',
          status: ApiStatus.failed,
        ),
      );
    } on http.ClientException {
      emit(
        AIResponseState(
           text: currentValue.isEmpty ? null : currentValue,
          error: 'No connection',
          status: ApiStatus.failed,
        ),
      );
    } on TimeoutException {
      emit(
        AIResponseState(
           text: currentValue.isEmpty ? null : currentValue,
          error: 'TimedOut',
          status: ApiStatus.failed,
        ),
      );
    } finally {
      currentValue = '';
    }
  }

  Stream<String> streamCompletion(String prompt) async* {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(basePath));
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

      final response = await client
          .send(request);

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
            var text =
                json['candidates']?[0]?['content']?['parts']?[0]?['text'];
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
}

class AICubitState {
  const AICubitState();
}

class AIResponseState extends AICubitState {
  final String? text;
  final String? error;

  final ApiStatus status;
  AIResponseState({this.text, this.error, this.status = ApiStatus.idle});
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
