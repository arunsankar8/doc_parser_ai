import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

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

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> pickPdf() async {
    setState(() => pickError = null);
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
      contents = await extractDocContent(path);
      setState(() {
        pickedFilePath = path;
        pickedFileName = file.name;
        pickedFileBytes = bytes;
      });

      // ignore: avoid_print
      print('Picked: $path  ($bytes bytes)');
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
                decoration: InputDecoration(
                  hint: Text('Ask about the file'),
                  suffixIcon: IconButton(
                    onPressed: () {},

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
                                        'Contents : $contents',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 5),
                      Row(
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
                              child: Column(
                                crossAxisAlignment: .start,
                                children: [
                                  Text("", style: TextStyle(fontSize: 18)),
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
