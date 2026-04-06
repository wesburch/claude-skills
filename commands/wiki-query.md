Query the wiki at ~/Documents/MyProjects/wiki/ to answer a question.

## Steps

1. Read ~/Documents/MyProjects/wiki/SCHEMA.md to load conventions.
2. Read ~/Documents/MyProjects/wiki/index.md to identify relevant pages.
   - If qmd MCP is available, use `qmd query "<question>"` for better semantic search.
3. Read all relevant pages (err on the side of reading more, not fewer).
4. Synthesize a thorough answer with citations:
   - Reference pages as [[category/page-name]]
   - Note contradictions or gaps in the wiki if found
   - Note confidence level if uncertain
5. If the answer represents novel synthesis not already captured in a page, offer to save it as a new wiki page.
6. Append to ~/Documents/MyProjects/wiki/log.md:
   ```
   ## [YYYY-MM-DD] query | <Question summary>
   
   Brief note on what pages were consulted and whether a new page was created.
   ```

## Output

Answer the question directly, then list sources consulted.

$ARGUMENTS
