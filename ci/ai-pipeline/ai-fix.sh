#!/usr/bin/env bash
# Runs INSIDE the ci-agent container. Invokes Claude Code CLI to fix a failed
# validation stage (build/test/sonarqube/trivy) using the captured log tail.
# Does NOT touch git - the host commits/pushes after re-checking guardrails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${FAILED_STAGE:?FAILED_STAGE is required}"
: "${FAILURE_LOG_FILE:?FAILURE_LOG_FILE is required}"
: "${ATTEMPT:?ATTEMPT is required}"
: "${MAX_FIX_ATTEMPTS:?MAX_FIX_ATTEMPTS is required}"
# Auth via Claude subscription (Pro/Max), not a pay-per-token API key. See
# SETUP.md for how CLAUDE_CODE_OAUTH_TOKEN is generated (`claude setup-token`).
: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is required}"

require_numeric ISSUE_NUMBER "$ISSUE_NUMBER"
require_numeric ATTEMPT "$ATTEMPT"
require_numeric MAX_FIX_ATTEMPTS "$MAX_FIX_ATTEMPTS"
[[ -f "$FAILURE_LOG_FILE" ]] || die "Failure log file not found: $FAILURE_LOG_FILE"

RESULT_JSON="${AI_RESULT_JSON:-ai-fix-result.json}"
MAX_TURNS="${AI_MAX_TURNS:-30}"
SETTINGS_FILE="$SCRIPT_DIR/claude-settings.ci.json"
LOG_EXCERPT="$(tail -c 8000 "$FAILURE_LOG_FILE")"

PROMPT="$(cat <<EOF
You are fixing a CI pipeline failure in an automated pipeline, for issue
#${ISSUE_NUMBER}. This is fix attempt ${ATTEMPT} of ${MAX_FIX_ATTEMPTS}. If this
attempt does not fix the problem, the pipeline stops here and a human takes
over - so make a real, targeted fix, not a superficial one.

The pipeline stage "${FAILED_STAGE}" failed. Here is the tail of its output:

--- BEGIN LOG ---
${LOG_EXCERPT}
--- END LOG ---

Instructions:
- Diagnose the root cause from the log and fix it in the application code or
  tests in this repository checkout.
- Do NOT modify: Jenkinsfile, anything under ci/ or podman/, .github/workflows/**,
  any .env/secret/credential/key file, or anything under k8s/, deploy/, infra/,
  terraform/. These paths are off-limits in this pipeline and are enforced
  outside of your control.
- Do NOT run git commit, git push, or any gh command. The pipeline handles
  commit and push itself after you finish.
- Do not weaken, skip, or delete tests just to make the stage pass - fix the
  underlying issue. If the failure is in the tests themselves because the
  tests were wrong, fix the test logic, don't remove coverage.
- If the log above is a coverage-threshold shortfall (line/branch/function %
  below the required minimum, with a list of uncovered lines), add test
  cases that exercise those specific lines/branches - do not lower the
  threshold or delete the coverage check, and don't add tests that don't
  actually assert anything just to touch a line.
EOF
)"

# Resume the AI Implement session if we have one (same HOME as that step,
# mounted from the workspace - see the Jenkinsfile), so this fix attempt
# doesn't have to re-explore the repo from a blank slate. Falls back to a
# fresh session if the file's missing, which just costs more tokens, not
# correctness.
SESSION_ID_FILE=".claude-session-id"
RESUME_ARGS=()
if [[ -f "$SESSION_ID_FILE" ]]; then
  RESUME_ARGS=(--resume "$(cat "$SESSION_ID_FILE")")
  log "Resuming session $(cat "$SESSION_ID_FILE") for this fix attempt"
else
  log "No prior session file found, starting a fresh session for this fix attempt"
fi

log "Invoking Claude Code CLI to fix '${FAILED_STAGE}' (attempt ${ATTEMPT}/${MAX_FIX_ATTEMPTS})"
if ! claude -p "$PROMPT" \
  "${RESUME_ARGS[@]}" \
  --settings "$SETTINGS_FILE" \
  --permission-mode acceptEdits \
  --max-turns "$MAX_TURNS" \
  --output-format json > "$RESULT_JSON"; then
  die "Claude Code CLI exited non-zero while fixing '${FAILED_STAGE}'"
fi

if command -v jq >/dev/null 2>&1 && jq -e '.is_error == true' "$RESULT_JSON" >/dev/null 2>&1; then
  log "Claude reported an error. Raw result:"
  cat "$RESULT_JSON" >&2
  die "Claude Code CLI reported is_error=true while fixing '${FAILED_STAGE}'"
fi

log "AI fix step finished, result written to $RESULT_JSON"
