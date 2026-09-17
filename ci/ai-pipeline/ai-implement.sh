#!/usr/bin/env bash
# Runs INSIDE the ci-agent container. Invokes Claude Code CLI to implement a
# GitHub issue. Does NOT touch git (no commit/push) - the host does that
# after re-checking guardrails. See ci/ai-pipeline/lib/guardrails.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${ISSUE_TITLE:?ISSUE_TITLE is required}"
: "${ISSUE_BODY:=}"
# Auth via Claude subscription (Pro/Max), not a pay-per-token API key. Token
# comes from running `claude setup-token` once, interactively, on any
# machine logged into the subscription - see SETUP.md.
: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is required}"

require_numeric ISSUE_NUMBER "$ISSUE_NUMBER"

RESULT_JSON="${AI_RESULT_JSON:-ai-implement-result.json}"
MAX_TURNS="${AI_MAX_TURNS:-30}"
SETTINGS_FILE="$SCRIPT_DIR/claude-settings.ci.json"

# ISSUE_TITLE / ISSUE_BODY are attacker-controlled (anyone who can open an
# issue controls this text). They are only ever used as plain prompt text
# here, never passed through eval/sh -c, so there is no shell-injection
# surface - but keep it that way if you touch this file.
PROMPT="$(cat <<EOF
You are implementing a GitHub issue in an automated CI pipeline. Work only
inside this repository checkout.

Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}

Instructions:
- Implement the change described above, following the existing code style and
  conventions in this repository.
- Add or update unit tests that cover the change. Do not skip writing tests.
- Do NOT modify: Jenkinsfile, anything under ci/ or podman/, .github/workflows/**,
  any .env/secret/credential/key file, or anything under k8s/, deploy/, infra/,
  terraform/. These paths are off-limits in this pipeline and are enforced
  outside of your control - attempting to edit them wastes your turns.
- Do NOT run git commit, git push, or any gh command. The pipeline handles
  commit and push itself after you finish.
- Keep the change scoped to what the issue asks for.
EOF
)"

log "Invoking Claude Code CLI to implement issue #${ISSUE_NUMBER}"
if ! claude -p "$PROMPT" \
  --settings "$SETTINGS_FILE" \
  --permission-mode acceptEdits \
  --max-turns "$MAX_TURNS" \
  --output-format json > "$RESULT_JSON"; then
  die "Claude Code CLI exited non-zero while implementing issue #${ISSUE_NUMBER}"
fi

if command -v jq >/dev/null 2>&1 && jq -e '.is_error == true' "$RESULT_JSON" >/dev/null 2>&1; then
  log "Claude reported an error. Raw result:"
  cat "$RESULT_JSON" >&2
  die "Claude Code CLI reported is_error=true while implementing issue #${ISSUE_NUMBER}"
fi

log "AI implement step finished, result written to $RESULT_JSON"
