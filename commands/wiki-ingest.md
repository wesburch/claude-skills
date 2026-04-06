Ingest a new source into the wiki at ~/Documents/MyProjects/wiki/.

## Steps

1. Read ~/Documents/MyProjects/wiki/SCHEMA.md to load conventions.
2. Identify the source from the user's argument: file path, URL, or inline text/paste.
   - If a file path: read it fully.
   - If a URL: fetch it.
   - If inline text: treat it as the raw source content.
3. Save the source to `~/Documents/MyProjects/wiki/raw/YYYY-MM-DD-title.md` (use today's date, derive title from content). Skip if already saved or if it's a URL with no content to save.
4. Read `~/Documents/MyProjects/wiki/index.md` to find related existing pages.
5. Read those related pages.
6. Create or update 5–15 pages to synthesize the new knowledge:
   - Follow naming conventions from SCHEMA.md
   - Use frontmatter (title, category, tags, created/updated, sources)
   - Cross-link to related pages with [[wiki-style links]]
   - Images referenced should point to raw/assets/
7. Update `~/Documents/MyProjects/wiki/index.md`:
   - Add any new pages under the correct category header (one line: `- [[category/page-name]] — one-line summary`)
   - Update summaries for pages that changed significantly
8. Append to `~/Documents/MyProjects/wiki/log.md`:
   ```
   ## [YYYY-MM-DD] ingest | <Source Title>
   
   Pages created: X, pages updated: Y. Brief note on what was notable.
   ```
9. Run `qmd embed` in the background to reindex (if qmd is installed).

## Output

Report back: source saved, pages created/updated (list them), any cross-references added.

$ARGUMENTS
