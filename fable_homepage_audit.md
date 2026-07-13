# Technical Audit — yannick-knieriemen.github.io

**Date:** 2026-07-13 · **Audited commit:** `07ebc33` (main) · **Scope:** full repository, read-only

## 0. What this site actually is (baseline facts)

There is no framework, no `package.json`, no build step for the page itself — and that is
the correct architecture for this site. Total repo payload:

```
264K  .
160K  ./cv.pdf          (built by CI from cv/cv.tex, PDF 1.7)
 28K  ./profile.webp    (WebP, 1200x900)
 24K  ./index.html      (entire site: markup + inline CSS + inline JS)
```

Three GitHub Actions workflows: `build-cv.yml` (LaTeX → cv.pdf on push to `cv/**`),
`link-check.yml` (monthly lychee), `retry-pages-deploy.yml` (re-runs failed Pages deploys).
Deployment is the classic GitHub Pages "pages build and deployment" pipeline (push = publish).

The site is small enough that nothing here is *slow* in absolute terms. But within that
envelope there are real, specific problems, ranked below by impact.

---

## 1. Tech Stack & Dependency Health

### 1.1 The only third-party runtime dependency is Google Fonts — and it's the single biggest performance and compliance liability

`index.html:35-37`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;1,400&family=DM+Sans:wght@300;400;500&display=swap" rel="stylesheet"/>
```

Measured during this session:

```
$ curl -w "fonts-css2: %{size_download} bytes, %{time_total}s" "https://fonts.googleapis.com/css2?..."
fonts-css2: 1400 bytes, 0.826827s
$ curl ... | grep -c "@font-face"
6
```

Three distinct problems, all verified:

1. **Render-blocking critical-path chain.** The stylesheet `<link>` is a blocking resource
   that requires DNS + TLS to a second origin (`fonts.googleapis.com`), whose CSS then
   triggers downloads from a *third* origin (`fonts.gstatic.com`). That is 2 extra TLS
   handshakes before first render — on a page whose entire own payload is 24 KB. The
   `preconnect` hints mitigate but do not eliminate this; the CSS fetch itself took ~830 ms
   from this container. For a page this small, Google Fonts is the majority of load time.

2. **Two of the six loaded font variants are dead weight.** The URL requests 6 variants;
   grep proves what the CSS actually uses:

   ```
   $ grep -oE "font-weight:? ?[0-9]+" index.html | sort | uniq -c
     2 font-weight: 400
     9 font-weight: 500
   ```

   - **DM Sans 300** — requested, *never referenced*. No `font-weight: 300` exists anywhere.
   - **EB Garamond italic 400** — its only consumer is `.avatar-initials`
     (`index.html:89`), an element that is `display:none` unless `profile.webp` fails to
     load (`index.html:191-192`). You are shipping an entire italic font file for an error
     fallback that renders two letters.
   - (EB Garamond 500 *is* implicitly used: `.cv-content strong` is serif with default
     `font-weight: 700`, so the browser picks the 500 file and synthesizes bold — see §2.3.)

3. **GDPR exposure, specifically relevant to you.** Embedding Google Fonts (which transmits
   visitor IP addresses to Google) was ruled a GDPR violation by LG München I
   (3 O 17493/20, Jan 2022). A German academic at a Munich institute serving Google Fonts
   from a personal site without a consent banner is exactly the fact pattern of that
   ruling and of the subsequent Abmahnung wave. Self-hosting eliminates the issue entirely,
   no banner needed.

**Verdict:** self-host two woff2 files (EB Garamond 400+500 latin, DM Sans 400+500 latin,
~15–25 KB each) with `font-display: swap` and preload the body font. This removes both
third-party origins, drops two dead variants, and closes the compliance gap. This is the
Phase-2 blueprint in §4.

### 1.2 CI dependency pinning is by mutable tag, not SHA

All actions are pinned to major tags: `actions/checkout@v4`, `xu-cheng/latex-action@v3`,
`lycheeverse/lychee-action@v2`, `peter-evans/create-issue-from-file@v5`,
`actions/github-script@v7`. Two of these workflows hold write permissions
(`build-cv.yml`: `contents: write`; `retry-pages-deploy.yml`: `actions: write`).
`xu-cheng/latex-action` and `peter-evans/create-issue-from-file` are single-maintainer
community actions; a compromised tag on either could push arbitrary commits to this repo
(= publish arbitrary content to your live site, since push = deploy). For a repo where
CI *commits to main*, pinning to full commit SHAs is the standard mitigation and costs
nothing. Low probability, but the blast radius is "attacker controls your public
professional identity."

### 1.3 `build-cv.yml` race condition (real, already documented, still unfixed)

`build-cv.yml` does checkout → ~2 min LaTeX compile → `git push` with **no retry and no
rebase**. If anything lands on `main` during the compile window, the push fails and the
CV/date silently never update — no issue is opened, `fail: false` semantics by omission.
Your own CLAUDE.md warns about the 2-minute lag ("git pull before further local work"),
which is exactly the window in which this breaks. Fix is one line:
`git pull --rebase origin main` before `git push`, or `git push` in a retry loop.

Also brittle by design: the workflow patches `index.html` with `sed` against the literal
pattern `<span id="cv-date">[^<]*</span>` (`build-cv.yml`, "Publish PDF" step). If that
span is ever reformatted (attribute added, split across lines), the sed silently matches
nothing and the date freezes while the PDF updates. Silent-success seds in CI deserve a
`grep -q` guard that fails the job when the pattern is missing.

### 1.4 `retry-pages-deploy.yml` — sound, one blind spot

The `run_attempt < 3` guard correctly prevents infinite retry loops, and the job-name
filter (`job.name === "deploy"`) is correct for the Pages pipeline. Blind spot: it only
re-runs when the *deploy* job failed; a failure in the *build* job (Jekyll — see §3.4)
is found by `jobs.find(...)` as `undefined` and skipped. Acceptable, but know that "retry"
here means "retry deploys only."

### 1.5 `link-check.yml` excludes most of what matters

```yaml
args: --no-progress --exclude 'linkedin\.com' --exclude 'ifo\.de' index.html
```

Verified against the live HTML: **5 of the 12 external links on the page are `ifo.de`**
(your profile ×2, the ECR center, the project page) plus 1 LinkedIn. So the monthly link
check actually validates only half your links — and the excluded ones are your most
important professional links (institutional profile, current project). ifo.de returning
503 to bots is a legitimate reason to exclude it from *failure*, but lychee supports
`--accept 403,503` per-status handling, which would keep those URLs checked for
hard 404s (dead profile page after a URL restructure) while tolerating bot-blocking.

---

## 2. Asset & Performance Bottlenecks

### 2.1 Fonts — covered in §1.1; it dominates everything else in this section.

### 2.2 `profile.webp`: fine on weight, broken on layout stability

26 KB for 1200×900 WebP is well-optimized — no complaint on bytes (it doubles as the
lightbox full-size image and the `og:image`, which justifies the resolution). But
`index.html:191`:

```html
<img src="profile.webp" alt="Yannick Knieriemen" onerror="...">
```

has **no `width`/`height` attributes**. The `aspect-ratio: 4/3` on the parent `.avatar`
(`index.html:87`) happens to prevent CLS *for the box*, so this is currently masked — but
the masking depends on a CSS rule three layers away staying in sync with the image's real
ratio. If you ever swap the photo for a 1:1 crop, you get silent distortion
(`object-fit: cover` will crop it invisibly) and nobody will notice for months. Put
`width="1200" height="900"` on the `img` so the truth lives with the asset. Also:
`image-rendering: -webkit-optimize-contrast` (`index.html:88`) is a legacy non-standard
hint that modern Chromium interprets as `crispy-edges`-ish downscaling and can make photos
*worse*; it should go.

### 2.3 Faux-bold serif headings — a typographic bug you're already shipping

`.cv-content strong` (`index.html:101`) renders in EB Garamond at the browser-default
`font-weight: 700`. Only 400 and 500 are loaded, so every entry title on the page
(**"Disaggregation of Climate Change Risks by Region"**, **"M.Sc. Economics"**, …) is a
*synthesized* bold — the browser mechanically smears the 500 outlines. On a site whose
whole aesthetic is careful typography, synthesized Garamond bold is visibly muddier than
the real cut. Either load the 600/700 cut (contradicts the diet in §1.1) or — better —
declare `.cv-content strong { font-weight: 500; }` explicitly so you render the true
500 cut you already pay for. One line, visible quality gain.

### 2.4 Entry animation runs blind and ignores motion preferences

`index.html:74`:

```css
section { ... opacity: 0; transform: translateY(24px); animation: fadeUp 0.7s forwards; }
```

Every section — including three that are below the fold — plays the same fade
simultaneously at load, invisibly. The animation has no scroll trigger, so it only ever
functions as "the whole page fades in once," at the cost of starting from `opacity: 0`
(content invisible until CSS parses and the animation starts; on slow devices this reads
as a flash of blank page). And there is **no `prefers-reduced-motion` guard** anywhere in
the file — the fade, the `scroll-behavior: smooth` (`index.html:60`), and the hover
`transform` all play for users who asked the OS to reduce motion. Either make the fade
scroll-triggered per-section (IntersectionObserver, ~6 lines) so it earns its cost, or
delete it; in both cases wrap motion in `@media (prefers-reduced-motion: no-preference)`.

### 2.5 Unthrottled scroll handler doing layout reads

`index.html:365-394`: the `scroll` listener runs on every scroll event and reads
`section.offsetTop` and `document.documentElement.scrollHeight` each time — forced-layout
reads inside the hottest event on the page. At 4 sections this is measurable-but-harmless;
it's still the wrong pattern, and the right one is *less* code: one `IntersectionObserver`
handles active-nav-link detection with zero scroll-time work, leaving only the trivial
back-to-top toggle in the scroll handler. Worth folding into any pass that touches the JS.

### 2.6 `background-attachment: fixed` (`index.html:61`)

Forces repaint-on-scroll of the body gradient on some engines and is ignored on iOS
Safari (where it silently degrades to `scroll`). For a 2-stop linear gradient the cost is
small, but you're paying it on every frame of every scroll for an effect iOS users never
see. `min-height: 100vh` on body with a plain gradient gives the same look without the
flag.

### 2.7 Dead / decorative-only code inventory

- **DM Sans 300** — loaded, zero uses (proof in §1.1).
- **EB Garamond italic** — loaded, one use inside an error-only fallback (§1.1).
- `.avatar-initials` + the `onerror` handler (`index.html:89,191-192`) — a fallback for
  "the repo's own image is missing," a failure mode that can only occur if you delete
  `profile.webp` from your own repo. Defensible paranoia, but it is the *only* reason the
  italic font exists; if the fallback drops the italic style, the font goes too.
- The inline SVG ifo wordmark (`index.html:304-313`) is ~1.3 KB of transform-nested paths
  copied from the Wikimedia SVG without path flattening/rounding. Harmless at this size;
  `svgo` would halve it if you ever care.

---

## 3. Architecture, Maintainability & SEO

### 3.1 Eleven inline `style=""` attributes are the site's main maintenance debt

```
$ grep -c 'style="' index.html
11
```

The worst offender is a fully-styled "link with arrow" pattern duplicated **verbatim**
at `index.html:209` and `index.html:236`:

```html
<a href="..." target="_blank" rel="noopener" style="font-size: 0.8rem; color: var(--accent); text-decoration: none; font-weight: 500; margin-top: 0.5rem; display: inline-block;">
```

plus three identical inline-styled underlined links in the hero (`index.html:173-174`),
an inline-styled eyebrow span (`index.html:168`), and a fully inline-styled CV download
card (`index.html:279-284`). Every new research entry you add will be written by
copy-pasting one of these blocks, and the styles will drift the first time you edit one
copy and forget the others. CLAUDE.md's own convention says "Reuse [CSS variables]; don't
introduce new hex values inline" — the spirit of that rule is being violated in structure
if not in color. Five small classes (`.entry-link`, `.text-link`, `.eyebrow`, `.cv-card`,
plus one for the muted-entry variant at line 215) would absorb all 11 attributes.

### 3.2 Palette drift: the nav bar's background is not your paper color

`index.html:64`: `nav { background: rgba(250,249,247,0.92); }`
`index.html:46`: `--paper: #f9f7f2;` → rgb(249, 247, **242**).

