import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'api_remote.dart';

class Slice2Home extends StatefulWidget {
  const Slice2Home({super.key, required this.title});

  final String title;

  @override
  State<Slice2Home> createState() => _Slice2HomeState();
}

class _Slice2HomeState extends State<Slice2Home> {
  TextEditingController controller = TextEditingController();

  // Local copy of api_remote's selectedModel, just so the dropdown has
  // something to rebuild against. api_remote.selectedModel is the one that
  // actually drives requests — this field only mirrors it for display.
  String currentModel = selectedModel;

  /// The PDF the user picked. Null until they pick one.
  String? pickedFilePath;
  String? pickedFileName;
  int? pickedFileBytes;
  String? pickError;
  String? contents;
  int? tokenCount;
  String? tokenCountError;

  /// True while pickPdf's file-pick + PDF text extraction is in flight
  /// (before the doc's own token count starts).
  bool isPickingFile = false;

  /// True while the doc-only countTokens call (inside pickPdf) is in flight.
  bool isCountingDocTokens = false;

  /// State for asking a question about the picked document.
  ApiStatus questionStatus = ApiStatus.idle;
  int? questionTokenCount; // countTokens for [contents, question] combined
  String answer = '';
  String? questionError;
  UsageInfo? lastUsage; // actual usage, from the streamed response

  /// True only during the pre-send countTokens call in askQuestion — as
  /// opposed to questionStatus == streaming, which covers the actual answer
  /// streaming in. Kept separate so the UI can show "counting…" vs
  /// "answering…" as two different loaders instead of one generic spinner.
  bool isCountingQuestionTokens = false;

  /// Slice 2 (whole document in every prompt) vs Slice 3 (retrieve only the
  /// relevant chunks). Both read/write the same picked document and question
  /// — flipping this is the whole point: same doc, same question, compare
  /// tokens/cost/latency/correctness across modes without re-picking or
  /// retyping anything. That's Slice 3 Step 4.
  QueryMode mode = QueryMode.fullContext;

