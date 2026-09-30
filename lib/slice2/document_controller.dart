import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../remote/api_remote.dart';
import 'full_context.dart';
import 'retrieval.dart';

enum QueryMode { fullContext, retrieval }

/// Sentinel used by copyWith to distinguish "leave this field alone" from
/// "set this field to null" — a plain `T? field` parameter can't tell those
/// apart, since "not passed" and "passed null" both look like null. Every
/// nullable copyWith parameter below defaults to this and is only treated
/// as "clear it" when the caller passes an explicit `null`.
const _unset = Object();

/// Everything slice2.dart used to hold as loose State fields, now in one
/// immutable snapshot. DocumentCubit emits a new one on every change;
/// slice2.dart just reads it and renders — same shape as Slice 1's
/// AiCubit/AICubitState, applied to a bigger screen.
class DocumentState {
  // Picked file.
  final String? pickedFilePath;
  final String? pickedFileName;
  final int? pickedFileBytes;
  final String? pickError;
  final String? contents;
  final bool isPickingFile;

  // Document-only token count (shown right after picking).
  final int? tokenCount;
  final String? tokenCountError;
  final bool isCountingDocTokens;

  // The question/answer round.
  final ApiStatus questionStatus;
  final int? questionTokenCount;
  final String answer;
  final String? questionError;
  final UsageInfo? lastUsage;
  final bool isCountingQuestionTokens;

  // Slice 2 vs Slice 3 mode, and what retrieval mode found.
  final QueryMode mode;
  final List<RetrievedChunk> retrievedChunks;

  const DocumentState({
    this.pickedFilePath,
    this.pickedFileName,
    this.pickedFileBytes,
    this.pickError,
    this.contents,
    this.isPickingFile = false,
    this.tokenCount,
    this.tokenCountError,
    this.isCountingDocTokens = false,
    this.questionStatus = ApiStatus.idle,
    this.questionTokenCount,
    this.answer = '',
    this.questionError,
    this.lastUsage,
    this.isCountingQuestionTokens = false,
    this.mode = QueryMode.fullContext,
    this.retrievedChunks = const [],
  });

  /// Returns a copy with the given fields replaced. Every nullable
  /// parameter defaults to the [_unset] sentinel, not null — so "don't pass
  /// pickError at all" (keep the current value) and "pass pickError: null"
  /// (actually clear it) are distinguishable. Non-nullable fields
  /// (isPickingFile, answer, mode, retrievedChunks, ...) don't need this;
  /// they can't legally be null in the first place.
  DocumentState copyWith({
    Object? pickedFilePath = _unset,
    Object? pickedFileName = _unset,
    Object? pickedFileBytes = _unset,
    Object? pickError = _unset,
    Object? contents = _unset,
    bool? isPickingFile,
    Object? tokenCount = _unset,
    Object? tokenCountError = _unset,
    bool? isCountingDocTokens,
    ApiStatus? questionStatus,
    Object? questionTokenCount = _unset,
    String? answer,
    Object? questionError = _unset,
    Object? lastUsage = _unset,
    bool? isCountingQuestionTokens,
    QueryMode? mode,
    List<RetrievedChunk>? retrievedChunks,
  }) {
    return DocumentState(
      pickedFilePath: identical(pickedFilePath, _unset)
          ? this.pickedFilePath
          : pickedFilePath as String?,
      pickedFileName: identical(pickedFileName, _unset)
          ? this.pickedFileName
          : pickedFileName as String?,
      pickedFileBytes: identical(pickedFileBytes, _unset)
          ? this.pickedFileBytes
          : pickedFileBytes as int?,
      pickError: identical(pickError, _unset)
          ? this.pickError
          : pickError as String?,
      contents: identical(contents, _unset)
          ? this.contents
          : contents as String?,
      isPickingFile: isPickingFile ?? this.isPickingFile,
      tokenCount: identical(tokenCount, _unset)
          ? this.tokenCount
          : tokenCount as int?,
      tokenCountError: identical(tokenCountError, _unset)
          ? this.tokenCountError
          : tokenCountError as String?,
      isCountingDocTokens: isCountingDocTokens ?? this.isCountingDocTokens,
      questionStatus: questionStatus ?? this.questionStatus,
      questionTokenCount: identical(questionTokenCount, _unset)
          ? this.questionTokenCount
          : questionTokenCount as int?,
      answer: answer ?? this.answer,
      questionError: identical(questionError, _unset)
          ? this.questionError
          : questionError as String?,
      lastUsage: identical(lastUsage, _unset)
          ? this.lastUsage
          : lastUsage as UsageInfo?,
      isCountingQuestionTokens:
          isCountingQuestionTokens ?? this.isCountingQuestionTokens,
      mode: mode ?? this.mode,
      retrievedChunks: retrievedChunks ?? this.retrievedChunks,
    );
  }
}

