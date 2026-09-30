# Learning notes — Slices 1 & 2

Personal reference. What each slice was *designed* to teach, and what I actually
hit while building it. Written before starting slice 3 so none of this gets lost.

---

## Slice 1 — Streaming text box

### What it was designed to teach
- Talking to an LLM API is not `http.post` + wait — the real skill is a
  **long-lived streaming connection** you parse incrementally.
- Server-Sent Events (SSE): `data: ` prefix, blank-line-separated events,
  ignore everything you don't need.
- `http.Client().send()` vs `http.post()` — `post()` buffers the whole body;
  `send()` gives you the stream as it arrives.
- The stream pipeline: raw bytes → `utf8.decoder` (stateful, handles
  multi-byte chars split across packets) → `LineSplitter` (buffers until a
  full line exists) → parse each `data:` line.
- `client.close()` belongs in `finally` — runs on every exit path (normal end,
  exception, or the listener cancelling), so the socket never leaks.
- Real error handling: bad key, no internet, rate limit, server error, a
  stream that just dies mid-response with **no exception at all** (the `await
  for` simply ends — you have to track whether you saw a real finish signal).
- Keys via `--dart-define`, never in source. Keeps it out of git, **not** out
  of the compiled binary — fine solo, not fine to distribute.
- BLoC/Cubit: emit a new state per chunk; ~50–200 rebuilds over a few seconds
  is fine for a `Text` widget — don't pre-optimise before you've measured a
  stutter.

### What I actually learned building it
- **Built against Gemini, not Claude** — no funds to spend on Claude yet.
  Confirmed the underlying skill transfers: SSE is SSE. What differs between
  providers is small — the endpoint, the auth header, and *one line*: where
  the text delta lives in the parsed JSON (Claude: `delta.text`; Gemini:
  `candidates[0].content.parts[0].text`).
- **Curl-tested the raw endpoint before writing any Dart.** A `curl` someone
  handed me turned out to hit a URL that doesn't exist (`/v1beta/interactions`
  — invented, not real Gemini API). Lesson: always verify against the
  provider's own docs or a working example before trusting a request shape,
  including one handed to me as "official."
- **`:generateContent` vs `:streamGenerateContent?alt=sse`** — these are two
  different verbs on the same model. `?alt=sse` alone does nothing if the verb
  is the non-streaming one. Both pieces have to be right.
- **`finishReason` is the success signal, not an error** — my first instinct
  was to `throw` when I saw it, which meant every clean completion looked
  like a thrown exception. Fixed by tracking a `bool`/`String?` flag and
  branching *after* the loop ends, not inside it. A dropped connection is the
  case with **no** `finishReason` ever seen — the loop just ends silently.
- **`currentValue` (accumulator) has to reset at the top of each request**, not
  only in a `finally` at the end — otherwise a failed request's leftover text
  bleeds into the next one, and concurrent taps can interleave writes to a
  shared field. Prefer a local accumulator per call over a shared mutable
  field.
- **`finally` is for cleanup only, not for emitting a "final" state** — I once
  put the success `emit()` inside `finally`, which meant it ran *after* the
  error-path `emit()` too, silently overwriting every error message with a
  blank "completed" state. Put success/failure emits at the actual end of
  each specific path, not in `finally`.
- **API-key leak, the hard way.** Put the key in `.vscode/launch.json` to make
  the IDE run button work — that file is tracked by git by default. Had to
  scrub it from git history (`git rm --cached`, orphan branch, `git gc
  --prune=now`) before the first push, and revoke the key regardless, since
  it had already been pasted around and sat in a local commit. Lesson locked
  in: `--dart-define` keeps a key out of *source*, but any file that holds
  the actual value at runtime (launch configs, `.env` files) needs its own
  gitignore entry, checked *before* the first commit, not after.
- **`file_picker`'s API changed across major versions** — the commonly-shown
  `FilePicker.platform.pickFiles()` pattern doesn't exist in v12; it's now a
  static `FilePicker.pickFile()` returning a single `PlatformFile?`. Another
  concrete case of "don't trust remembered API shapes, check the installed
  version's actual source."

---

## Slice 2 — Put a document in the prompt

### What it was designed to teach
- The naive approach — stuff the whole document into the prompt — actually
  *works* for small documents. Large context windows mean "it doesn't fit" is
  no longer the wall it was in 2023.
- The real walls are three **softer**, measured ones:
  1. **Cost** — pay per input token, on *every* question against that
     document, not once.
  2. **Latency** — the model reads the whole input before the first output
     token; a big document means a long blank pause even with streaming.
  3. **Accuracy** — models get *measurably* worse at finding one fact buried
     in a large context, and the failure is a **confident, plausible, wrong**
     answer — not an honest "I couldn't find it."