The nav uses rgb(250, 249, **247**) — a cooler near-white that matches nothing in
`:root`. It's a 5-point blue shift on a warm-ivory page, visible where the translucent
nav overlaps the hero. This is precisely the "new hex value inline" your CLAUDE.md
forbids, hidden inside an rgba(). Should be derived from `--paper` (e.g. define
`--paper-rgb: 249 247 242;` and use `rgb(var(--paper-rgb) / 0.92)`).

### 3.3 SEO / metadata: good skeleton, specific holes

What exists is genuinely solid (JSON-LD `Person` with `sameAs`, OG tags, meta
description, google-site-verification). Verified missing:

- **No `<link rel="canonical">`.** GitHub Pages serves this page at both
  `https://yannick-knieriemen.github.io/` and `/index.html`; a canonical tag is one line
  and removes any duplicate-URL ambiguity for Scholar/Google.
- **No `robots.txt`, no `sitemap.xml`** (`ls` proof in session: all absent). For a
  one-pager a sitemap is near-cosmetic, but `robots.txt` absence means crawlers get a
  404 on every visit's first probe; both files are trivial.
- **No 404.html.** Any mistyped deep link (e.g. an old `/cv.pdf` variant or a truncated
  URL in a mail client) gets GitHub's generic 404 with none of your branding or a link home.
