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
- `cv/cv.tex` — the CV's LaTeX source (single source of truth; migrated
  from Overleaf 2026-07-06, the old Overleaf project is retired).
- `cv.pdf` — compiled CV. NEVER edit or replace by hand: CI builds it
  from cv/cv.tex (see below).
- `profile.webp` — profile photo.

## Conventions
- Keep the site a plain static one-pager — no static site generator, no
  framework, no build step. Revisit only when the publication list grows
  enough that generating the Research section from a BibTeX file beats
  hand-editing (a small Python script would fit; decision 2026-07-06).
- Colors/fonts are CSS variables in `:root` (EB Garamond headings,
  DM Sans body). Reuse them; don't introduce new hex values inline.
- The site must stay fully static — GitHub Pages serves it as-is.

## Updating the CV (fully automated)
Edit `cv/cv.tex` and push. That's the whole workflow. CI
(`.github/workflows/build-cv.yml`) then:
1. compiles the PDF with TeX Live (`xu-cheng/latex-action`),
2. replaces the root `cv.pdf`,
3. bumps the static date in `<span id="cv-date">` in `index.html`,
4. commits + pushes, which redeploys the site.

Do NOT hand-edit `cv.pdf` or the cv-date span — both are written by CI.
The date inside the PDF (`\today`) and the date on the page therefore
always agree (both = build date). Note the CI commit lands ~2 min after
the push: `git pull` before further local work.

For a fast local preview without a TeX install, Tectonic works on both
OSes: `tectonic cv/cv.tex` (output is gitignored). Optional — pushing and
waiting for CI is fine.

The footer "Last updated" date is automatic (`document.lastModified`,
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
