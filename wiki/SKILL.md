---
name: wiki
description: Read, write, and maintain the personal knowledge wiki at ~/Documents/MyProjects/wiki/. Use when the user wants to ingest a source (file, URL, or pasted text) into the wiki, query the wiki to answer a question, audit/lint the wiki for health issues, or asks to "save this to the wiki", "what does my wiki say about X", or runs /wiki-ingest, /wiki-query, or /wiki-lint.
metadata:
  short-description: Ingest, query, and lint the personal wiki
---

# Wiki

Operates the personal knowledge base at `~/Documents/MyProjects/wiki/`.

## Always first

Read `~/Documents/MyProjects/wiki/CLAUDE.md` (or `AGENTS.md`, which points to it) and
`~/Documents/MyProjects/wiki/SCHEMA.md` before any read or write. They hold the read order,
search commands, naming conventions, frontmatter contract, and the hard rules for editing.
Never invent conventions — SCHEMA.md wins.

## Layout

| Path | Contents |
|---|---|
| `index.md` | Catalog of every page, grouped by category. The entry point. |
| `pages/` | The wiki pages themselves, one topic per file. |
| `raw/` | Verbatim saved sources. `raw/assets/` holds images. |
| `log.md` | Append-only activity log. Every operation appends an entry. |
| `SCHEMA.md` | Conventions: naming, frontmatter, linking, categories. |

## Pick the operation

| The user wants | Load and follow |
|---|---|
| Add a source (file / URL / pasted text) to the wiki | `references/ingest.md` |
| An answer synthesized from the wiki | `references/query.md` |
| A health audit of the wiki | `references/lint.md` |

Load the matching reference file in full before acting. Do not work from this page alone.

## Hard rules

- Every operation appends a dated entry to `log.md`. No silent writes.
- New or renamed pages must be reflected in `index.md` in the same turn.
- Cross-link with `[[category/page-name]]`; images point at `raw/assets/`.
- `lint` reports only — it never auto-fixes without the user picking the fixes.
- `raw/` and `log.md` are append-only. Never edit a saved source or rewrite a past entry.
- No `tags:` in frontmatter — removed 2026-08-22. Links and `index.md` are the retrieval path.
- Search with `qmd search "keywords"` first (fast BM25); `qmd query "question"` for hybrid+rerank.
- Reindex with `make reindex` (= `qmd update` then `qmd embed`). `qmd embed` alone will NOT
  pick up new files. Verify with `qmd status` output, never by exit code.
