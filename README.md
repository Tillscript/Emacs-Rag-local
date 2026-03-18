# emacs-local-rag

> Local RAG (Retrieval-Augmented Generation) for Doom Emacs — semantic search over your Org notes, injected directly into GPTel.

No cloud. No external APIs for embeddings. Your notes stay on your machine.

----

## Origin

<img src="assets/profile.jpeg" align="right" width="120" />

I use [Doom Emacs](https://github.com/doomemacs/doomemacs) as my primary development environment and [org-roam](https://www.orgroam.com/) as my personal knowledge base — notes on projects, code snippets, study material, ideas, everything.

The problem: as the note graph grew, finding the right context before asking GPTel something became friction. I'd open a few files manually, copy relevant chunks, paste them into the prompt. Every single time.

So I built this.

**emacs-local-rag** turns my org-roam vault into a live, queryable knowledge base. When I ask GPTel something, the system automatically retrieves the most semantically relevant fragments from my own notes and injects them into the prompt — without me lifting a finger. The LLM gets my personal context. I get better answers.

The entire retrieval pipeline runs locally: no data leaves the machine, no API costs for embeddings, works offline. The Python subprocess stays out of the way; Emacs Lisp owns the workflow.

---

## How it works

```
.org files  ──►  chunker  ──►  Python embedder  ──►  in-memory vector index
                                                              │
                                              cosine similarity retrieval
                                                              │
                                              relevant chunks injected into GPTel context
```

The workflow is split across two layers:

**Emacs Lisp** owns the editor-side logic:
- Chunking `.org` files into retrievable fragments
- Storing and querying an in-memory vector index
- Computing cosine similarity between the query embedding and stored chunks
- Injecting the top-k results into a GPTel prompt as context
- Async inline editing / code rewrite workflow

**Python** handles the heavy lifting for embeddings:
- Generates local embeddings via [`sentence-transformers`](https://www.sbert.net/)
- Model: `all-MiniLM-L6-v2` (fast, lightweight, good quality for English and Portuguese)
- Runs as a subprocess called from Emacs

---

## Features

- **Fully local** — embeddings and retrieval run entirely on your machine
- **Org-native** — indexes your `.org` files directly, no conversion needed
- **Semantic search** — finds relevant notes by meaning, not just keywords
- **GPTel integration** — automatically prepends retrieved context before sending prompts
- **Top-k retrieval** — configurable number of chunks to inject
- **Async inline editing** — rewrite code or text blocks without leaving the buffer

---

## Requirements

| Dependency | Notes |
|---|---|
| Emacs 28+ | Tested on Doom Emacs |
| [GPTel](https://github.com/karthink/gptel) | For LLM prompt integration |
| Python 3.9+ | For the embedding subprocess |
| `sentence-transformers` | Local embedding model |

---

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/Tillscript/Emacs-Rag-local.git
cd Emacs-Rag-local
```

### 2. Set up the Python environment

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Load the Emacs Lisp

Add to your Doom Emacs config (`~/.config/doom/config.el`):

```emacs-lisp
(load! "/path/to/Emacs-Rag-local/elisp/rag.el")
```

Then set the path to the Python helper and your notes directory:

```emacs-lisp
(setq my/rag-python-script "/path/to/Emacs-Rag-local/python/embedder.py"
      my/rag-notes-dir     "~/org/")  ;; or your org-roam directory
```

### 4. Index your notes

```
M-x my/rag-index-notes
```

This scans your `.org` files, chunks them, and populates the in-memory vector index.

---

## Usage

### Semantic search

```
M-x my/rag-search
```

Enter a natural language query. The top-k most relevant chunks from your notes will be displayed.

### GPTel with context injection

```
M-x my/rag-gptel-with-context
```

Same as a normal GPTel prompt, but your query is first used to retrieve relevant note fragments, which are injected into the system context before the LLM sees your message.

### Inline edit / rewrite

Place point inside any code or prose block and call:

```
M-x my/rag-inline-edit
```

Sends the selected region plus retrieved context to the LLM and replaces the buffer content with the result — asynchronously.

---

## Example

Try the included example notes to test the system immediately:

### 1. Index the examples directory

```
M-x my/rag-index-notes
# select: examples/
```

### 2. Query with context injection

```
M-x my/rag-gptel-with-context
```

Try queries like:
- `"What is RAG and how does it work?"`
- `"How does semantic search work?"`
- `"What tools are used for local AI models?"`

The system will retrieve the most relevant chunks from the example notes and inject them into the GPTel prompt automatically.

---

## Project structure

```
Emacs-Rag-local/
├── elisp/
│   └── rag.el           # Core Emacs Lisp: chunking, index, retrieval, GPTel injection
├── python/
│   └── embedder.py      # sentence-transformers subprocess
├── examples/            # Example org files and demo workflows
│   ├── basic/           #   note1.org, note2.org, note3.org
│   ├── programming/     #   python.org, system-design.org, rag.org
│   └── personal-knowledge/ # ideas.org, startup.org, ai-notes.org
├── screenshots/         # UI screenshots
├── requirements.txt
└── README.md
```

---

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `my/rag-python-script` | `nil` | Path to `embedder.py` |
| `my/rag-notes-dir` | `"~/org/"` | Directory to index |
| `my/rag-top-k` | `3` | Number of chunks to retrieve |
| `my/rag-chunk-size` | `300` | Approximate chunk size in words |

---

## Why local embeddings?

- **Privacy** — your notes never leave your machine
- **Cost** — no API calls, no tokens consumed for retrieval
- **Speed** — `all-MiniLM-L6-v2` is fast enough to embed thousands of notes in seconds on CPU
- **Offline** — works without internet after the model is downloaded once

---

## Roadmap

- [ ] Persistent index (save/load from disk)
- [ ] Hybrid search (BM25 + semantic)
- [ ] Re-ranking with a cross-encoder
- [ ] `org-roam` node-aware chunking
- [ ] Android sync via Orgzly

---

## License

MIT — see [LICENSE](LICENSE).
