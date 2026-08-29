# Lint

Audit the wiki for health issues. **Report only — do not auto-fix.**

## Steps

1. Read `SCHEMA.md` (and `CLAUDE.md`) to load conventions, if not already loaded.
2. Read `index.md` for the full page catalog, plus each category `index.md` map.
3. Read all pages in `pages/`.
4. Check for:

   **Broken links** — `[[links]]` that reference pages not in `index.md`.
   **Bare links** — `[[page-name]]` without the `category/` prefix.
   **Orphan pages** — pages on disk that are not listed in `index.md`.
   **Category-map drift** — pages in `index.md` missing from their category `index.md`.
   **Missing frontmatter** — pages missing required fields per `SCHEMA.md`
   (title, category, created, updated, sources).
   **Stray `tags:`** — tags were removed 2026-08-22; any surviving `tags:` is an issue.
   **Unsourced claims** — factual assertions with no source citation.
   **Contradictions** — claims in one page that conflict with another.
   **Stale content** — `updated` older than 90 days on time-sensitive topics.
   **Empty categories** — categories in `index.md` with no pages.
   **Overloaded pages** — pages grown too broad that should be split.
   **Stale index** — `qmd status` file count or timestamp out of sync with the vault.

5. Produce a lint report grouped by issue type. Do NOT auto-fix.
6. Rank which issues are highest priority to address.
7. Append to `log.md` (append-only):
   ```
   ## [YYYY-MM-DD] lint | N issues found

   Breakdown: X broken links, Y orphans, Z contradictions, etc.
   ```

## Output

Prioritized lint report. Then ask the user which issues to fix.
