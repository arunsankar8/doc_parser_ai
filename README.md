# doc_parser

A Flutter learning project built slice by slice on the AI Engineer path. Each slice
adds one vertical capability and is only "done" when it runs on a real device.

---

## Slice 1 — Streaming text box

**Goal:** one text field, one output area. Type a question, hit send, the answer
streams in word by word. Failures show a readable message, never a red screen.

Built against the **Gemini API** (free tier) instead of Claude for cost reasons.
The streaming protocol (SSE) is nearly identical between providers, so the skill
transfers — only the endpoint, the auth header, and the JSON path to the text
delta differ.

### What it does

- Sends `POST .../models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse`
- Reads the response as a live stream via `http.Client().send()` (not `http.post`,
  which buffers the whole body and defeats streaming)
- Parses Server-Sent Events line by line and appends each text delta to the UI
- Handles the failure modes below without crashing

### How the streaming works

1. `client.send(request)` returns a `StreamedResponse` as soon as the response
   **headers** arrive — the body is still downloading.
2. `response.stream` is a `Stream<List<int>>` of raw byte chunks off the socket.
3. `.transform(utf8.decoder)` → `Stream<String>`. The decoder is **stateful**, so a
   multi-byte character split across two network packets is reassembled correctly
   instead of producing garbage.
4. `.transform(LineSplitter())` buffers until it sees a newline, so downstream we
   always get complete lines even though network chunks don't respect line
   boundaries.
5. `.timeout(30s)` fires `TimeoutException` if 30s pass **between chunks** (stalled
   connection), which is the right granularity for a stream.
6. For each line: skip anything not starting with `data: `, strip the prefix,
   `jsonDecode` the rest, pull the text from
   `candidates[0].content.parts[0].text`, and `yield` it.
7. `client.close()` in a `finally` block runs on every exit path (normal end,
   exception, or the listener cancelling) so the socket is never leaked.

### Detecting a broken stream

Gemini sends a `finishReason` on its final event:

- `STOP` — clean finish, show nothing extra
- `MAX_TOKENS` / `SAFETY` / etc. — answer was cut short; the text is still shown
  plus a `[ Stopped : <reason> ]` marker
- **no `finishReason` ever seen** — the connection dropped mid-response (which
  throws no exception, the loop just ends); a `[ Connection Dropped ]` marker is
  appended

### State management (BLoC / Cubit)

`AiCubit` emits an `AIResponseState` carrying `text`, `error`, and an `ApiStatus`
(`idle` / `streaming` / `failed` / `completed`):

- one `emit` per chunk with the full accumulated string → the `Text` widget
  rebuilds ~50–200 times over a couple of seconds (fine for a single `Text`)
- the send button is disabled whenever `status == streaming` (`onPressed: null`),
  re-enabled on every terminal state

### Error handling

| Failure | Handling |
|---|---|
| Missing API key (`--dart-define` not set) | checked at request start, fails loudly |
| Bad API key | non-200 → `ApiException` → "Invalid API key" |
| Rate limited (429) | "Rate limited — try again in a moment" |
| Server error (5xx) | "Service unavailable — try again" |
| No internet (airplane mode) | `SocketException` / `ClientException` → "No connection" |
| Stalled connection | `TimeoutException` → "TimedOut" |

The non-200 branch drains `response.stream` before throwing — an unread error
body leaves the connection hanging.

### API key handling

The key is passed at launch, never committed:

```bash
flutter run --dart-define=GEMINI_KEY=your_key_here
```

Read in Dart with `String.fromEnvironment('GEMINI_KEY')`. This keeps the key out
of git but **not** out of the compiled binary — fine for a build only I install,
not for distribution. `.vscode/launch.json` (which holds the key locally for the
IDE run button) is gitignored.

### Definition of done

- [x] Text appears incrementally, not in one blob
- [x] Send button disables while a request is in flight
- [x] Bad API key shows "Invalid API key", not a red screen
- [x] Airplane mode shows "No connection", not a red screen
- [x] Installed on a real phone and used at least once for something real

---

## Getting Started

```bash
flutter pub get
flutter run --dart-define=GEMINI_KEY=your_key_here
```
