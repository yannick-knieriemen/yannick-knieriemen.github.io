#!/usr/bin/env bash
# SessionStart hook: keep the local checkout in sync with origin.
#
# CI pushes to main on its own (cv.pdf build, cv-date bump), and edits can
# land from other machines or cloud sessions. Starting a session on a stale
# main means the first push gets rejected and needs a rebase.
#
# Fast-forward only: never merges, never rebases, never touches local work.
# Bails out quietly when the tree is dirty or the branch has diverged.
set -u

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

emit() {
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1" "$1"
}

git fetch --quiet origin 2>/dev/null || { emit "git fetch failed (offline?) — repo may be out of date."; exit 0; }

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || exit 0
behind=$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)
[ "$behind" -eq 0 ] && exit 0

if [ -n "$(git status --porcelain)" ]; then
  emit "$behind commit(s) behind $upstream — auto-pull skipped, working tree is dirty."
  exit 0
fi

if git merge --ff-only --quiet "$upstream" 2>/dev/null; then
  emit "Pulled $behind commit(s) from $upstream."
else
  emit "$behind commit(s) behind $upstream, but fast-forward is not possible (branches diverged) — resolve manually."
fi
