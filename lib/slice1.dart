import 'dart:async';
import 'dart:io';

import 'package:doc_parser/api_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

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
      await for (String chunk in streamLlmApiResponse(prompt)) {
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
          text: currentValue.isEmpty ? null : currentValue,
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
