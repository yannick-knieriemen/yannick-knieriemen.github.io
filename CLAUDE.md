# CLAUDE.md — Personal Academic Homepage

## Overview
- Live at https://yannick-knieriemen.github.io/ (GitHub Pages).
- Deploys automatically on every push to `main` (~1 minute). There is no
  build step and no branch protection — push = publish.
- Workflow: edit locally, preview, push. Never use the GitHub web-UI
  file upload (that was the old workflow; it left messy delete/re-upload
  commits in the history).

## Files
- `index.html` — the entire site: one page, inline CSS and JS. Some CSS
  comments are in German; that's fine.
- `cv.pdf` — compiled CV (binary, replaced manually; source lives in LaTeX
  elsewhere, not in this repo).
- `profile.webp` — profile photo.

## Conventions
- Keep the site a plain static one-pager — no static site generator, no
  framework, no build step. Revisit only when the publication list grows
  enough that generating the Research section from a BibTeX file beats
  hand-editing (a small Python script would fit; decision 2026-07-06).
- Colors/fonts are CSS variables in `:root` (EB Garamond headings,
  DM Sans body). Reuse them; don't introduce new hex values inline.
- The site must stay fully static — GitHub Pages serves it as-is.

## Updating the CV (manual, two steps!)
1. Replace `cv.pdf` with the new compiled PDF.
2. Update the static date inside `<span id="cv-date">` in `index.html`
   ("View my full CV (…)"). It is intentionally NOT automatic — it should
   reflect when the CV changed, not when the page was last deployed.

The footer "Last updated" date IS automatic (`document.lastModified`,
i.e. the last deploy of index.html) — leave it as is.

## Preview
- `python -m http.server 8000` in the repo root, then http://localhost:8000
  (on Linux use `python3` if `python` doesn't exist).
- Claude Code: `.claude/launch.json` defines a `homepage` preview server.

## CI
- `.github/workflows/link-check.yml` — lychee link check, monthly + manual
  trigger. Failures open a GitHub issue. linkedin.com is excluded (it
  blocks bots and produces false positives).

## Cross-platform
Everything here works identically on Windows and Linux: plain git + static
files. No machine-specific config belongs in this repo.
