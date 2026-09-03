# Slice 1 — Streaming text box

**Goal:** A Flutter app with one text field and one output area. You type a question, hit send, and Claude's answer appears word by word. Failures show a readable message instead of a crash.

**Not in this slice:** PDFs. Chat history. Saved conversations. Markdown rendering. Nice UI. A backend. Do not add them.

---

## Definition of done

Tick all five or the slice isn't finished:

1. Text appears incrementally, not in one blob at the end.
2. Send button disables while a request is in flight.
3. A bad API key shows "Invalid API key", not a red screen.
4. Airplane mode shows "No connection", not a red screen.
5. It's installed on your actual phone and you've used it at least once for something real.

---

## Why streaming is the whole point

A non-streaming call is `http.post`, wait 8 seconds, get a string. You already know how to do that. It teaches you nothing.

Streaming is different because the response arrives as a long-lived HTTP connection that dribbles out chunks over several seconds. You have to parse a protocol, update UI on every chunk, and handle the connection dying halfway through. Every serious LLM feature works this way. This is the skill.

---

## The protocol: Server-Sent Events (SSE)

When you send `"stream": true`, the API keeps the connection open and pushes text lines at you. The format is dead simple — lines look like:

```
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

event: message_stop
data: {"type":"message_stop"}
```

Rules you need to know:

- Every payload line starts with `data: ` — strip that prefix, then `jsonDecode` the rest.
- Blank lines separate events. Ignore them.
- Lines starting with `event: ` are a type hint. You can ignore these too — the JSON in `data:` already has a `type` field.
- You only care about `content_block_delta`. That's where the text is: `json['delta']['text']`.
- Everything else (`message_start`, `content_block_start`, `ping`, `message_delta`, `message_stop`) you can skip for now. `ping` exists to keep the connection alive on slow generations.

---

## The request

```
POST https://api.anthropic.com/v1/messages
```

**Headers:**

| Header | Value | What it does |
|---|---|---|
| `x-api-key` | your key | Auth. Not a Bearer token — this API uses its own header. |
| `anthropic-version` | `2023-06-01` | Pins the API schema. Without it you get a 400. It is not a date you update. |
| `content-type` | `application/json` | Standard. |

**Body:**

```json
{
  "model": "claude-sonnet-5",
  "max_tokens": 1024,
  "stream": true,
  "messages": [
    { "role": "user", "content": "your text here" }
  ]
}
```

`max_tokens` is a hard ceiling on the *response* length, not the input. If the model hits it, the response just stops mid-sentence — it isn't an error. 1024 is fine for slice 1.

`messages` is a list because multi-turn conversations are just the whole history replayed each time. There's no server-side session. Slice 1 sends a list of one.

---

## Setup commands

```bash
flutter create llmbox
cd llmbox
flutter pub add http
```

`flutter pub add http` writes the dependency into `pubspec.yaml` and runs `pub get` in one step, instead of you hand-editing the YAML and getting the indentation wrong.

**Android only** — open `android/app/src/main/AndroidManifest.xml` and add inside `<manifest>`, above `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Release builds strip network access without this. Debug builds have it implicitly, so you'll ship a release build that mysteriously does nothing. Classic two-hour bug.

**iOS:** nothing to do. Outbound HTTPS is allowed by default.

---

## Handling the API key

Do **not** paste the key into your Dart source. You'll commit it eventually, everyone does.

For slice 1, pass it at launch:

```bash
flutter run --dart-define=ANTHROPIC_KEY=sk-ant-xxxxx
```

Read it in Dart:

```dart
const apiKey = String.fromEnvironment('ANTHROPIC_KEY');
```

`--dart-define` injects a compile-time constant into the build. `String.fromEnvironment` reads it. If the key is missing it returns an empty string, not null — so check `apiKey.isEmpty` and fail loudly at startup.

**Be clear-eyed about this:** `--dart-define` keeps the key out of git. It does *not* keep it out of the compiled binary — anyone can extract it from an APK. That's fine for a build only you install. The moment you hand this to someone else, the key has to move behind a server you control, and the app calls your server instead. That's a slice 3+ problem. Don't build it now.

---

## The streaming call

The `http` package's `post()` buffers the entire response before returning it — useless here. You need `Client().send()`, which gives you a `StreamedResponse` you can read as it arrives.

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Stream<String> streamCompletion(String prompt) async* {
  final client = http.Client();
  try {
    final request = http.Request(
      'POST',
      Uri.parse('https://api.anthropic.com/v1/messages'),
    );
    request.headers.addAll({
      'x-api-key': const String.fromEnvironment('ANTHROPIC_KEY'),
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    });
    request.body = jsonEncode({
      'model': 'claude-sonnet-5',
      'max_tokens': 1024,
      'stream': true,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
    });

    final response = await client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, body);
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final payload = line.substring(6);

      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json['type'] == 'content_block_delta') {
        yield json['delta']['text'] as String;
      }
    }
  } finally {
    client.close();
  }
}
```

