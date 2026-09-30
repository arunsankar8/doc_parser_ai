/// Slice 2's approach: send the whole document as context on every question.
/// Kept here, isolated, so it stays easy to compare against retrieval.dart's
/// approach via the mode switch in slice2.dart.

/// Builds the request parts for full-context mode: the entire document
/// text, then the question, as two separate content parts.
List<String> buildFullContextParts({
  required String documentText,
  required String question,
}) {
  return [documentText, question];
}