class DocumentCubit extends Cubit<DocumentState> {
  DocumentCubit() : super(const DocumentState());

  Future<void> pickPdf() async {
    // A fresh pick starts clean: clear the previous file's error/tokens
    // rather than carrying them forward. copyWith with explicit nulls
    // handles this correctly now (see the _unset sentinel above).
    emit(
      state.copyWith(
        pickError: null,
        tokenCount: null,
        tokenCountError: null,
        isPickingFile: true,
      ),
    );
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      // User dismissed the picker without choosing anything.
      if (file == null) {
        emit(state.copyWith(isPickingFile: false));
        return;
      }

      final path = file.path;
      if (path == null) {
        emit(
          state.copyWith(
            pickError: 'Could not read the file path.',
            isPickingFile: false,
          ),
        );
        return;
      }

      final bytes = await file.length();
      final extracted = await extractDocContent(path);
      emit(
        state.copyWith(
          pickedFilePath: path,
          pickedFileName: file.name,
          pickedFileBytes: bytes,
          contents: extracted,
          isPickingFile: false,
          isCountingDocTokens: true,
        ),
      );

      // Count tokens for the extracted text. Kept as its own try/catch so a
      // token-count failure (e.g. rate limit) doesn't wipe out the file
      // details and extracted text already emitted above.
      try {
        final count = await requestTokenCount([extracted]);
        emit(state.copyWith(tokenCount: count));
      } on ApiException catch (e) {
        emit(state.copyWith(tokenCountError: e.userMessage));
      } finally {
        emit(state.copyWith(isCountingDocTokens: false));
      }
    } catch (e) {
      emit(
        state.copyWith(pickError: 'File pick failed: $e', isPickingFile: false),
      );
    }
  }

  void setMode(QueryMode mode) {
    emit(state.copyWith(mode: mode));
  }

  /// Resets everything for a fresh document + question. mode is preserved
  /// deliberately — like model selection, which mode you're testing is a
  /// setup choice, not part of "start over with a new file".
  void clearAll() {
    emit(DocumentState(mode: state.mode));
  }

  Future<void> askQuestion(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || state.contents == null) return;

    emit(
      state.copyWith(
        questionStatus: ApiStatus.streaming,
        questionTokenCount: null,
        questionError: null,
        answer: '',
        lastUsage: null,
        retrievedChunks: const [],
        isCountingQuestionTokens: true,
      ),
    );

    final List<String> parts;
    if (state.mode == QueryMode.fullContext) {
      parts = buildFullContextParts(
        documentText: state.contents!,
        question: trimmed,
      );
    } else {
      // Slice 3 behaviour: only the retrieved chunks + question. Currently
      // unimplemented — will throw until retrieval.dart's
      // buildRetrievedParts is built.
      try {
        final result = await buildRetrievedParts(
          documentText: state.contents!,
          question: trimmed,
        );
        parts = result.parts;
        emit(state.copyWith(retrievedChunks: result.retrieved));
      } catch (e) {
        emit(
          state.copyWith(
            questionError: 'Retrieval mode not implemented yet: $e',
            questionStatus: ApiStatus.failed,
            isCountingQuestionTokens: false,
          ),
        );
        return;
      }
    }

    // Step 1: count tokens for document + question together, before
    // sending anything to generateContent.
    try {
      final count = await requestTokenCount(parts);
      emit(state.copyWith(questionTokenCount: count));
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          questionError: e.userMessage,
          questionStatus: ApiStatus.failed,
        ),
      );
      return; // don't send if we couldn't even count tokens
    } finally {
      emit(state.copyWith(isCountingQuestionTokens: false));
    }

    // Step 2: only on success of the count above, stream the answer.
    try {
      final buffer = StringBuffer();
      await for (final chunk in streamLlmApiResponse(
        parts,
        onUsage: (usage) => emit(state.copyWith(lastUsage: usage)),
      )) {
        buffer.write(chunk);
        emit(state.copyWith(answer: buffer.toString()));
      }
      emit(state.copyWith(questionStatus: ApiStatus.completed));
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          questionError: e.userMessage,
          questionStatus: ApiStatus.failed,
        ),
      );
    } on SocketException {
      emit(
        state.copyWith(
          questionError: 'No connection',
          questionStatus: ApiStatus.failed,
        ),
      );
    }
  }

  Future<String> extractDocContent(String fileName) async {
    final PdfDocument document = PdfDocument(
      inputBytes: File(fileName).readAsBytesSync(),
    );
    // Extract the text from all the pages.
    String text = PdfTextExtractor(document).extractText();
    // Dispose the document.
    document.dispose();
    return text.isEmpty || text.length < 20 ? 'This is a scanned pdf' : text;
  }
}
