#!/usr/bin/env bash
# Runs INSIDE the ci-agent container. First AI step: Claude writes ONLY
# tests describing the desired behavior from the issue - no implementation
# yet (red phase of TDD). ai-implement.sh resumes this same session to
# write the code that makes these tests pass. Does NOT touch git - the
# host commits/pushes after re-checking guardrails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${ISSUE_TITLE:?ISSUE_TITLE is required}"
: "${ISSUE_BODY:=}"
: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is required}"

require_numeric ISSUE_NUMBER "$ISSUE_NUMBER"

RESULT_JSON="${AI_RESULT_JSON:-ai-write-tests-result.json}"
MAX_TURNS="${AI_MAX_TURNS:-30}"
SETTINGS_FILE="$SCRIPT_DIR/claude-settings.ci.json"

# Owns the session for this whole issue - written to the workspace so
# ai-implement.sh (and, if needed, ai-fix.sh) can --resume it instead of
# starting from a blank slate. Requires HOME to point at a path under the
# workspace so the session state actually persists across separate
# `podman run` invocations - see the Jenkinsfile.
SESSION_ID_FILE=".claude-session-id"
SESSION_ID="$(cat /proc/sys/kernel/random/uuid)"
echo "$SESSION_ID" > "$SESSION_ID_FILE"

# ISSUE_TITLE / ISSUE_BODY are attacker-controlled (anyone who can open an
# issue controls this text). They are only ever used as plain prompt text
# here, never passed through eval/sh -c, so there is no shell-injection
# surface - but keep it that way if you touch this file.
PROMPT="$(cat <<EOF
You are working on a GitHub issue in an automated CI pipeline, using a
test-driven workflow. This is step 1 of 2: write tests only.

Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}

Instructions:
- Write unit tests that describe the behavior requested in the issue above,
  following the existing test conventions in this repository (see the
  test/ directory for the pattern - node:test + assert, no new test
  framework dependency).
- Do NOT implement the feature yet. It is expected and fine for these tests
  to fail right now (red phase) - the next step implements the code to make
  them pass.
- Write real, meaningful test cases that would catch actual bugs: cover the
  success path AND the edge cases / error conditions implied by the issue
  (invalid input, not-found cases, boundary values, etc.), not just a single
  happy-path assertion. The next step will be required to reach 95% line/
  branch/function coverage against these tests, so thin tests just cause
  more retries later.
- Do NOT modify: Jenkinsfile, anything under ci/ or podman/, .github/workflows/**,
  any .env/secret/credential/key file, or anything under k8s/, deploy/, infra/,
  terraform/. These paths are off-limits in this pipeline and are enforced
  outside of your control - attempting to edit them wastes your turns.
- Do NOT run git commit, git push, or any gh command. The pipeline handles
  commit and push itself after you finish.
- Do NOT add any new npm dependency.
EOF
)"

log "Invoking Claude Code CLI to write tests for issue #${ISSUE_NUMBER} (session $SESSION_ID)"
if ! claude -p "$PROMPT" \
  --session-id "$SESSION_ID" \
  --settings "$SETTINGS_FILE" \
  --permission-mode acceptEdits \
  --max-turns "$MAX_TURNS" \
  --output-format json > "$RESULT_JSON"; then
  die "Claude Code CLI exited non-zero while writing tests for issue #${ISSUE_NUMBER}"
fi

if command -v jq >/dev/null 2>&1 && jq -e '.is_error == true' "$RESULT_JSON" >/dev/null 2>&1; then
  log "Claude reported an error. Raw result:"
  cat "$RESULT_JSON" >&2
  die "Claude Code CLI reported is_error=true while writing tests for issue #${ISSUE_NUMBER}"
fi

log "AI write-tests step finished, result written to $RESULT_JSON"
