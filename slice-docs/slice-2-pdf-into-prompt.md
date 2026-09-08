# Slice 2 — Put a document in the prompt

**Goal:** Pick a PDF, pull its text out, send it along with your question, get an answer about that document. Then measure what that cost you in tokens, money, and seconds.

**Not in this slice:** Embeddings. Vector databases. Chunking strategies. Similarity search. Citations. You will *want* to add these by the end — that wanting is the point, and it's slice 3.

---

## Definition of done

1. You can pick a PDF from the device and see its extracted text length (characters and tokens).
2. Asking a question about a small PDF returns a correct answer.
3. You have measured, for at least three documents of very different sizes: token count, response latency, and estimated cost per question.
4. You have found and written down at least one case where the big-document answer is *worse* than the small-document answer.
5. Still on your phone. Still no crashes.

Item 4 is the real deliverable. Items 1–3 are how you get there.

---

## Why this slice exists

The naive approach is "stuff the whole document in the prompt." For small documents it works perfectly, and you should see that work.

The lesson is what happens as the document grows. Older material will tell you the document won't fit — that context windows are small and you'll hit a hard wall. That was true in 2023. Current models have very large context windows, so a 200-page PDF often *does* fit.

So the wall you hit isn't "it doesn't fit." It's three softer walls, and they're the actual reason RAG exists in 2026:

1. **Cost.** You pay per input token, every single question. Send 300k tokens of context to ask "what's the payment schedule?" and you pay for 300k tokens to get a 30-token answer. Ask ten questions, pay ten times.
2. **Latency.** The model has to process the whole input before it emits the first token. Your beautiful streaming UI sits blank for several seconds.
3. **Accuracy.** Models get measurably worse at finding a specific fact buried in a huge context, especially when it's in the middle. The failure mode is subtle — you get a confident, wrong, plausible answer rather than "I couldn't find it."

Retrieval fixes all three by sending only the relevant 2,000 tokens instead of all 300,000. But you'll only believe that — and be able to explain it in an interview — if you've measured the problem yourself.

---

## Build order

### Step 1 — Pick a file

`file_picker` is the standard package.

```bash
flutter pub add file_picker
```

Restrict to PDFs with `FileType.custom` and `allowedExtensions: ['pdf']`. On Android, check what permissions the package version needs — this has changed several times across Android versions and is a common source of "works in debug, silently fails on device."

**Done when:** you can pick a file and print its path and byte size.

### Step 2 — Extract text

PDF text extraction in Dart is not trivial — a PDF is a page-description format, not a text format. Text is stored as positioned glyph runs, so "reading order" is inferred, not stored.

The practical option is `syncfusion_flutter_pdf`, which has a `PdfTextExtractor` class. Check its current licence terms before you commit to it — Syncfusion has a community licence with revenue and headcount conditions, and you should know whether your use qualifies. That habit matters more than the package choice.

**Test it on a scanned PDF.** You'll get back nothing, or garbage. That's not a bug — a scanned page is an image, and getting text out needs OCR, which is a different tool entirely. Handle it: if extraction returns near-empty text, tell the user the document appears to be scanned. This is real production behaviour and most tutorials skip it.

**Done when:** you can display the first 500 characters of extracted text in the UI.

### Step 3 — Count tokens before you send

Do not skip this. Guessing at token counts is how people get surprise bills.

Gemini exposes a `countTokens` endpoint on the model — check the current API docs for the exact path and request shape rather than trusting anything I write here. It takes the same `contents` structure as your generate call.

Show the count in your UI before the send button is pressed. Then find the pricing page for the model you're using and compute the cost per question. Display that too.

Two things you'll learn immediately:

- Tokens are not words. English runs roughly 3–4 characters per token, but code, tables, and non-English text are much denser. Your intuition will be wrong until you've watched the number.
- A "small" 40-page spec document is bigger than you think.

**Done when:** your UI shows token count and estimated cost before sending.

### Step 4 — Send it

Structurally trivial — one text part with the document, one with the question:

```
contents: [{ parts: [
  { text: "Here is a document:\n\n<document text>" },
  { text: "Question: <user question>" }
] }]
```

Two things worth doing properly:

- **Add a system instruction** telling the model to answer only from the provided document and to say so when the answer isn't there. Gemini takes this as `system_instruction` at the top level of the request body, not inside `contents`. Without it, the model will happily answer from its own general knowledge and you won't be able to tell the difference.
- **Log the response metadata.** The API returns usage figures (prompt tokens, output tokens) with the response. Log them and compare against your pre-send estimate.

**Done when:** correct answers about a small PDF.

### Step 5 — Measure, and break it

This is the actual slice. Do it deliberately, write results in `notes.md`.

Take three documents: something short (5 pages), something medium (50), something large (300+). For each, record:

| | tokens | time to first token | total time | cost/question |
|---|---|---|---|---|

Then the accuracy test. Take a specific, verifiable fact that appears exactly once in the large document — a date, a number, a clause reference. Put it near the middle. Ask for it. Then put the *same fact* in a 2-page extract and ask the same question.

Compare the answers. Ask it five different ways. Look for:

- confident wrong answers
- the model answering from general knowledge instead of the document
- the model missing something that's plainly there
- inconsistent answers to the same question asked twice

**Write down every failure you find, with the exact question and the exact wrong answer.** These become your eval test cases in slice 5, and they're the most useful thing you'll produce in this slice.

---

## Predictable problems

- **Memory.** A 300-page PDF extracted to a String is tens of megabytes in memory, and you're on a phone. Watch for jank or OOM. This is a genuine mobile-specific constraint that server-side tutorials never mention — and it's your on-device edge showing up early.
- **UI freeze during extraction.** Text extraction is synchronous CPU work and will block the UI thread. If it stutters, that's what `Isolate` / `compute()` is for. Don't reach for it until you see the stutter.
- **Encoding artifacts.** Ligatures, hyphenation across line breaks, headers and footers repeated on every page, multi-column layouts read in the wrong order. Look at your extracted text properly — don't just check that it's non-empty.
- **Token limits on output.** Long answers get cut. You already handle `MAX_TOKENS` from slice 1.

---

## The question to sit with

When you've measured all three documents, ask yourself: what would you have to build so that asking a question about the 300-page document cost the same as asking about the 5-page one?

Work out your own answer before reading slice 3. Whatever you come up with will be close to what RAG actually is, and understanding it as a solution to a problem you personally measured is worth more than any tutorial.

---

## When you're done

Push it. Update the README with your measurement table and the failure cases you found. That table is a better portfolio artifact than the code.
