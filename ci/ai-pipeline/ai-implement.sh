#!/usr/bin/env bash
# Runs INSIDE the ci-agent container. Step 2 of 2 in the TDD workflow:
# resumes the session from ai-write-tests.sh and implements the code that
# makes those tests pass (green phase). Does NOT touch git - the host
# commits/pushes after re-checking guardrails. See lib/guardrails.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${ISSUE_TITLE:?ISSUE_TITLE is required}"
: "${ISSUE_BODY:=}"
: "${COVERAGE_THRESHOLD:?COVERAGE_THRESHOLD is required}"
# Auth via Claude subscription (Pro/Max), not a pay-per-token API key. Token
# comes from running `claude setup-token` once, interactively, on any
# machine logged into the subscription - see SETUP.md.
: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is required}"

require_numeric ISSUE_NUMBER "$ISSUE_NUMBER"

RESULT_JSON="${AI_RESULT_JSON:-ai-implement-result.json}"
MAX_TURNS="${AI_MAX_TURNS:-30}"
CLAUDE_MODEL="${AI_MODEL:-sonnet}"
SETTINGS_FILE="$SCRIPT_DIR/claude-settings.ci.json"

# Resume the ai-write-tests.sh session (same HOME as that step, mounted from
# the workspace) so this step sees the exact tests it needs to satisfy,
# instead of re-deriving requirements from the issue text alone. Falls back
# to a fresh session if the file's missing, which still works, just costs
# more tokens re-establishing context.
SESSION_ID_FILE=".claude-session-id"
RESUME_ARGS=()
if [[ -f "$SESSION_ID_FILE" ]]; then
  RESUME_ARGS=(--resume "$(cat "$SESSION_ID_FILE")")
  log "Resuming write-tests session $(cat "$SESSION_ID_FILE") to implement"
else
  log "No prior session file found, starting a fresh session to implement"
fi

# ISSUE_TITLE / ISSUE_BODY are attacker-controlled (anyone who can open an
# issue controls this text). They are only ever used as plain prompt text
# here, never passed through eval/sh -c, so there is no shell-injection
# surface - but keep it that way if you touch this file.
PROMPT="$(cat <<EOF
This is step 2 of 2 of the test-driven workflow for issue #${ISSUE_NUMBER}:
${ISSUE_TITLE}

The tests for this issue already exist (you just wrote them in the previous
step). Now implement the code that makes them pass.

Instructions:
- Implement the change, following the existing code style and conventions in
  this repository. Do not weaken, skip, or delete the tests you just wrote to
  make them pass artificially - make the implementation actually correct.
- The validation stage will run the test suite with
  \`node --test --experimental-test-coverage\` and requires at least
  ${COVERAGE_THRESHOLD}% line, branch, and function coverage. If your
  implementation leaves branches uncovered, add the missing test cases too
  (edge cases, error paths) rather than leaving them untested.
- Do NOT modify: Jenkinsfile, anything under ci/ or podman/, .github/workflows/**,
  any .env/secret/credential/key file, or anything under k8s/, deploy/, infra/,
  terraform/. These paths are off-limits in this pipeline and are enforced
  outside of your control - attempting to edit them wastes your turns.
- Do NOT run git commit, git push, or any gh command. The pipeline handles
  commit and push itself after you finish.
- Do NOT add any new npm dependency.
EOF
)"

log "Invoking Claude Code CLI to implement issue #${ISSUE_NUMBER}"
if ! claude -p "$PROMPT" \
  "${RESUME_ARGS[@]}" \
  --model "$CLAUDE_MODEL" \
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