  /// Chunks retrieved for the most recent retrieval-mode question, with
  /// their similarity scores — shown in the UI so a wrong answer can be
  /// diagnosed as "retrieval picked the wrong chunks" vs "generation got it
  /// wrong despite good chunks". Slice 3 Step 3's "show your work".
  List<RetrievedChunk> retrievedChunks = [];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> pickPdf() async {
    setState(() {
      pickError = null;
      tokenCount = null;
      tokenCountError = null;
      isPickingFile = true;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      // User dismissed the picker without choosing anything.
      if (file == null) return;

      final path = file.path;
      if (path == null) {
        setState(() => pickError = 'Could not read the file path.');
        return;
      }

      final bytes = await file.length();
      final extracted = await extractDocContent(path);
      setState(() {
        pickedFilePath = path;
        pickedFileName = file.name;
        pickedFileBytes = bytes;
        contents = extracted;
        isPickingFile = false;
        isCountingDocTokens = true;
      });

      // Count tokens for the extracted text. Kept as its own try/catch so a
      // token-count failure (e.g. rate limit) doesn't wipe out the file
      // details and extracted text you already have on screen.
      try {
        final count = await requestTokenCount([extracted]);
        setState(() => tokenCount = count);
      } on ApiException catch (e) {
        setState(() => tokenCountError = e.userMessage);
      } finally {
        setState(() => isCountingDocTokens = false);
      }
      // ignore: avoid_print
      print(
        'Picked: $pickedFileName  ($bytes bytes) -- (${contents?.length})  -- tokenCount - $tokenCount',
      );
    } catch (e) {
      setState(() => pickError = 'File pick failed: $e');
    } finally {
      setState(() => isPickingFile = false);
    }
  }

  /// Resets every field for a fresh document + question, without touching
  /// the model selection (that's a separate concern, not part of "start
  /// over with a new file").
  void clearAll() {
    controller.clear();
    setState(() {
      pickedFilePath = null;
      pickedFileName = null;
      pickedFileBytes = null;
      pickError = null;
      contents = null;
      tokenCount = null;
      tokenCountError = null;
      isPickingFile = false;
      isCountingDocTokens = false;

      questionStatus = ApiStatus.idle;
      questionTokenCount = null;
      answer = '';
      questionError = null;
      lastUsage = null;
      isCountingQuestionTokens = false;
      retrievedChunks = [];
      // mode is deliberately NOT reset — like model selection, which mode
      // you're testing is a setup choice, not part of "start over with a
      // new file".
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Clear file, question and answer',
            onPressed: clearAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
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
                    setState(() {
                      currentModel = m;
                      selectedModel = m; // api_remote.dart's mutable global
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                const Text('mode  : ', style: TextStyle(fontSize: 18)),
                const Text('full context', style: TextStyle(fontSize: 13)),
                Switch(
                  value: mode == QueryMode.retrieval,
                  onChanged: (useRetrieval) {
                    setState(() {
                      mode = useRetrieval
                          ? QueryMode.retrieval
                          : QueryMode.fullContext;
                    });
                  },
                ),
                const Text('retrieval', style: TextStyle(fontSize: 13)),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                const Text('pick a doc  : ', style: TextStyle(fontSize: 18)),
                ElevatedButton(
                  onPressed: isPickingFile ? null : pickPdf,
                  child: const Text('File picker'),
                ),
                if (isPickingFile) ...[
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
                onSubmitted: (_) => askQuestion(),
                decoration: InputDecoration(
                  hint: Text('Ask about the file'),
                  suffixIcon: questionStatus == ApiStatus.streaming
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: askQuestion,
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
                            child: pickError != null
                                ? Text(
                                    pickError!,
                                    style: const TextStyle(fontSize: 14),
                                  )
                                : pickedFilePath == null
                                ? const Text(
                                    'No file picked yet',
                                    style: TextStyle(fontSize: 14),
                                  )
                                : Column(
                                    crossAxisAlignment: .start,
                                    children: [
                                      Text(
                                        'name: $pickedFileName\n'
                                        'size: $pickedFileBytes bytes '
                                        '(${(pickedFileBytes! / 1024).toStringAsFixed(1)} KB)\n'
                                        'path: $pickedFilePath\n'
                                        'Contents size : ${contents?.length}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      if (isCountingDocTokens)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
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
                                          'tokens: ${tokenCount ?? tokenCountError ?? '—'}'
                                          '${tokenCount != null ? '  (~\$${((tokenCount! / 1000000) * inputPricePerMillion).toStringAsFixed(4)} per question, input only)' : ''}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                      if (mode == QueryMode.retrieval) ...[
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
                              child: retrievedChunks.isEmpty
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
                                        for (final c in retrievedChunks)
                                          Padding(
                                            padding: const EdgeInsets.only(
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
                                  if (isCountingQuestionTokens)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
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
                                  else if (questionTokenCount != null)
                                    Text(
                                      'question+doc tokens: $questionTokenCount'
                                      '  (~\$${((questionTokenCount! / 1000000) * inputPricePerMillion).toStringAsFixed(4)} est. input)',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (questionStatus == ApiStatus.streaming &&
                                      answer.isEmpty &&
                                      !isCountingQuestionTokens)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
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
                                  if (questionError != null)
                                    Text(
                                      questionError!,
                                      style: const TextStyle(fontSize: 18),
                                    )
                                  else
                                    Text(
                                      answer,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  if (lastUsage != null)
                                    Text(
                                      'actual — input: ${lastUsage!.promptTokens} tok '
                                      '(\$${lastUsage!.inputCost.toStringAsFixed(4)}), '
                                      'output: ${lastUsage!.candidatesTokens} tok visible '
                                      '+ ${lastUsage!.thoughtsTokens} thinking '
                                      '(\$${lastUsage!.outputCost.toStringAsFixed(4)}), '
                                      'total: \$${lastUsage!.totalCost.toStringAsFixed(4)}',
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
      ),
    );
  }

  Future<void> askQuestion() async {
    final question = controller.text.trim();
    if (question.isEmpty || contents == null) return;

    setState(() {
      questionStatus = ApiStatus.streaming;
      questionTokenCount = null;
      questionError = null;
      answer = '';
      lastUsage = null;
      retrievedChunks = [];
      isCountingQuestionTokens = true;
    });

    final List<String> parts;
    if (mode == QueryMode.fullContext) {
      // Slice 2 behaviour, unchanged: whole document + question.
      parts = [contents!, question];
    } else {
      // Slice 3 behaviour: only the retrieved chunks + question. Currently
      // unimplemented — will throw until buildRetrievedParts is built.
      try {
        parts = await buildRetrievedParts(question);
      } catch (e) {
        setState(() {
          questionError = 'Retrieval mode not implemented yet: $e';
          questionStatus = ApiStatus.failed;
          isCountingQuestionTokens = false;
        });
        return;
      }
    }

    // Step 1: count tokens for document + question together, before
    // sending anything to generateContent.
    try {
      final count = await requestTokenCount(parts);
      setState(() => questionTokenCount = count);
    } on ApiException catch (e) {
      setState(() {
        questionError = e.userMessage;
        questionStatus = ApiStatus.failed;
      });
      return; // don't send if we couldn't even count tokens
    } finally {
      setState(() => isCountingQuestionTokens = false);
    }

    // Step 2: only on success of the count above, stream the answer.
    try {
      final buffer = StringBuffer();
      await for (final chunk in streamLlmApiResponse(
        parts,
        onUsage: (usage) => lastUsage = usage,
      )) {
        buffer.write(chunk);
        setState(() => answer = buffer.toString());
      }
      setState(() => questionStatus = ApiStatus.completed);
    } on ApiException catch (e) {
      setState(() {
        questionError = e.userMessage;
        questionStatus = ApiStatus.failed;
      });
    } on SocketException {
      setState(() {
        questionError = 'No connection';
        questionStatus = ApiStatus.failed;
      });
    }
  }

  Future<String> extractDocContent(String fileName) async {
    final PdfDocument document = PdfDocument(
      inputBytes: File(fileName).readAsBytesSync(),
    );
    //Extract the text from all the pages.
    String text = PdfTextExtractor(document).extractText();
    //Dispose the document.
    document.dispose();
    return text.isEmpty || text.length < 20 ? 'This is a scanned pdf' : text;
  }

  /// Slice 3 retrieval path. NOT IMPLEMENTED — this is the actual slice 3
  /// work: chunk [contents], embed each chunk once and persist it, embed
  /// the question, rank by cosine similarity, take the top k, and return
  /// those chunks as the "parts" to send instead of the whole document.
  ///
  /// TODO(you), in order (see slice-3-retrieval.md):
  /// 1. Chunking      — split contents into ~800-1000 char pieces with
  ///    ~100-200 char overlap.
  /// 2. Embeddings    — find Gemini's current embedding endpoint, batch-embed
  ///    all chunks once, persist locally (don't re-embed on every question).
  /// 3. Retrieval     — embed the question (one call), cosine-similarity
  ///    against every stored chunk vector, sort, take top-k (start k=5).
  /// 4. Return the top-k chunks' text as the "parts" list, and also return
  ///    their scores so retrievedChunks can be shown in the UI (the whole
  ///    point of item 3 in the definition of done).
  Future<List<String>> buildRetrievedParts(String question) async {
    throw UnimplementedError(
      'Slice 3 retrieval not built yet — implement chunking, embedding, '
      'and cosine-similarity ranking here.',
    );
  }
}

enum QueryMode { fullContext, retrieval }

/// One chunk retrieved for a question, with its similarity score — what the
/// UI shows under "retrieved chunks" so a wrong answer can be diagnosed as a
/// retrieval failure vs a generation failure.
class RetrievedChunk {
  final int index;
  final String text;
  final double score;
  RetrievedChunk({required this.index, required this.text, required this.score});
}