Things worth understanding rather than copying:

- **`async*` / `yield`** makes this function return a `Stream<String>`. Each `yield` pushes one chunk to whoever is listening. You've used this shape before if you've written a `Stream` in BLoC.
- **`.transform(utf8.decoder)`** turns raw bytes into text. Do not use `utf8.decode()` on individual chunks — a multi-byte character (an em-dash, an emoji) can be split across two network packets and you'll get garbage or a crash. The decoder is stateful and handles the split correctly. This bug is subtle and everyone hits it once.
- **`.transform(LineSplitter())`** buffers until it sees a newline, so you always get complete lines. Network chunks don't respect line boundaries.
- **`client.close()` in `finally`** — without it you leak a socket every request.
- **Error body handling:** on a non-200 you must drain `response.stream` to read the error JSON. If you throw without reading it, the connection hangs.

---

## Errors you will actually hit

| Status | Meaning | What to do |
|---|---|---|
| 401 | Bad or missing API key | Show "Invalid API key". Not retryable. |
| 400 | Malformed request | Read `error.message` in the body — it's usually specific. Not retryable. |
| 429 | Rate limited | Retry after a short delay. |
| 500 / 529 | Server error / overloaded | Retry with backoff. |
| — | `SocketException` | No internet. Catch separately. |
| — | `TimeoutException` | Wrap the call in `.timeout(Duration(seconds: 60))`. |

Minimum viable error class:

```dart
class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  String get userMessage => switch (statusCode) {
    401 => 'Invalid API key',
    429 => 'Rate limited — try again in a moment',
    >= 500 => 'Service unavailable — try again',
    _ => 'Something went wrong ($statusCode)',
  };
}
```

One more failure mode people forget: **the stream dies mid-response.** The connection drops at 60% and `await for` just... ends. No exception. Your UI shows a truncated answer and looks fine. For slice 1, track whether you ever saw a `message_stop` event; if not, append "[incomplete]". That's enough.

---

## State management

Use BLoC. You already know it, and the point of this slice is the API, not learning a new pattern. Three states is plenty:

- `Idle` — empty or showing a finished answer
- `Streaming(String textSoFar)` — emit a new state on every chunk, appending
- `Failed(String message)`

The one thing to get right: emitting a state per chunk means ~50–200 rebuilds over a few seconds. That's fine for a `Text` widget. If it stutters, buffer chunks and emit every 50ms instead — but measure first, don't pre-optimise.

`setState` in a `StatefulWidget` works identically here and is about 30 lines shorter. Either is defensible. Pick in 60 seconds and move on.

---

## Suggested order

1. Hardcode a prompt, no UI, print chunks to console. Confirms auth + parsing.
2. Add the text field and send button.
3. Wire streaming into the UI.
4. Break it deliberately: wrong key, airplane mode, `max_tokens: 5`. Fix each.
5. Release build, install on your phone, use it.

Step 4 is where the actual learning is. Do not skip it.

---

## When you're done

Come back and say "slice 1 is on my phone." Then we open slice 2.
