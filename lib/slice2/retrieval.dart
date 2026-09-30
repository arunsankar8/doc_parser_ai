/// Slice 3's approach: chunk the document, embed each chunk once, and at
/// question time retrieve only the top-k most relevant chunks instead of
/// sending the whole document. See slice-docs/slice-3-retrieval.md.
///
/// NOT IMPLEMENTED YET — this file is the actual Slice 3 work. Build it in
/// order:
/// 1. Chunking    — chunkText() below: split into ~800-1000 char pieces
///    with ~100-200 char overlap.
/// 2. Embeddings  — find Gemini's current embedding endpoint, batch-embed
///    all chunks once, persist locally (don't re-embed on every question).
/// 3. Retrieval   — embed the question (one call), cosine-similarity
///    against every stored chunk vector, sort, take top-k (start k=5).
/// 4. buildRetrievedParts() ties it together: returns the top-k chunks'
///    text as the parts to send, plus the same chunks (with scores) so the
///    UI can show what was retrieved.

/// One chunk of a document, produced by chunkText(). Just text + position —
/// no similarity score yet, because a chunk isn't "relevant" or "irrelevant"
/// until it's compared against a specific question.
class DocChunk {
  final int index;
  final String text;
  DocChunk({required this.index, required this.text});
}

/// One chunk retrieved for a specific question, with its similarity score.
/// This is what the UI shows under "retrieved chunks" so a wrong answer can
/// be diagnosed as a retrieval failure (wrong chunks) vs a generation
/// failure (right chunks, model still got it wrong) — Slice 3 Step 3's
/// "show your work".
class RetrievedChunk {
  final int index;
  final String text;
  final double score;
  RetrievedChunk({
    required this.index,
    required this.text,
    required this.score,
  });
}

/// Step 1 — chunking. Splits [text] into fixed-size, overlapping pieces.
///
/// TODO(you): implement this. Advance through the string in steps of
/// (chunkSize - overlap), so consecutive chunks share their last [overlap]
/// characters with the next chunk's first [overlap] characters. Stop once
/// you reach the end of the string — don't produce empty trailing chunks.
List<DocChunk> chunkText(
  String text, {
  int chunkSize = 900,
  int overlap = 150,
}) {
  throw UnimplementedError('Slice 3 Step 1: implement chunkText.');
}

/// Step 3 — the actual retrieval call: chunk (or reuse persisted chunks),
/// embed the question, rank by cosine similarity, return the top-k as both
/// plain parts (for the generate request) and scored RetrievedChunks (for
/// the UI).
///
/// TODO(you): implement this once chunkText (Step 1) and the embedding
/// calls (Step 2) exist.
Future<({List<String> parts, List<RetrievedChunk> retrieved})>
buildRetrievedParts({
  required String documentText,
  required String question,
  int topK = 5,
}) async {
  throw UnimplementedError(
    'Slice 3 retrieval not built yet — implement chunking, embedding, '
    'and cosine-similarity ranking here.',
  );
}
