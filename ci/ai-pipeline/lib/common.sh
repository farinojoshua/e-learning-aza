#!/usr/bin/env bash
# Shared helpers for the AI CI/CD pipeline scripts. Source, don't execute.
set -euo pipefail

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Sets the bot identity used for every AI-authored commit, so `git blame` and
# GitHub always show these commits as coming from the pipeline, never a human.
configure_git_bot_identity() {
  git config user.name "${AI_GIT_BOT_NAME:-ai-pipeline-bot}"
  git config user.email "${AI_GIT_BOT_EMAIL:-ai-pipeline-bot@users.noreply.github.com}"
}

# Reduces an arbitrary (attacker-controlled) issue title down to a safe
# [a-z0-9-] charset before it's ever used to build a branch name or path.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-40
}

# Fails loudly if $1 is not a plain positive integer. Used to validate
# ISSUE_NUMBER (attacker-controlled webhook input) before it's used anywhere.
require_numeric() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be numeric, got: '$value'"
}