- **OG image has no `og:image:width/height/alt`** — harmless for Google, but LinkedIn's
  scraper (your most likely share target) resolves cards faster and more reliably with
  explicit dimensions; and `twitter:card` is `summary` while the 1200×900 photo would
  qualify for `summary_large_image`.
- **`lang` mismatch:** `<html lang="en">` but the Surplus Magazin entry
  (`index.html:230-234`) is German prose. Screen readers will read German text with
  English phonemes. `lang="de"` on those two elements fixes pronunciation and is a
  correctness signal to crawlers.
- **JSON-LD nit:** `"email": "mailto:knieriemen@ifo.de"` — schema.org expects the plain
  address; `alumniOf` (Mannheim) is a free, legitimate enrichment for an academic Person
  entity.

### 3.4 You are running a Jekyll build you don't use, on every single deploy

There is **no `.nojekyll` file** (verified by `ls`). The classic Pages pipeline therefore
runs a full Jekyll pass over the repo on every push — building nothing, since there's no
Jekyll content — before deploying. This adds tens of seconds to every deploy and, more
importantly, is the *only build step in the "no build step" site*, and it's one that can
fail independently (Jekyll chokes on certain file/dir name patterns, e.g. anything
starting with `_`). Your `retry-pages-deploy.yml` exists precisely because this pipeline
sometimes fails — and per §1.4 it can't retry build-phase failures. An empty `.nojekyll`
at the root makes Pages copy files verbatim: faster deploys, one less failure mode.
This is the highest-value one-character change available in this repo.

