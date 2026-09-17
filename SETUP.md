# AI CI/CD pipeline - one-time setup

This pipeline is a template. It was designed without access to your real
Jenkins/GitHub setup, so read this fully before enabling the webhook - several
values below are placeholders you must change.

## 1. Edit the placeholders

- `Jenkinsfile` -> `GIT_REPO_SLUG` parameter default: set to your real
  `owner/repo`. This is deliberately hardcoded rather than read from the
  webhook payload, so a forged webhook can never point this job at an
  arbitrary repository.
- `sonar-project.properties` -> `sonar.projectKey`, `sonar.sources`.
- `podman/ci-agent.Containerfile` -> version ARGs (Trivy, sonar-scanner) -
  bump and re-pin periodically, don't float on `latest`.

## 2. Jenkins plugins required

- Generic Webhook Trigger
- SonarQube Scanner (Jenkins plugin, not just the CLI)
- Pipeline, Git, Credentials Binding (usually already installed)

## 3. Jenkins agent prerequisites

A static agent labeled `podman` with:
- `podman` on PATH (rootless is fine)
- `git`
- enough disk for the built `ci-agent` image (rebuilt every run, removed in
  the `post { always { ... } }` block)

No Docker daemon is required anywhere - everything shells out to `podman`
directly, matching this VM's existing container setup.

## 4. Jenkins credentials (Manage Jenkins > Credentials)

| ID                          | Type        | Used for                                   |
|------------------------------|-------------|---------------------------------------------|
| `github-ai-pipeline-pat`    | Secret text | git push, `gh pr create`, `gh issue comment` |
| `claude-code-oauth-token`   | Secret text | Claude Code CLI auth (subscription, not API key) |

The GitHub PAT should be a **fine-grained** token scoped to this one repo
only, with `Contents: Read and write` and `Pull requests: Read and write`.
Nothing broader.

### Claude auth: subscription (Pro/Max), not a pay-per-token API key

This pipeline authenticates Claude Code CLI using a **Claude subscription**
token instead of an Anthropic API key, so usage is covered by an existing
Pro/Max plan rather than billed per token.

1. On any machine where you're logged into Claude Code with your
   subscription, run:
   ```
   claude setup-token
   ```
   This prints a long-lived token meant for exactly this kind of headless/CI
   use.
2. Paste that token into Jenkins as a **Secret text** credential with ID
   `claude-code-oauth-token`.
3. Verify the exact command name and the env var Claude Code CLI expects
   (`CLAUDE_CODE_OAUTH_TOKEN` is what the pipeline scripts read) against
   `claude --help` / current docs for the CLI version pinned in
   `podman/ci-agent.Containerfile` - this is a newer, less-documented flow
   and naming may have shifted since.

**Trade-off to keep in mind:** subscription plans are rate-limited for one
human's interactive use. If this pipeline ends up firing often (many issues,
each with multiple self-heal attempts), it can burn through that limit
faster than a pay-as-you-go API key would, and a stalled/rate-limited build
just fails - there's no automatic fallback to API billing. If that becomes a
problem, switch back to an Anthropic API key by swapping
`CLAUDE_CODE_OAUTH_TOKEN` for `ANTHROPIC_API_KEY` in
`ci/ai-pipeline/ai-implement.sh`, `ai-fix.sh`, and the `Jenkinsfile`
`environment {}` block - everything else stays the same.

## 5. SonarQube server

Manage Jenkins > System > SonarQube servers: add a server named exactly
`SonarQube` (matches `withSonarQubeEnv('SonarQube')` in the Jenkinsfile),
pointing at your SonarQube instance, with its own token credential attached
there (not a separate Jenkinsfile credential ID - the plugin injects
`SONAR_HOST_URL`/`SONAR_AUTH_TOKEN` for you).

Also configure a SonarQube webhook back to Jenkins
(`<jenkins-url>/sonarqube-webhook/`) so `waitForQualityGate()` doesn't have to
poll.

## 6. Create the Jenkins job

- Job type: **Pipeline** (not Multibranch - this job is triggered by a
  webhook carrying issue data, not by branch pushes).
- Pipeline script: **from SCM**, pointing at this repo's `main` branch,
  script path `Jenkinsfile`.

## 7. GitHub webhook

Repo Settings > Webhooks > Add webhook:
- Payload URL: `https://<your-jenkins-host>/generic-webhook-trigger/invoke?token=github-issue-webhook-token`
- Content type: `application/json`
- Events: select **Issues** only (not "Send me everything")

## 8. The `ai-task` label as an access gate

The pipeline only runs on issues labeled `ai-task`
(`Jenkinsfile` -> "Guard: validate webhook input" stage). This doubles as
access control: on most repos only collaborators with triage/write access can
apply labels, so a random public user opening an issue cannot trigger the
pipeline just by writing a good description. If your repo has open triage
permissions (labels open to anyone), add an author allow-list check in that
same stage before relying on this.

## 9. Why deploy isn't here

There is no deploy stage in the `Jenkinsfile`, on purpose, and a comment at
the top of the file says so explicitly. This pipeline's job ends at opening a
PR to `main`. Whatever you already do to deploy stays exactly as it is,
triggered by a human, outside of Jenkins automation.

## 9b. Add a CLAUDE.md to whatever repo you point this at

Claude Code CLI auto-loads `CLAUDE.md` from the repo root at the start of
every session, including the pipeline's headless runs - put your project's
conventions, test setup, and coverage/dependency rules there once instead
of restating them in every prompt in `ci/ai-pipeline/*.sh`. See this repo's
own `CLAUDE.md` for an example of what that looks like.

## 10. Before trusting this in production

- This was written and syntax-checked (`bash -n`, brace-balance check on the
  Jenkinsfile) but **never run against a live Jenkins instance** - there is
  none in this sandbox to test against.
- Verify the Claude Code CLI flags used in `ci/ai-pipeline/ai-implement.sh`
  and `ai-fix.sh` (`--settings`, `--permission-mode`, `--max-turns`,
  `--output-format json`) against `claude --help` for whatever CLI version
  you pin in `podman/ci-agent.Containerfile` - flag names can change between
  releases.
- Test end-to-end on a disposable test repo/branch and a throwaway issue
  before pointing `GIT_REPO_SLUG` at anything real.
- Read `ci/ai-pipeline/forbidden-paths.txt` and
  `ci/ai-pipeline/claude-settings.ci.json` and add any project-specific
  paths you don't want the AI touching (they're deliberately kept in sync -
  update both when you change one).
