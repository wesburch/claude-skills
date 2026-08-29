# Query

Answer a question from the wiki.

## Steps

1. Read `SCHEMA.md` (and `CLAUDE.md`) to load conventions, if not already loaded.
2. Read `index.md` to identify relevant pages — it is authoritative and complete, so
   scanning it beats globbing `pages/`. Follow into the category `index.md` maps as needed.
3. Search when the index isn't enough:
   ```sh
   qmd search "keywords"     # BM25 full-text, fast — start here
   qmd query "question"      # hybrid + rerank; first use downloads a ~1.3GB model
   qmd vsearch "question"    # vector similarity only
   ```
4. Read all relevant pages — err on the side of reading more, not fewer.
5. Synthesize a thorough answer with citations:
   - Reference pages as `[[category/page-name]]`.
   - Note contradictions or gaps in the wiki where they exist.
   - State a confidence level when uncertain.
6. If the answer is novel synthesis not already captured in a page, offer to save it as a
   new page (then follow the ingest steps for index, category map, and log updates).
7. Append to `log.md` (append-only):
   ```
   ## [YYYY-MM-DD] query | <Question summary>

   Brief note on what pages were consulted and whether a new page was created.
   ```

## Output

Answer the question directly, then list the sources consulted.
