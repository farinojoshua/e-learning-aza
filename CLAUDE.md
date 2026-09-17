# CLAUDE.md

This file is read automatically by Claude Code CLI at the start of every
session in this repo, including the AI CI/CD pipeline's headless runs -
put anything here that would otherwise have to be re-explained in every
prompt.

## What this repo is

`e-learning-aza`: a small course-catalog demo app, kept deliberately
dependency-free (see `package.json` - only built-in Node.js). It doubles as
the test project for the AI CI/CD pipeline defined in `Jenkinsfile` / `ci/`
/ `podman/`.

## Code conventions

- Plain Node.js ES modules (`"type": "module"` in package.json), no
  framework, no TypeScript.
- One module per concern under `src/`, named exports only (see
  `src/courses.js` for the pattern: an in-memory `Map`/array as the data
  store, plain functions, `throw new Error('message')` for invalid states -
  no custom error classes, no result objects).
- Tests live under `test/`, one `*.test.js` file per `src/` module, using
  Node's built-in test runner (`node:test` + `node:assert/strict`). Do not
  add a test framework dependency (Jest, Mocha, etc.) - `npm test` runs
  `node --test` directly.

## Testing & coverage

- `npm test` runs the full suite. The CI pipeline additionally enforces
  `--experimental-test-coverage` with a minimum line/branch/function
  coverage threshold (currently 95%, see `COVERAGE_THRESHOLD` in
  `Jenkinsfile`) - a shortfall fails the build.
- When writing tests, cover the success path AND the edge cases implied by
  the requirement (invalid input, not-found, empty/boundary values) - thin
  happy-path-only tests just cause more CI retries later.

## Dependencies

Do not add new npm dependencies without being explicitly asked to. This
repo is kept dependency-free on purpose (faster `npm ci`, smaller attack
surface, no lockfile drift) - reach for a built-in Node.js module first.

## If you're the AI CI/CD pipeline (ai-write-tests.sh / ai-implement.sh / ai-fix.sh)

- Never run `git commit`, `git push`, or any `gh` command - the pipeline
  scripts do that themselves after re-checking guardrails.
- Never touch `Jenkinsfile`, anything under `ci/` or `podman/`,
  `.github/workflows/**`, any `.env`/secret/credential/key file, or
  anything under `k8s/`, `deploy/`, `infra/`, `terraform/` - these are
  enforced outside your control (see `ci/ai-pipeline/claude-settings.ci.json`
  and `ci/ai-pipeline/lib/guardrails.sh`); attempting to edit them just
  wastes turns.
- The workflow is test-driven, split across two CLI invocations that share
  one resumed session: tests are written first (red), then code is
  implemented against them (green). If you're in the implement or fix step,
  the tests already exist - read them before writing implementation code.
