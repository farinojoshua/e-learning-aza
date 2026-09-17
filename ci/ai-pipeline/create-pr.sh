#!/usr/bin/env bash
# Opens the final PR to the base branch once validation has passed. Runs
# inside the ci-agent container (has gh CLI); never invoked by Claude itself.
# Prints the PR URL to stdout (and only the PR URL) on success.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/guardrails.sh
source "$SCRIPT_DIR/lib/guardrails.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${ISSUE_TITLE:?ISSUE_TITLE is required}"
: "${BRANCH_NAME:?BRANCH_NAME is required}"
: "${BASE_BRANCH:=main}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required for gh}"

require_numeric ISSUE_NUMBER "$ISSUE_NUMBER"
assert_safe_branch "$BRANCH_NAME" || die "Refusing to open a PR from an unsafe branch"

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

cat > "$BODY_FILE" <<EOF
Closes #${ISSUE_NUMBER}

This PR was generated automatically by the AI CI pipeline from GitHub issue
#${ISSUE_NUMBER}, and has passed build, unit tests, SonarQube analysis, and a
Trivy scan on branch \`${BRANCH_NAME}\`.

**This still needs a human review before merge.** Deployment is a separate,
manual step and is never triggered by merging this PR.

Validation summary:
- Build: passed
- Unit tests: passed
- SonarQube quality gate: passed
- Trivy scan (HIGH/CRITICAL): passed
EOF

# Idempotent: creates the label on first run, silently no-ops on every run
# after that. Without this, `gh pr create --label` fails outright on a repo
# where nobody has manually created "ai-generated" yet.
gh label create "ai-generated" \
  --color "5319E7" \
  --description "Opened automatically by the AI CI pipeline" \
  2>/dev/null || true

log "Opening PR: ${BRANCH_NAME} -> ${BASE_BRANCH}"
gh pr create \
  --title "AI: ${ISSUE_TITLE} (closes #${ISSUE_NUMBER})" \
  --body-file "$BODY_FILE" \
  --base "$BASE_BRANCH" \
  --head "$BRANCH_NAME" \
  --label "ai-generated"
