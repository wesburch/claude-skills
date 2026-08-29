# Ingest

Add a new source to the wiki and synthesize it into pages.

## Steps

1. Read `SCHEMA.md` (and `CLAUDE.md`) to load conventions, if not already loaded.
2. Identify the source from the user's argument: file path, URL, or inline text/paste.
   - File path → read it fully.
   - URL → fetch it.
   - Inline text → treat it as the raw source content.
3. Save the source to `raw/YYYY-MM-DD-title.md` (today's date, title derived from content).
   Skip if already saved, or if it's a URL with no retrievable content.
   **`raw/` is append-only** — never edit a previously saved source. New material means a
   new dated file.
4. Read `index.md` to find related existing pages, then read the relevant category
   `index.md` maps.
5. Read those related pages before writing anything. Update existing pages in preference to
   creating near-duplicates.
6. Create or update 5–15 pages to synthesize the new knowledge:
   - Follow the naming conventions in `SCHEMA.md`.
   - Frontmatter per `SCHEMA.md` (title, category, created, updated, sources).
     **No `tags:`** — tags were removed 2026-08-22; do not reintroduce them.
   - Link liberally with full paths: `[[category/page-name]]`, not `[[page-name]]`.
     Cross-category links are the point.
   - Images reference `raw/assets/`.
   - Flag uncertainty inline: `Unconfirmed:`, `As of [date]:`, `Contradicts [[x]]:`.
7. Update `index.md`: add each new page under the correct category header as one line —
   `- [[category/page-name]] — one-line summary` — and refresh summaries for pages that
   changed significantly.
8. Update the category `index.md` map for every category you touched, grouping the new page
   under the right theme. Create a new category directory only on demand.
9. Append to `log.md` (append-only, never rewrite past entries):
   ```
   ## [YYYY-MM-DD] ingest | <Source Title>

   Pages created: X, pages updated: Y. Brief note on what was notable.
   ```
10. Reindex: `make reindex` (runs `qmd update` then `qmd embed`). `qmd embed` alone does not
    pick up new files. Verify with `qmd status` — a file count matching the vault and a
    fresh timestamp. A zero exit code proves nothing.

## Output

Report: source saved, pages created/updated (list them), cross-references added, reindex status.
