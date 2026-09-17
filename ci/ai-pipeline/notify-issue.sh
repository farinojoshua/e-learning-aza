#!/usr/bin/env bash
# Posts a success or failure comment back on the originating GitHub issue.
# Runs inside the ci-agent container (has gh CLI); never invoked by Claude.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${STATUS:?STATUS must be 'success' or 'failure'}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required for gh}"

require_numeric ISSUE_NUMBER "$ISSUE_NUMBER"

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

case "$STATUS" in
  success)
    : "${PR_URL:?PR_URL is required for a success notification}"
    cat > "$BODY_FILE" <<EOF
AI pipeline finished: implementation, unit tests, SonarQube, and Trivy scan
all passed.

Pull request ready for review: ${PR_URL}

Deployment is not automated - review, merge, then deploy manually as usual.
EOF
    ;;
  failure)
    : "${BUILD_URL:?BUILD_URL is required for a failure notification}"
    : "${FAILED_STAGE:?FAILED_STAGE is required for a failure notification}"
    : "${MAX_FIX_ATTEMPTS:?MAX_FIX_ATTEMPTS is required for a failure notification}"
    cat > "$BODY_FILE" <<EOF
AI pipeline could not produce a passing change after ${MAX_FIX_ATTEMPTS} fix
attempt(s). The last failure was in stage **${FAILED_STAGE}**.

No pull request was opened. Build log: ${BUILD_URL}

A human needs to take over from here.
EOF
    ;;
  *)
    die "Unknown STATUS: $STATUS"
    ;;
esac

log "Posting ${STATUS} comment to issue #${ISSUE_NUMBER}"
gh issue comment "$ISSUE_NUMBER" --body-file "$BODY_FILE"
