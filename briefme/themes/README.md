# Themes

## Installed themes

| Theme | Character | Type stack |
|---|---|---|
| `default` | Refined editorial — sans-led with an Instrument Serif accent. Safe choice for most clients. | Inter Tight · Instrument Serif · JetBrains Mono |
| `engineered` | Technical / data-room feel — monospaced details, gridded. Good for engineering-heavy work. | IBM Plex Sans · IBM Plex Mono |
| `magazine` | Bold editorial — oversized Bricolage display, magazine layout energy. Good for creative/brand clients. | Bricolage Grotesque · Inter Tight · JetBrains Mono |
| `swiss` | Modernist / gridded — Space Grotesk display, tight & geometric. Good for clean B2B / product clients. | Space Grotesk · Inter Tight · JetBrains Mono |

To add a new theme, follow the contract below.

---

# Theme contract

Every theme is a folder under `themes/` containing at minimum:

```
themes/<theme-name>/
└── template.html
```

Optional:
- `preview.png` — a small screenshot of the theme (used in docs, not at runtime).
- `assets/` — any static assets the template references (logos, ornaments). Inline base64 is preferred so the brief stays a single standalone HTML file.

## Required template tokens

The skill substitutes these placeholders in `template.html` before writing the output. **All must be present in your template** (use them in `<title>`, header chrome, footer, etc. as makes sense for the design):

| Token | Source | Example |
|---|---|---|
| `{{CLIENT_NAME}}` | `brand.json` `client` | "Acme Corp" |
| `{{CLIENT_URL}}` | `brand.json` `url` or git remote | `https://acme.com` |
| `{{TAGLINE}}` | `brand.json` `tagline` (may be empty) | "Brand & growth" |
| `{{MODE_LABEL}}` | derived from mode | "Status Brief" / "Meeting Brief" / "Research Brief" |
| `{{TITLE}}` | agent-generated short title | "Auth refactor & dashboard kickoff" |
| `{{DATE}}` | today | "May 20, 2026" |
| `{{COLOR_PRIMARY}}` | `brand.json` colors | `#0A2540` |
| `{{COLOR_ACCENT}}` | `brand.json` colors (contrast-safe; ≥4.5:1 vs background) | `#635BFF` |
| `{{COLOR_ACCENT_DECO}}` | `brand.json` colors (original brand value, even if light) | `#86C8BC` |
| `{{COLOR_BACKGROUND}}` | `brand.json` colors | `#FFFFFF` |
| `{{COLOR_SURFACE}}` | `brand.json` colors | `#F7F7F9` |
| `{{COLOR_TEXT}}` | `brand.json` colors | `#0A0A0A` |
| `{{COLOR_MUTED}}` | `brand.json` colors | `#6B7280` |
| `{{COLOR_BORDER}}` | `brand.json` colors | `#E5E7EB` |

## Required body placeholder

The composed body HTML gets injected at this exact comment marker (case-sensitive, no extra whitespace inside):

```html
<!-- BODY -->
```

Put it inside whatever container/layout your theme uses (a `<main>`, a max-width wrapper, etc.).

## Required CSS class names (style these in your theme)

The agent generates the body using a stable set of classes so any theme can render any mode. Your theme's CSS must style these so output looks right:

| Class | Used by | Purpose |
|---|---|---|
| `.card` | all modes | One section/topic block |
| `.card--with-stat` | `meeting` | Two-column card with a stat block |
| `.card-main` | `meeting` | Left column of a stat card |
| `.card-eyebrow` | optional | Small label above card title |
| `.card-title` | all modes | Card heading — **always rendered as `<h3>`** so the document outline stays clean (h1 title → h2 section labels → h3 card titles). Style based on the class, not the element. |
| `.bullets` / `.bullets li` | all modes | Talking-point bullets |
| `.stat` | `meeting`, `status` | Big-number container |
| `.stat-value` | `meeting`, `status` | Large numeric display |
| `.stat-label` | `meeting`, `status` | Small caption under the stat |
| `.callout` | `research` | Highlighted executive summary box |
| `.findings` / `.findings > li` | `research` | Numbered findings list |
| `.findings h3` | `research` | Finding title |
| `.findings .source` | `research` | Italic source line |
| `.section` | optional | Logical grouping of cards |
| `.section-label` | optional | Small uppercase label above a section |

If your theme wants to add extra ornaments (rules, ornaments, accent bars), do it in your own theme-local classes — don't rename the shared ones.

### Two-tier accent (mandatory for new themes)

Every theme must declare two accent CSS variables in `:root`:

```css
--c-accent:      {{COLOR_ACCENT}};       /* text-safe accent (≥4.5:1 vs bg) — used wherever accent carries TEXT */
--c-accent-deco: {{COLOR_ACCENT_DECO}};  /* decorative accent — original brand color, used on non-text dots/strips */
```

**Use `--c-accent` for:**
- `color:` on text-carrying elements: `.card-eyebrow`, `pre .code-header .lang`, `.title em` (when em is text not bg-highlight), counter numbers in `ol.bullets > li::before`, `.findings > li::before` counters, `.section-label::before` symbol, link colors.
- Anything that needs to be legible as text or text-like glyph.

**Use `--c-accent-deco` for:**
- `background:` fills on decorative pseudo-elements: dots, accent bars, callout strips.
- `border-left:` / `border-top:` accent strips on `.callout`, `.stat`.
- Highlight backgrounds behind text (e.g. `.title em { background: ... }`) — paired with dark text overlay via `color`.
- The `.acc` / `.mark` decorative-dot classes in ticker/footer.

When brand accent already passes 4.5:1, both variables receive the same value — visually identical to a single-accent theme. The two-tier system only diverges when contrast fallback fires (light pastel brand colors).

### Code evidence block

Themes should also style `<pre><code>` blocks for code-evidence inside findings. The expected markup is:

```html
<pre>
  <span class="code-header">
    <span class="file">src/lib/auth.ts:42-58</span>
    <span class="lang">TypeScript</span>
  </span>
  <code>... actual code, preserved whitespace ...</code>
</pre>
```

Required CSS hooks for the theme:
- `pre` — the container (background, border, monospace, no overflow).
- `pre .code-header` — top strip showing file path + language.
- `pre .code-header .file` — file path span.
- `pre .code-header .lang` — language span (usually styled with `var(--c-accent)`).
- `pre code` — the code block itself (block display, padding, preserved whitespace).

All four shipped themes (`default`, `engineered`, `magazine`, `swiss`) already implement this.

## Naming

- Folder name = theme name. Use kebab-case: `editorial`, `bold`, `minimal`, `studio-press`.
- The folder name is what users type: `/briefme meeting editorial`.

## How a theme is selected (recap)

1. Explicit arg: `/briefme <mode> <theme>`
2. Per-client default in `brand.json`: `"theme": "editorial"`
3. If neither, the skill asks interactively, listing the folders found here.
