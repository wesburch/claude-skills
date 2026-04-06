Audit the wiki at ~/Documents/MyProjects/wiki/ for health issues.

## Steps

1. Read ~/Documents/MyProjects/wiki/SCHEMA.md to load conventions.
2. Read ~/Documents/MyProjects/wiki/index.md to get the full page catalog.
3. Read all pages in ~/Documents/MyProjects/wiki/pages/.
4. Check for each of the following issues:

   **Broken links** — [[links]] that reference pages not in index.md
   **Orphan pages** — pages that exist on disk but are not listed in index.md
   **Missing frontmatter** — pages without required frontmatter fields (title, category, tags, created, updated, sources)
   **Unsourced claims** — factual assertions with no source citation
   **Contradictions** — claims in one page that conflict with claims in another
   **Stale content** — pages with `updated` dates older than 90 days that reference time-sensitive topics
   **Empty categories** — categories in index.md with no pages
   **Overloaded pages** — pages that have grown too broad and should be split

5. Produce a lint report grouped by issue type. Do NOT auto-fix — report only.
6. Suggest which issues are highest priority to address.
7. Append to ~/Documents/MyProjects/wiki/log.md:
   ```
   ## [YYYY-MM-DD] lint | N issues found
   
   Breakdown: X broken links, Y orphans, Z contradictions, etc.
   ```

## Output

Lint report with prioritized issue list. Ask user which issues to fix.

$ARGUMENTS
