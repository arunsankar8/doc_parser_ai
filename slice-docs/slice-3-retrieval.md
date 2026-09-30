# Slice 3 — Retrieval

**Goal:** Stop sending the whole document. Split it into chunks, convert each to a vector, and at question time send only the handful of chunks that actually relate to the question.

This is the centre of the project. If you only ever finish one more slice, finish this one — it's the single most requested skill in AI engineering job postings.

**Not in this slice:** LangChain. LlamaIndex. Chroma. Pinecone. You are building this by hand, on purpose. Reasons at the bottom.

---

## Definition of done

1. A document is split into chunks and each chunk has an embedding stored locally.
2. Asking a question retrieves the top-k relevant chunks and sends only those.
3. The UI shows which chunks were retrieved, with their similarity scores.
4. You have the comparison table from slice 2, now done properly: same question, same document, full-context vs retrieved-context — input tokens, time to first token, cost, and whether the answer was correct.
5. You have found at least one question where retrieval returns the *wrong* chunks and the answer suffers as a result.

Item 5 again matters more than the code. Retrieval failure is the main reason real RAG systems disappoint, and you need to have seen it.

---

## The concept, minus the mystique

**An embedding is a list of numbers representing meaning.** You send text to an embedding model, it returns a fixed-length array of floats — often 768 or 1536 of them. Text with similar meaning produces arrays that point in similar directions.

"How do I cancel my order?" and "What's the refund process?" share almost no words, but their vectors land close together. That's the whole trick, and it's why this beats keyword search.

**Similarity is a dot product.** To compare two vectors you use cosine similarity: the dot product divided by the product of their magnitudes. Result is between -1 and 1; higher is more similar. If your embedding vectors are already normalized to unit length — most providers return them that way, check yours — cosine similarity is just the dot product, one multiply-accumulate loop.

**A vector database is an array plus that loop.** For a few thousand chunks, comparing the question vector against every chunk vector takes single-digit milliseconds in Dart. Purpose-built vector databases exist to make this fast at millions of vectors using approximate nearest-neighbour indexes. You do not have millions. Brute force is not a shortcut here — it's the correct engineering choice at your scale, and it will teach you what the databases are actually doing.

---

## Build order

### Step 1 — Chunking

Split the extracted text into pieces. Start naive and deliberately imperfect:

- Fixed size, roughly 800–1000 characters per chunk
- Overlap of roughly 100–200 characters between consecutive chunks

**Why overlap?** A sentence that straddles a chunk boundary is destroyed — half its meaning in each chunk, neither embedding representing it properly. Overlap means boundary-straddling content appears whole in at least one chunk. It costs storage and buys recall.

**Why this will be bad, and that's fine.** Fixed-size splitting cuts mid-sentence, mid-table, mid-list. Better strategies split on paragraph or section boundaries, or recursively on a hierarchy of separators. Build the naive version first so that when you improve it you can measure that the improvement is real.

Store each chunk with its index and its source page if you can get it — you'll want that for citations in slice 4.

**Done when:** you can display the chunk count and inspect any chunk by index.

### Step 2 — Embeddings

Gemini has embedding models — look up the current model name and endpoint in the docs rather than trusting a name from memory.

**Batch your requests.** There's a batch embedding endpoint that takes many texts in one call. Given your rate limit situation, this is not optional: a 50-page document might be 200 chunks, and 200 individual calls will get you throttled instantly. One batch call of 200 will not. This is your rate-limit problem turning into a design constraint, which is exactly how it works in production.

**Embed once, store forever.** Chunk embeddings never change unless the document changes. Compute them at ingest time, persist them, and never recompute. Only the question gets embedded at query time — one small call per question.

**Task types matter.** Most embedding APIs let you specify whether you're embedding a document or a query, and they produce slightly different vectors optimized for matching each other. Check whether Gemini's does and use it — it's free accuracy.

**Persistence:** store chunk text plus its vector locally. A `List<double>` per chunk in SQLite as a JSON string or binary blob works fine. Do not over-engineer this; you can swap in a real store later.

**Done when:** a document ingests, embeddings persist, and reopening the app doesn't re-embed.

### Step 3 — Retrieval

At question time:

1. Embed the question (one API call)
2. Compute cosine similarity against every stored chunk vector
3. Sort descending, take the top k — start with k=5
4. Send those chunks plus the question to the model

Write the similarity function yourself. It's about eight lines. Writing it is the point.

**Show your work in the UI.** Display the retrieved chunks and their scores above the answer. This is the single most valuable debugging affordance in the whole project — when an answer is wrong, you need to know instantly whether retrieval failed or generation failed. They're different bugs with different fixes.

**Done when:** answers are correct and you can see which chunks produced them.

### Step 4 — The comparison

The measurement you owe from slice 2, now done properly.

Pick one document and five questions. For each question, run it twice — once with the full document in context, once with retrieval. Record:

| question | mode | input tokens | TTFT | cost | correct? |
|---|---|---|---|---|---|

The token difference will be dramatic — often 50–100x. That number is your headline. It's also the answer to "why not just use the big context window", which you will be asked.

### Step 5 — Break it

Find questions where retrieval fails. Deliberately try:

- **Aggregation questions** — "how many times is X mentioned?", "summarize the whole document". Retrieval fundamentally cannot answer these; top-5 chunks is not the whole document. This is a real, known limitation, not your bug.
- **Vocabulary mismatch** — ask using words that don't appear in the document at all.
- **Multi-hop questions** — where the answer needs two facts from distant parts of the document.
- **Questions whose answer spans a chunk boundary.**
- **Exact identifiers** — a specific code, part number, or clause reference. Semantic similarity is poor at exact-match lookups, which is precisely why hybrid search (keyword + semantic) exists.

Write down every failure with the question, the retrieved chunks, and the wrong answer. These are slice 5's eval cases, and they're the honest content that makes a portfolio write-up credible.

---

## Why no framework

LangChain or LlamaIndex would do this slice in about thirty lines. You should know exactly what those thirty lines are hiding, for three reasons:

1. **Debugging.** When retrieval returns garbage, framework users are stuck reading source code to find out what chunking strategy and what similarity metric they got by default. You'll know, because you chose them.
2. **Interviews.** "I used LangChain" and "I implemented chunking with overlap, embedded with batch calls, and ranked by cosine similarity" are different answers.
3. **Mobile.** Most of these frameworks are Python-first. On Flutter you'd be writing this by hand regardless.

Read LangChain's concepts page *after* this slice. It'll be obvious rather than magical, and you'll be able to judge whether it's worth adopting.

---

## What comes after, so you know it exists — but don't build it now

Reranking, hybrid search, query rewriting, semantic chunking, metadata filtering. All real improvements. All pointless until you have measured that plain retrieval isn't good enough and know specifically how it fails. That's what step 5 is for.

---

## When you're done

Push it. The README should carry your comparison table and your retrieval failure cases. At that point you have a genuine portfolio piece — not "I called an API" but "I built retrieval from scratch, measured it against full-context, and documented where it breaks."