### 3.5 Structural assessment (for the record)

The one-file architecture is *correct* for this site and should be defended, not
apologized for. The CLAUDE.md decision to revisit only when the publication list outgrows
hand-editing is sound; with 2 research entries and 4 education entries, a generator would
be pure overhead. The `cv.tex → CI → cv.pdf` pipeline is genuinely well-designed
(single source of truth, date coherence between PDF and page). The brittleness is not in
the architecture but in the specific joints flagged above: sed-patching (§1.3), tag
pinning (§1.2), and inline-style duplication (§3.1).

---

## 4. Concrete Execution Blueprint (Phase 2, on your order)

Ranked by measured impact ÷ risk. Items 1–3 are one commit each; item 4 is the only one
touching layout.

**Step 1 — `.nojekyll` (one empty file).** Kills the useless Jekyll build on every
deploy (§3.4). Zero risk, immediate deploy-speed and reliability gain.

**Step 2 — Self-host fonts (§1.1, §2.3).** Download EB Garamond 400/500 and DM Sans
400/500 as latin-subset woff2 (≈70–90 KB total, cached forever), place in `/fonts/`,
replace the three `<link>` tags with four inline `@font-face` rules +
`<link rel="preload" as="font">` for DM Sans 400, drop DM Sans 300 and the italic, and
add `.cv-content strong { font-weight: 500; }` to end faux-bold. Removes both Google
origins from the critical path (~0.8 s measured for the CSS alone from this container)
and the GDPR exposure. Verifiable locally with the existing `python -m http.server`
preview.

**Step 3 — Metadata batch (§3.3).** Canonical link, `robots.txt`, `sitemap.xml`,
`404.html`, `og:image` dimensions, `summary_large_image`, `lang="de"` spans, JSON-LD
email/alumniOf fixes. All additive, no visual change.

**Step 4 — CSS consolidation + hardening batch (§3.1, §3.2, §2.4, §2.5, §1.3).**
Introduce the five classes and delete all 11 inline styles; fix the nav rgba to derive
from `--paper`; wrap animations in `prefers-reduced-motion`; replace the scroll-handler
nav detection with IntersectionObserver; add `git pull --rebase` + a sed-match guard to
`build-cv.yml`; SHA-pin the actions. This is the "easy to maintain manually without AI
oversight" payoff: after it, adding a publication is copying one clean 8-line block with
zero styling decisions.

Everything above was verified against the working tree at commit `07ebc33` during this
session; measurements (byte counts, curl timings, grep counts) are reproduced inline.
