---
name: briefme
description: Generate a branded HTML brief from agent work — status updates, research findings, or client meeting talking points. Auto-detects client brand colors from `.claude/brand.json` in the repo. Use when the user runs `/briefme`, asks for a brief, status doc, research write-up, or client meeting talking points from the current conversation.
argument-hint: "<status|meeting|research> [theme] [concise|standard|detailed] [optional inline content]"
---

# briefme — Branded HTML brief generator

Turn the work we just did together into a polished, branded HTML document. Three modes:

- **`status`** — dense work log for personal/internal review (what shipped, what's in flight, blockers, next steps).
- **`meeting`** — section-card layout designed to read live during a client meeting (one topic per card, scannable bullets, optional headline stat).
- **`research`** — findings deliverable (executive summary, numbered findings, recommendations).

## Arguments

- `$1` — mode: `status` | `meeting` | `research` (required)
- `$2` — optional theme name (folder name under `themes/`). If `$2` matches an existing theme folder, treat it as the theme. Otherwise it's not a theme — move to the next slot.
- `$3` — optional verbosity: `concise` | `standard` | `detailed`. Default is `standard` if not specified. If `$3` matches one of those, use it. Otherwise it's not a verbosity flag — treat `$3` onward as inline content.
- Remaining args — optional inline content. If omitted, synthesize the brief from the recent conversation context.

Args are positional and *each* slot is optional, but the order is: mode → theme → verbosity → content. The skill detects which is which by matching against known theme names and the two verbosity keywords.

**Examples:**
```
/briefme meeting
/briefme meeting engineered
/briefme meeting engineered concise
/briefme status concise                              # no theme, concise verbosity
/briefme research engineered detailed
/briefme status "Shipped the auth refactor"          # no theme, no verbosity, inline content
/briefme research engineered concise "Quick note: ..."
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
  "verbosity": "detailed",
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

The `theme` field is optional; omit it to be prompted each time (or always pass theme via the CLI arg). The `verbosity` field is optional; default is `standard` if missing. Valid values: `concise`, `standard`, `detailed`.

#### Color selection guidance

The accent color is used for small UI elements **including text** — card eyebrows, code-header `.lang` labels, link color, tag text, section-label markers. Because the accent carries text, it should hit **WCAG 4.5:1 against `background`**, not just 3:1.

##### When creating a new `brand.json`

1. **Investigate the client's actual brand** before picking colors. Look at their website, search for "<client> brand guidelines" or "<client> color palette", and pull the canonical brand colors. Note the source in your reply so the user knows whether it's official or inferred.
2. **Populate `colors.palette`** with 3–6 of the client's brand colors (hex values, full set). This becomes the pool of acceptable swap candidates if the chosen accent later fails contrast. Include the dark colors *and* the light ones — the agent picks per-context.
3. **Pick `primary` for hero/structural uses** — ticker, footer, borders, large blocks. Usually the client's darkest brand color. Must have ≥ 4.5:1 contrast against `background`.
4. **Pick `accent` for small element + text use** — dots, chips, links, eyebrows, code-header lang. **Must have ≥ 4.5:1 contrast against `background`.** If the most "brand-iconic" color (often a light mint, soft pastel, or pale tint) fails 4.5:1, pick a different color from `palette` rather than darkening — preserves brand authenticity.
5. **Only derive a darker variant as a last resort** — e.g. when the brand truly has only two colors and one is the background. Note the derivation: "Derived `#Y` from `#X` (HSL lightness -25%) because no palette color hit 4.5:1."
6. **Surface the tradeoff to the user before writing.** One-line summary: which colors you chose, the source, and whether any palette swap or derivation happened.

##### When loading an existing `brand.json`

1. Compute the contrast ratio of `accent` against `background` (WCAG relative luminance formula).
2. **If contrast ≥ 4.5:1, proceed silently** — no warning needed.
3. **If contrast < 4.5:1, do NOT silently render.** Run the fallback chain *in this exact order*:
   - **(a) Palette swap.** Walk `colors.palette` (if present). For each color, compute contrast vs. `background`. Pick the palette member that (i) passes 4.5:1, and (ii) is closest in hue to the original accent (so the brief still *feels* like the brand). If a palette swap succeeds, tell the user: *"Heads up — accent `#X` has ~Y:1 against background (below 4.5:1 for text). Using `#Z` from the brand palette for this run; it's a darker brand color that hits ~N:1 and stays in-brand. Want me to keep `#X` anyway?"*
   - **(b) Derived darker variant.** If `palette` is missing or no palette member passes 4.5:1, derive a darker variant of the original accent (HSL lightness -20–30%). Tell the user: *"Heads up — accent `#X` has ~Y:1 against background. No brand-palette color hit 4.5:1, so I derived `#Z` (darker variant of your accent) for this run. Want me to keep `#X` anyway?"*
4. **Whichever path runs, the swap is run-only.** Never modify `brand.json` without explicit user permission. If they prefer the original despite the contrast issue, use `#X` and move on — their call.

##### Defaults are already contrast-safe

The fallback palette (`#0A2540` primary / `#635BFF` accent on white) passes 4.5:1 cleanly.

### 4. Compose the body content

Based on the chosen mode AND chosen verbosity, structure the content.

#### Verbosity

**Default is `standard`** unless the user passed `concise` or `detailed` as an arg, or `brand.json` has a `"verbosity"` field set. The three levels are different rendering profiles, not different content — same source material, different filter.

##### `standard` (default) — everyday use

The sweet spot. Enough detail to be useful in a meeting or as an artifact you might forward, without burying the headline in three paragraphs of context.

Aim for this in practice:
- **1–2 short paragraphs per finding/card.** First paragraph carries the assertion + the key data point in `<code>`. Second (when present) adds the one piece of context the reader can't infer.
- **Executive summary is 2–3 sentences** in the callout — what's the headline, what's the recommendation in one line.
- **Cite real numbers in `<code>` spans.** Counts, percentages, file paths, event names. Don't paraphrase what's known.
- **Source line is kept** — one line under each finding, mono-styled. Anchors the claim.
- **No "considered and ruled out" tangent.** That's for `detailed`.
- **No code excerpts unless one is genuinely load-bearing** for the finding (rare in standard).
- **Recommendations are imperative + short rationale.** "**Approve v8 classifications** — converts the investigation from open to closed." One sentence, not a paragraph.

##### `concise` — personal scan, quick status

The reader is usually *you* and you already have the context. Strip to the load-bearing assertion + the key number.

- **One short paragraph per finding/card** — headline plus one decisive number/qualifier. No two-sided framing.
- **Callout collapses to one or two sentences.**
- **`<code>` spans kept** for key numbers and identifiers.
- **Source line is optional.** Include only if contested or load-bearing.
- **Code excerpts omitted** unless the finding is *about* the code.
- **Recommendations become short imperatives.** "Approve v8 classifications." / "Open direct_shop businessLine ticket if needed."

##### `detailed` — client meetings, research deliverables, high-stakes handoff

When you'll be reading FROM the brief in a discussion, or shipping it as a standalone artifact someone has to act on without you.

- **2–4 paragraphs per finding/card.** Headline → why → how you know → what was considered and ruled out → what to do.
- **Executive summary is 2–3 fuller sentences** with the headline AND the recommendation framing.
- **Include the "considered and ruled out" thread** when it informs the conclusion. "We initially suspected the frontend was dropping values, but the v8 Rollup showed parity, so the gap moved upstream to..."
- **Don't drop names, dates, tickets, or links.** "Wesley confirmed via Datadog requery on Apr 17."
- **Code excerpts pull their weight** when findings are code-grounded (per the code-evidence rule below).
- **Recommendations include rationale paragraphs.** Bolded directive + 1–2 sentences of explanation per item. Include conditional paths ("if X is a hard requirement, do Y, decision owner Z").

##### What's the same across all three

- Mode structure (status/meeting/research sections) is identical.
- Card eyebrows, em-accented titles, h3 card-titles, theme rendering — all consistent.
- **Filler is forbidden in all three.** If the conversation had 3 substantive findings, the brief has 3 — not 8 padded ones. **Never invent content.** Higher verbosity adds *real* context that exists in source material; it does not pad.

In short: **concise = "say it once", standard = "say it clearly", detailed = "explain it fully".**

**Title rules (apply to all modes).** The `{{TITLE}}` is the *subject* of the brief, not the *type*. Do not include words like "status", "research", "brief", "report", "investigation", "findings", "update", or "summary" in the title — those are already shown in the mode tag and ticker. Title should be specific to the subject: ✅ "GTM missing parameters" / "Auth refactor & dashboard kickoff" / "Pricing page competitive analysis". ❌ "GTM missing parameters status update" / "Auth research findings". **Default to wrapping the last 1–3 words of the title in `<em>`** for a typographic accent — themes style this consistently and it's an important visual signal. Example: `<h1 class="title">Auth refactor <em>before pilot</em></h1>`. The em phrase still must not restate the mode.

**Card eyebrow nudge.** When generating cards, **default to including a 1–2 word `<p class="card-eyebrow">` label** on each card (e.g. "Artifacts", "Findings", "Risk", "Next decision"). Eyebrows are styled with accent color and serve as quick scanability tags for cards. Omit only when the eyebrow would be redundant with the card title or section label.

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

**Critical: do not hand-write or paraphrase the template.** You must read the theme's `template.html` from disk verbatim and only substitute the listed tokens. Hand-rolling a "similar" CSS is wrong — the themes carry the design (specific Google Fonts, panel styles, ornaments, code-block treatments) that make briefs visually consistent. If you rewrite the CSS, every brief looks different and the theme system is meaningless.

The exact procedure:

1. **Read the template file** at `TEMPLATE_PATH` (resolved in step 2) using the Read tool. This gives you the complete HTML document — `<!DOCTYPE>` through `</html>` — including all `<link>` tags for fonts, the full `<style>` block, and the body chrome.
2. **Do not modify the CSS or the chrome.** Specifically:
   - Do not change the Google Fonts `<link>` tags or the `--f-sans` / `--f-mono` / `--f-display` / `--f-serif` font stacks.
   - Do not simplify, minify, or reformat the CSS.
   - Do not drop CSS classes you think are unused — other modes/themes may use them.
   - Do not invent new classes; only use ones the theme already defines (see `themes/README.md`).
3. **Substitute these tokens** by exact string replacement (case-sensitive, with double curly braces):
   - `{{CLIENT_NAME}}` — from brand.json
   - `{{CLIENT_URL}}` — from brand.json or `REMOTE_URL` (linkify if URL, else plain text)
   - `{{TAGLINE}}` — from brand.json (or empty string)
   - `{{MODE_LABEL}}` — `Status Brief` | `Meeting Brief` | `Research Brief`
   - `{{TITLE}}` — short title you generate based on content (e.g. "Auth refactor & dashboard kickoff")
   - `{{DATE}}` — today's date, formatted `Month D, YYYY` (e.g. "May 20, 2026")
   - `{{COLOR_PRIMARY}}`, `{{COLOR_ACCENT}}`, `{{COLOR_ACCENT_DECO}}`, `{{COLOR_BACKGROUND}}`, `{{COLOR_SURFACE}}`, `{{COLOR_TEXT}}`, `{{COLOR_MUTED}}`, `{{COLOR_BORDER}}` — from brand.json (use defaults if not set). See the two-tier accent rule below for `{{COLOR_ACCENT}}` vs `{{COLOR_ACCENT_DECO}}`.

**Two-tier accent rule.** Themes use two accent variables:
- `--c-accent` carries text — card eyebrows, code-header `.lang` labels, link color, counter numbers. Must hit ≥ 4.5:1 vs background.
- `--c-accent-deco` is for decoration only — dots, borders, accent strips, highlight backgrounds where dark text sits on top. Can be lighter; preserves brand identity.

Substitution rule when rendering:
- **If brand accent passes 4.5:1:** substitute the same brand accent for *both* `{{COLOR_ACCENT}}` and `{{COLOR_ACCENT_DECO}}`. No special-casing needed.
- **If brand accent fails 4.5:1 (contrast fallback fired in step 3):** substitute the *contrast-safe value* (palette swap or derived darker variant) into `{{COLOR_ACCENT}}`, and substitute the *original light brand color* into `{{COLOR_ACCENT_DECO}}`. This keeps the original brand color visible on dots/strips while text uses the readable darker variant.

So for Stitch Fix mint `#86C8BC` (1.91:1 — fails), a run might substitute `#3A8073` (derived darker) into `{{COLOR_ACCENT}}` and keep `#86C8BC` in `{{COLOR_ACCENT_DECO}}`. Result: text reads cleanly, mint dots/strips stay vibrant.
4. **Replace the `<!-- BODY -->` placeholder** with your composed body HTML (the content from step 4). Replace the comment marker exactly once with your body content.
5. **Sanity check before writing.** Confirm the output:
   - Starts with `<!DOCTYPE html>`
   - Contains the `<link rel="stylesheet" href="https://fonts.googleapis.com/...">` tag the template had (themes load specific fonts; if this is missing, you regenerated the template instead of substituting into it)
   - Contains the full `<style>` block from the template (typically 200+ lines unminified)
   - Has no remaining `{{TOKEN}}` placeholders or `<!-- BODY -->` markers
6. **Write the file** using the Write tool.

If you find yourself writing CSS rules, stop — you are doing it wrong. Re-read the template file and substitute into it.

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
