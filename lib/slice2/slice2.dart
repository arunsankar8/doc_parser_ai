import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../remote/api_remote.dart';
import 'document_controller.dart';

/// Pure UI. All state and logic (file pick, extraction, token counting,
/// asking a question, full-context vs retrieval) live in DocumentCubit —
/// this widget only reads DocumentState and dispatches button taps to the
/// cubit's methods.
class Slice2Home extends StatelessWidget {
  const Slice2Home({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DocumentCubit(),
      child: _Slice2View(title: title),
    );
  }
}

class _Slice2View extends StatefulWidget {
  const _Slice2View({required this.title});

  final String title;

  @override
  State<_Slice2View> createState() => _Slice2ViewState();
}

class _Slice2ViewState extends State<_Slice2View> {
  final TextEditingController controller = TextEditingController();

  // Local copy of api_remote's selectedModel, just so the dropdown has
  // something to rebuild against. api_remote.selectedModel is the one that
  // actually drives requests — this field only mirrors it for display.
  String currentModel = selectedModel;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DocumentCubit>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Clear file, question and answer',
            onPressed: () {
              controller.clear();
              cubit.clearAll();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocBuilder<DocumentCubit, DocumentState>(
        builder: (context, state) {
          return Center(
            child: Column(
              mainAxisAlignment: .start,
              crossAxisAlignment: .start,
              children: [
                SizedBox(height: 20),
                Row(
                  children: [
                    const Text('model  : ', style: TextStyle(fontSize: 18)),
                    DropdownButton<String>(
                      value: currentModel,
                      items: availableModels
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (m) {
                        if (m == null) return;
                        setState(() => currentModel = m);
                        selectedModel = m; // api_remote.dart's mutable global
                      },
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    const Text('mode  : ', style: TextStyle(fontSize: 18)),
                    const Text(
                      'full context',
                      style: TextStyle(fontSize: 13),
                    ),
                    Switch(
                      value: state.mode == QueryMode.retrieval,
                      onChanged: (useRetrieval) {
                        cubit.setMode(
                          useRetrieval
                              ? QueryMode.retrieval
                              : QueryMode.fullContext,
                        );
                      },
                    ),
                    const Text('retrieval', style: TextStyle(fontSize: 13)),
                  ],
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'pick a doc  : ',
                      style: TextStyle(fontSize: 18),
                    ),
                    ElevatedButton(
                      onPressed: state.isPickingFile ? null : cubit.pickPdf,
                      child: const Text('File picker'),
                    ),
                    if (state.isPickingFile) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'reading & extracting…',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: TextField(
                    controller: controller,
                    style: TextStyle(fontSize: 18),
                    onSubmitted: (_) => cubit.askQuestion(controller.text),
                    decoration: InputDecoration(
                      hint: Text('Ask about the file'),
                      suffixIcon: state.questionStatus == ApiStatus.streaming
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: () =>
                                  cubit.askQuestion(controller.text),
                              icon: Icon(Icons.send),
                            ),
                    ),
                  ),
                ),
                SizedBox(height: 50),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: .start,
                            children: [
                              const Text(
                                "File Details: ",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Expanded(
                                child: state.pickError != null
                                    ? Text(
                                        state.pickError!,
                                        style: const TextStyle(fontSize: 14),
                                      )
                                    : state.pickedFilePath == null
                                    ? const Text(
                                        'No file picked yet',
                                        style: TextStyle(fontSize: 14),
                                      )
                                    : Column(
                                        crossAxisAlignment: .start,
                                        children: [
                                          Text(
                                            'name: ${state.pickedFileName}\n'
                                            'size: ${state.pickedFileBytes} bytes '
                                            '(${(state.pickedFileBytes! / 1024).toStringAsFixed(1)} KB)\n'
                                            'path: ${state.pickedFilePath}\n'
                                            'Contents size : ${state.contents?.length}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (state.isCountingDocTokens)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'counting tokens…',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Text(
                                              'tokens: ${state.tokenCount ?? state.tokenCountError ?? '—'}'
                                              '${state.tokenCount != null ? '  (~\$${((state.tokenCount! / 1000000) * inputPricePerMillion).toStringAsFixed(4)} per question, input only)' : ''}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                          if (state.mode == QueryMode.retrieval) ...[
                            Divider(height: 5),
                            Row(
                              crossAxisAlignment: .start,
                              children: [
                                const Text(
                                  "retrieved: ",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: state.retrievedChunks.isEmpty
                                      ? const Text(
                                          '(no chunks retrieved yet)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment: .start,
                                          children: [
                                            for (final c
                                                in state.retrievedChunks)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                      bottom: 4,
                                                    ),
                                                child: Text(
                                                  '#${c.index} (${c.score.toStringAsFixed(3)})  '
                                                  '${c.text.length > 100 ? '${c.text.substring(0, 100)}…' : c.text}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ],
                          Divider(height: 5),
                          Row(
                            crossAxisAlignment: .start,
                            children: [
                              const Text(
                                "ans: ",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: .start,
                                    children: [
                                      if (state.isCountingQuestionTokens)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 4),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'counting question+doc tokens…',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (state.questionTokenCount !=
                                          null)
                                        Text(
                                          'question+doc tokens: ${state.questionTokenCount}'
                                          '  (~\$${((state.questionTokenCount! / 1000000) * inputPricePerMillion).toStringAsFixed(4)} est. input)',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      if (state.questionStatus ==
                                              ApiStatus.streaming &&
                                          state.answer.isEmpty &&
                                          !state.isCountingQuestionTokens)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 4),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'waiting for answer…',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (state.questionError != null)
                                        Text(
                                          state.questionError!,
                                          style: const TextStyle(
                                            fontSize: 18,
                                          ),
                                        )
                                      else
                                        Text(
                                          state.answer,
                                          style: const TextStyle(
                                            fontSize: 18,
                                          ),
                                        ),
                                      if (state.lastUsage != null)
                                        Text(
                                          'actual — input: ${state.lastUsage!.promptTokens} tok '
                                          '(\$${state.lastUsage!.inputCost.toStringAsFixed(4)}), '
                                          'output: ${state.lastUsage!.candidatesTokens} tok visible '
                                          '+ ${state.lastUsage!.thoughtsTokens} thinking '
                                          '(\$${state.lastUsage!.outputCost.toStringAsFixed(4)}), '
                                          'total: \$${state.lastUsage!.totalCost.toStringAsFixed(4)}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