- Retrieval (RAG, slice 3) fixes all three by sending ~2,000 relevant tokens
  instead of the whole 300,000 — but the point of slice 2 is to *personally
  measure* the problem before being handed the solution.
- Tokens ≠ words ≠ bytes. Have to watch the real number, not guess it.
- PDF text extraction is not free or guaranteed: PDFs store positioned glyphs,
  not text — reading order is inferred. Scanned PDFs contain *no* text at
  all, only images (needs OCR, out of scope).
- Mobile-specific constraints server-side tutorials skip: a 300-page PDF as a
  Dart `String` is tens of MB in RAM on a phone; synchronous extraction
  blocks the UI thread (`compute()`/`Isolate` is the fix, only once you
  actually see the stutter).

### What I actually learned building it
- **File byte size is a poor proxy for token count, and I proved it on my own
  document.** A 1 MB PDF → 51,178 extracted characters → 13,820 tokens.
  Bytes-per-token ≈ 75; chars-per-token ≈ 3.7 (the expected English ratio).
  Roughly 95% of the file's bytes were fonts/structure/overhead, not
  extractable text. **Lesson: measure tokens from extracted text, never
  estimate from file size.**
- **`countTokens` and `generateContent` don't share an identical request
  schema.** Added `systemInstruction` to a shared request-builder and
  `countTokens` rejected it outright ("Unknown name... Cannot find field")
  even though the field is real and documented for `generateContent`. Had to
  split the body-building so `systemInstruction` is only sent on the actual
  generate call. Consequence: the pre-send token estimate will always run
  slightly *under* the real request once a system instruction is added,
  because the count never sees it.
- **Docs can be wrong about exact field casing — the server's error message is
  more authoritative than fetched documentation.** Google's own docs
  described `system_instruction`; the real field is `systemInstruction`
  (camelCase). Found via a live 400 error, not by reading harder.
- **`usageMetadata.thoughtsTokenCount` is a real, separate, billed-as-output
  field I almost missed entirely.** On one request: 7,790 prompt + 383
  visible output + 884 thinking = 9,057 total — and the 884 doesn't show up
  anywhere unless you read the *raw* JSON instead of trusting the two fields
  you expected to be there. My first cost calculation silently undercounted
  the real bill by ~30% because of this. Gemini's pricing page does say
  "output price, including thinking tokens" — but you only notice that
  matters once the arithmetic doesn't add up and you go looking.
- **Thinking-token overhead showed up even on trivial requests** — a 3-page
  poem question produced 430 thinking tokens against only 99 visible output
  tokens. Working hypothesis (untested at scale yet): thinking overhead may
  behave closer to a fixed per-request cost than something that scales with
  document size — worth checking once larger documents are testable again.
- **Free-tier rate limits are a real constraint on the measurement plan, not
  just an inconvenience.** Hit a 429 partway through testing across
  differently-sized documents — this itself is a legitimate finding: "the
  quota, not the context window, was the first hard wall I hit in practice"
  is worth keeping as a slice-2 note in its own right.
- **Synthetic filler text (lorem ipsum) is useless for this slice** — the
  accuracy test specifically needs *real, varied* content with one
  identifiable, checkable fact buried in it. Ended up sourcing real documents
  (a poem, a 17-page doc, ~200-page Moby Dick from Project Gutenberg) instead
  of generated filler.
- **State-management discipline carried over from slice 1 directly**: reset
  accumulators at the start of a request, not just in a `finally`; keep a
  request's token-count call and its generate call in *separate* try/catch
  blocks so a failure in one (e.g. token counting) doesn't wipe out data
  already successfully obtained (e.g. the extracted document text still on
  screen).

### Where slice 2 stands (as of writing this note)
Steps 1–4 done and tested: file pick, text extraction (incl. scanned-PDF
detection), pre-send token count + cost estimate, and the real send with
`systemInstruction` + streamed answer + actual post-response cost (including
thinking tokens). Step 5 (the actual measurement table + the buried-fact
accuracy test) is blocked on rate limits and needs a fresh quota window to
finish — poem-scale data exists, medium (17pg) and large (Moby Dick) still
outstanding.

### The open question to answer before/while reading slice 3
*What would I have to build so that asking a question about the 300-page
document cost the same as asking about the 5-page one?*

Working answer so far: don't send the whole document — send only the part of
it that's actually relevant to the question. That means some way to find the
relevant piece *before* calling the model at all (search over the document's
content rather than reading all of it) — which is, near enough, what RAG is.
