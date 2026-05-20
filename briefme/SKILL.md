---
name: briefme
description: Generate a branded HTML brief from agent work — status updates, research findings, or client meeting talking points. Auto-detects client brand colors from `.claude/brand.json` in the repo. Use when the user runs `/briefme`, asks for a brief, status doc, research write-up, or client meeting talking points from the current conversation.
argument-hint: "<status|meeting|research> [theme] [optional inline content]"
---

# briefme — Branded HTML brief generator

Turn the work we just did together into a polished, branded HTML document. Three modes:

- **`status`** — dense work log for personal/internal review (what shipped, what's in flight, blockers, next steps).
- **`meeting`** — section-card layout designed to read live during a client meeting (one topic per card, scannable bullets, optional headline stat).
- **`research`** — findings deliverable (executive summary, numbered findings, recommendations).

## Arguments

- `$1` — mode: `status` | `meeting` | `research` (required)
- `$2` — optional theme name (folder name under `themes/`). If `$2` matches an existing theme folder, treat it as the theme. Otherwise treat `$2` and onward as inline content.
- `$3..` (or `$2..` if no theme) — optional inline content. If omitted, synthesize the brief from the recent conversation context.

**Examples:**
```
/briefme meeting
/briefme meeting editorial
/briefme status "Shipped the auth refactor, started on the dashboard widget"
/briefme research bold "Finished competitive analysis on pricing pages..."
```

## Procedure

Run these steps in order. Use parallel tool calls where independent.

### 1. Resolve project root and client info

Run in parallel:
- `git rev-parse --show-toplevel` — repo root. If not in a git repo, ask the user where to save and use cwd.
- `git remote get-url origin 2>/dev/null` — for client URL fallback.

Set `REPO_ROOT` from the first command. Set `REMOTE_URL` from the second (may be empty).

### 2. Resolve the theme

Themes live in `themes/<theme-name>/template.html` next to this SKILL.md. Selection precedence:

1. **Explicit arg.** If `$2` matches an existing folder under `themes/`, use it.
2. **Per-client default.** If `brand.json` has a `theme` field naming an existing theme, use it.
3. **Interactive prompt.** Otherwise, list the folders under `themes/` and ask the user with `AskUserQuestion` which to use. Always include "default" first. Limit to 4 options; if there are more themes, ask which category (use folder names directly).

If the resolved theme folder doesn't exist or is missing `template.html`, fall back to `themes/default/template.html` and tell the user why.

Store the resolved path as `TEMPLATE_PATH`.

### 3. Load (or create) brand.json

Check for `<REPO_ROOT>/.claude/brand.json`.

**If it exists:** read it. Validate it has at minimum `client` and `colors.primary`.

**If it does NOT exist:** before generating the brief, ask the user with `AskUserQuestion`:
> "No `.claude/brand.json` found in this repo. Want me to create one now? I'll need: client name, primary color, accent color, and optional URL."

Offer two options:
- "Yes, set it up now" — collect values via follow-up questions, then write `<REPO_ROOT>/.claude/brand.json` using the schema in `brand.example.json` (next to this SKILL.md).
- "Use defaults this time" — proceed with the built-in default palette (neutral grays + blue accent).

Brand schema (mirror `brand.example.json`):
```json
{
  "client": "Acme Corp",
  "url": "https://acme.com",
  "tagline": "Optional one-liner shown under the client name",
  "theme": "default",
  "colors": {
    "primary": "#0A2540",
    "accent": "#635BFF",
    "background": "#FFFFFF",
    "surface": "#F7F7F9",
    "text": "#0A0A0A",
    "muted": "#6B7280",
    "border": "#E5E7EB"
  }
}
```

The `theme` field is optional; omit it to be prompted each time (or always pass theme via the CLI arg).

#### Color selection guidance

The accent color is used for small UI elements that sit on the background: dots, tags, eyebrow text, code-header lang labels, link color. If the accent doesn't contrast against the background, the brief looks washed out and accessibility suffers.

**When creating a new `brand.json`** (i.e., the file doesn't exist and the user agrees to set one up):

1. **Investigate the client's actual brand** before picking colors. Look at their website, search for "<client> brand guidelines" or "<client> color palette", and pull the canonical primary + secondary brand colors. Note the source in your reply so the user knows whether it's official or inferred.
2. **Pick `primary` for hero/structural uses** — large blocks, ticker, footer, borders. Usually the client's darkest brand color (often deep navy, charcoal, or saturated brand hue). Must have ≥ 4.5:1 contrast against the background.
3. **Pick `accent` for small element use on the background** — dots, chips, links, eyebrows. Must have **≥ 3:1 contrast against `background`** (WCAG non-text minimum). Aim for 4.5:1+ if it will carry text.
4. **If the natural brand accent is too light** for the background (e.g. pastel mint, soft beige), do one of the following:
   - Pick a *different* brand color that has better contrast (often the second or third in the palette is darker).
   - Derive a darker variant by reducing lightness ~20–30% (HSL space). Note this clearly to the user: "I darkened the accent from #X to #Y for contrast — let me know if you'd prefer to keep the lighter brand value."
5. **Surface the tradeoff to the user before writing the file.** Don't silently pick. One-line summary: which colors you selected, source, and any darkened variants.

**When loading an existing `brand.json`**:

- Compute the contrast ratio of `accent` against `background` (WCAG relative luminance formula).
- If it's below 3:1, do NOT silently render — warn the user once at the start: *"Heads up: accent `#X` has ~Y:1 contrast against background. Small UI bits (dots, tags, eyebrows) will look faded. Want me to derive a darker variant just for this brief?"*
- If the user says yes, use a derived darker variant for this run only — do not modify `brand.json` without explicit permission.

**Defaults are already contrast-safe** — the fallback palette (`#0A2540` / `#635BFF` on white) passes both 3:1 and 4.5:1.

### 4. Compose the body content

Based on the chosen mode, structure the content. **Do not pad with filler.** If the conversation only has 3 substantive points, the brief has 3 cards — not 8.

**Title rules (apply to all modes).** The `{{TITLE}}` is the *subject* of the brief, not the *type*. Do not include words like "status", "research", "brief", "report", "investigation", "findings", "update", or "summary" in the title — those are already shown in the mode tag and ticker. Title should be specific to the subject: ✅ "GTM missing parameters" / "Auth refactor & dashboard kickoff" / "Pricing page competitive analysis". ❌ "GTM missing parameters status update" / "Auth research findings". You may use `<em>` to add a 1–3 word secondary phrase (e.g. `Auth refactor <em>before pilot</em>`) — but the phrase still should not restate the mode.

#### `status` mode — dense work log
Sections, in this order, **omit any that have no content**:
1. **Summary** — one paragraph, what was the focus of this session.
2. **Completed** — bulleted list with brief detail per item.
3. **In progress** — bulleted list with current state per item.
4. **Blocked / open questions** — what's stuck and why.
5. **Next steps** — ordered list, prioritized.

#### `meeting` mode — section cards for talking live
Generate 3–7 cards. Each card is one discussion topic. Per card:
- **Title** (short, headline-style, 2–6 words)
- **2–4 bullets** — talking points, scannable while speaking
- **Optional headline stat** — a big number/metric pulled from the work (e.g. "40% faster", "3 features shipped"). Only include if there's a real, defensible number — never invent one.

Order cards by what the user would discuss first → last in a meeting (wins → progress → asks).

#### `research` mode — findings deliverable
1. **Executive summary** — 2–3 sentences in a highlighted callout box.
2. **Findings** — numbered list of findings, each with: a title, 1–2 paragraphs of detail, **optional code evidence** (see below — prefer to include when the finding is about code behavior), and an optional source/citation line.
3. **Recommendations** — ordered list of next actions.

**Code evidence in findings.** When a research finding is grounded in code you've actually read in this session, **default to including a short code excerpt as evidence** under the finding's narrative. This is the difference between a finding that asserts something and one that proves it.

Rules:
- Excerpt 5–25 lines, focused on the relevant block. If the function is longer, show the load-bearing slice with a `// …` comment indicating elision.
- Always include the file path + line range in the `.file` span (e.g. `src/lib/auth.ts:42-58`).
- Include the language in the `.lang` span (e.g. `TypeScript`, `Ruby`, `SQL`).
- Use the markup pattern below. All themes style it.
- Never invent or paraphrase code — only show code you have actually read. If you don't have the actual code in context, omit the block.

```html
<li>
  <h3>Finding title</h3>
  <p>Narrative paragraph explaining what the code shows and why it matters.</p>
  <pre><span class="code-header"><span class="file">src/lib/auth.ts:42-58</span><span class="lang">TypeScript</span></span><code>function buildSession(user: User) {
  if (!user.profile?.complete) {
    return null; // guards downstream emitters
  }
  return { id: user.id, ts: Date.now() };
}</code></pre>
  <p class="source">Source: code inspection, growth-next-ui@<sha></p>
</li>
```

The same code-evidence block is also useful in `status` mode when reporting on what was changed — include it sparingly, only when the diff is small and load-bearing.

### 5. Render the HTML

Read `TEMPLATE_PATH` (the theme's `template.html`, resolved in step 2). It contains a complete design shell with CSS custom properties for brand colors and a single `<!-- BODY -->` placeholder.

Replace the following tokens in the template:
- `{{CLIENT_NAME}}` — from brand.json
- `{{CLIENT_URL}}` — from brand.json or `REMOTE_URL` (linkify if URL, else plain text)
- `{{TAGLINE}}` — from brand.json (or empty string)
- `{{MODE_LABEL}}` — `Status Brief` | `Meeting Brief` | `Research Brief`
- `{{TITLE}}` — short title you generate based on content (e.g. "Auth refactor & dashboard kickoff")
- `{{DATE}}` — today's date, formatted `Month D, YYYY` (e.g. "May 20, 2026")
- `{{COLOR_PRIMARY}}`, `{{COLOR_ACCENT}}`, `{{COLOR_BACKGROUND}}`, `{{COLOR_SURFACE}}`, `{{COLOR_TEXT}}`, `{{COLOR_MUTED}}`, `{{COLOR_BORDER}}` — from brand.json (use defaults if not set)
- `<!-- BODY -->` — replace with your composed body HTML

### 6. Write and open

- Output path: `<REPO_ROOT>/.claude/briefs/<mode>-<theme>-YYYY-MM-DD-HHMM.html`
- Create the `.claude/briefs/` directory if it doesn't exist.
- After writing, run `open <path>` to launch it in the default browser.
- Add `.claude/briefs/` to `.gitignore` if a `.gitignore` exists at the repo root and the path isn't already ignored (don't create a `.gitignore` just for this).

### 7. Confirm to the user

One short line: the path that was written, the theme used, and that it's been opened in the browser. No summary of the brief contents — they'll see it in the browser.

## Body HTML guidelines (for any mode)

Use semantic, minimal HTML. **All themes style the same set of classes** — see `themes/README.md` for the full contract. The shared classes:

- `<section class="card">` — one section card with header + body
- `<h3 class="card-title">` — card title. **Always use `<h3>` for card titles**, never `<h2>`. Section labels (e.g. "Completed", "Findings") use `<h2 class="section-label">`; this preserves a clean h1 → h2 → h3 outline.
- `<p class="card-eyebrow">` — small uppercase label above title (optional)
- `<ul class="bullets">` / `<li>` — talking-point bullets
- `<div class="stat">` — big headline stat container
  - `<div class="stat-value">40%</div>` — large number
  - `<div class="stat-label">faster page load</div>` — small caption
- `<div class="callout">` — highlighted box for executive summary
- `<ol class="findings">` / `<li>` — numbered findings list
- `<pre><span class="code-header"><span class="file">path:line</span><span class="lang">Language</span></span><code>...</code></pre>` — code-evidence block. See "Code evidence" below.

You may also wrap a short phrase in `<em>` inside the title (e.g. `GTM <em>investigation status</em>`) — all themes style this as a typographic accent. Use sparingly.

For `meeting` mode cards with a stat, use this two-column structure:
```html
<section class="card card--with-stat">
  <div class="card-main">
    <h3 class="card-title">Card title</h3>
    <ul class="bullets">
      <li>Talking point</li>
    </ul>
  </div>
  <aside class="stat">
    <div class="stat-value">3x</div>
    <div class="stat-label">faster builds</div>
  </aside>
</section>
```

## Defaults (used when brand.json is missing)

```
primary:    #0A2540
accent:     #635BFF
background: #FFFFFF
surface:    #F7F7F9
text:       #0A0A0A
muted:      #6B7280
border:     #E5E7EB
client:     <derive from REPO_ROOT folder name>
```

## Notes

- Never invent metrics, dates, or claims. If a stat isn't in the conversation or repo, omit the stat block — don't fabricate one.
- Keep the brief tight. A meeting brief with 4 strong cards beats one with 8 padded cards.
- The HTML is standalone (inline CSS, no external assets except an optional Google Font CDN link in the template head). The user can save it, share it, or print to PDF.
