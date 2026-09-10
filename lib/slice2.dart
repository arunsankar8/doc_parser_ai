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

  /// The PDF the user picked. Null until they pick one.
  String? pickedFilePath;
  String? pickedFileName;
  int? pickedFileBytes;
  String? pickError;
  String? contents;
  int? tokenCount;
  String? tokenCountError;

  /// State for asking a question about the picked document.
  ApiStatus questionStatus = ApiStatus.idle;
  int? questionTokenCount; // countTokens for [contents, question] combined
  String answer = '';
  String? questionError;
  UsageInfo? lastUsage; // actual usage, from the streamed response

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
      });

      // ignore: avoid_print

      // Count tokens for the extracted text. Kept as its own try/catch so a
      // token-count failure (e.g. rate limit) doesn't wipe out the file
      // details and extracted text you already have on screen.
      try {
        final count = await requestTokenCount([extracted]);
        setState(() => tokenCount = count);
      } on ApiException catch (e) {
        setState(() => tokenCountError = e.userMessage);
      }
      print(
        'Picked: $pickedFileName  ($bytes bytes) -- (${contents?.length})  -- tokenCount - $tokenCount',
      );
    } catch (e) {
      setState(() => pickError = 'File pick failed: $e');
    }
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
            Row(
              children: [
                const Text('pick a doc  : ', style: TextStyle(fontSize: 18)),
                ElevatedButton(
                  onPressed: pickPdf,
                  child: const Text('File picker'),
                ),
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
                  suffixIcon: IconButton(
                    onPressed: questionStatus == ApiStatus.streaming
                        ? null
                        : askQuestion,
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
                            child: Text(
                              pickError != null
                                  ? pickError!
                                  : pickedFilePath == null
                                  ? 'No file picked yet'
                                  : 'name: $pickedFileName\n'
                                        'size: $pickedFileBytes bytes '
                                        '(${(pickedFileBytes! / 1024).toStringAsFixed(1)} KB)\n'
                                        'path: $pickedFilePath\n'
                                        'tokens: ${tokenCount ?? tokenCountError ?? 'counting…'}'
                                        '${tokenCount != null ? '  (~\$${((tokenCount! / 1000000) * inputPricePerMillion).toStringAsFixed(4)} per question, input only)' : ''}\n'
                                        'Contents size : ${contents?.length}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
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
                                  if (questionTokenCount != null)
                                    Text(
                                      'question+doc tokens: $questionTokenCount'
                                      '  (~\$${((questionTokenCount! / 1000000) * inputPricePerMillion).toStringAsFixed(4)} est. input)',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
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
    });

    final parts = [contents!, question];

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
}
