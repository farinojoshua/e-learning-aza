#!/usr/bin/env bash
# Guardrail checks for the AI CI/CD pipeline. Source, don't execute.
# These are the last line of defense - they must be re-checked on the HOST,
# after every single AI invocation, regardless of what claude-settings.ci.json
# already denied inside the container.
set -euo pipefail

SCRIPT_DIR_GUARDRAILS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORBIDDEN_PATHS_FILE="${FORBIDDEN_PATHS_FILE:-$SCRIPT_DIR_GUARDRAILS/../forbidden-paths.txt}"

# Only these branches may ever receive an AI commit/push. One branch per issue.
ALLOWED_BRANCH_REGEX='^ai/issue-[0-9]+-[a-z0-9-]+$'
# These branches may never be pushed to directly by this pipeline.
PROTECTED_BRANCH_REGEX='^(main|master|develop|release/.*)$'

assert_safe_branch() {
  local branch="${1:?assert_safe_branch requires a branch name}"

  if [[ "$branch" =~ $PROTECTED_BRANCH_REGEX ]]; then
    echo "GUARDRAIL VIOLATION: refusing to touch protected branch '$branch'" >&2
    return 1
  fi

  if ! [[ "$branch" =~ $ALLOWED_BRANCH_REGEX ]]; then
    echo "GUARDRAIL VIOLATION: branch '$branch' does not match required pattern '$ALLOWED_BRANCH_REGEX'" >&2
    return 1
  fi

  return 0
}

# Scans the working tree (staged, unstaged, and untracked files) for any path
# that matches a pattern in forbidden-paths.txt. Returns non-zero on any hit.
check_forbidden_paths() {
  [[ -f "$FORBIDDEN_PATHS_FILE" ]] || { echo "GUARDRAIL SETUP ERROR: $FORBIDDEN_PATHS_FILE not found" >&2; return 1; }

  local changed_files
  changed_files="$(git status --porcelain --untracked-files=all | cut -c4-)"
  [[ -z "$changed_files" ]] && return 0

  local -a violations=()
  local pattern file
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      # bash [[ x == pattern ]] glob matching: '*' already spans '/' here,
      # so 'ci/**' behaves the same as 'ci/*' (matches ci/x and ci/x/y).
      if [[ "$file" == $pattern ]]; then
        violations+=("$file  (matched pattern: $pattern)")
      fi
    done <<< "$changed_files"
  done < "$FORBIDDEN_PATHS_FILE"

  if (( ${#violations[@]} > 0 )); then
    echo "GUARDRAIL VIOLATION: forbidden path(s) touched by the AI step:" >&2
    printf '  - %s\n' "${violations[@]}" >&2
    return 1
  fi

  return 0
}
