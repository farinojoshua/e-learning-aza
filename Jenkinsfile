// =============================================================================
// AI-driven Issue -> Code -> PR pipeline.
//
// Flow: GitHub Issue (labeled "ai-task") opened -> webhook triggers this job ->
// branch created -> Claude Code CLI implements the issue + tests -> build/test/
// SonarQube/Trivy run -> on failure, log is fed back to Claude Code CLI for a
// bounded number of fix attempts -> once green, a PR is opened against
// BASE_BRANCH for human review.
//
// DEPLOY IS INTENTIONALLY NOT PART OF THIS FILE. This pipeline stops at
// opening a Pull Request. Do not add a deploy stage here - this project is
// payment-related and deployment must remain a manual, human-triggered action
// completely outside of Jenkins automation. If you're tempted to add one,
// stop and talk to whoever owns the payment-compliance requirement instead.
//
// SECURITY NOTE: ISSUE_TITLE / ISSUE_BODY / ISSUE_LABELS below come straight
// from the GitHub webhook payload, i.e. from whoever opened the issue - they
// are UNTRUSTED input. Every reference to them in this file goes through a
// real shell environment variable inside single-quoted Groovy script blocks
// (`'''...$VAR...'''`), never through Groovy GString interpolation
// (`"""...${env.ISSUE_TITLE}..."""`). Do not "simplify" that pattern - Groovy
// string interpolation of these fields is a shell-injection hole (the same
// class of bug as the well-known GitHub Actions "script injection" CVEs).
// =============================================================================

pipeline {
  agent { label 'podman' }

  parameters {
    string(name: 'MAX_FIX_ATTEMPTS', defaultValue: '3',
           description: 'Max self-heal (validate -> AI fix) attempts before giving up')
    string(name: 'BASE_BRANCH', defaultValue: 'main',
           description: 'Branch the generated PR targets')
    string(name: 'GIT_REPO_SLUG', defaultValue: 'farinojoshua/e-learning-aza',
           description: 'owner/repo on github.com this job operates on. ' +
                         'Deliberately NOT read from the webhook payload, so a ' +
                         'crafted webhook can never redirect this job at an ' +
                         'arbitrary repo.')
  }

  options {
    timeout(time: 60, unit: 'MINUTES')
    disableConcurrentBuilds()
  }

  triggers {
    GenericTrigger(
      genericVariables: [
        [key: 'ISSUE_ACTION', value: '$.action'],
        [key: 'ISSUE_NUMBER', value: '$.issue.number'],
        [key: 'ISSUE_TITLE',  value: '$.issue.title'],
        [key: 'ISSUE_BODY',   value: '$.issue.body'],
        [key: 'ISSUE_LABELS', value: '$.issue.labels[*].name']
      ],
      causeString: 'Triggered by a GitHub issue webhook',
      token: 'github-issue-webhook-token',
      printContributedVariables: false,
      printPostContent: false,
      // Only fire on "opened" - edits/closes/relabels must not re-trigger a run.
      regexpFilterText: '$ISSUE_ACTION',
      regexpFilterExpression: '^opened$'
    )
  }

  environment {
    // Fine-grained PAT, scope: contents:write + pull-requests:write on
    // GIT_REPO_SLUG only. Bound as Secret Text -> single GITHUB_TOKEN var.
    GITHUB_TOKEN      = credentials('github-ai-pipeline-pat')
    // Claude subscription (Pro/Max) token, not an API key - generated once via
    // `claude setup-token` (see SETUP.md), stored as a Jenkins Secret text.
    CLAUDE_CODE_OAUTH_TOKEN = credentials('claude-code-oauth-token')
    CI_AGENT_IMAGE    = "localhost/ci-agent:${env.BUILD_NUMBER}"
  }

  stages {

    stage('Guard: validate webhook input') {
      steps {
        script {
          if (!(env.ISSUE_LABELS ?: '').contains('ai-task')) {
            currentBuild.result = 'NOT_BUILT'
            error("Issue #${env.ISSUE_NUMBER ?: '?'} is missing the 'ai-task' label - skipping. " +
                  "(This label is also your access-control gate: only collaborators who can " +
                  "label issues can trigger this pipeline. If this repo has open triage " +
                  "permissions, add an author allow-list check here too.)")
          }
          if (!((env.ISSUE_NUMBER ?: '') ==~ /^[0-9]+$/)) {
            error("ISSUE_NUMBER from the webhook payload was not numeric: '${env.ISSUE_NUMBER}'")
          }
        }
      }
    }

    stage('Prepare') {
      steps {
        sh '''
          set -euo pipefail
          find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
          git clone --branch "$BASE_BRANCH" --single-branch \
            "https://github.com/${GIT_REPO_SLUG}.git" .
          . ci/ai-pipeline/lib/common.sh
          configure_git_bot_identity
        '''
        script {
          // slugify runs in bash, output is guaranteed [a-z0-9-] only - safe
          // to Groovy-interpolate from this point on, unlike the raw title.
          env.SLUG = sh(
            script: '. ci/ai-pipeline/lib/common.sh; slugify "$ISSUE_TITLE"',
            returnStdout: true
          ).trim()
          env.BRANCH_NAME = "ai/issue-${env.ISSUE_NUMBER}-${env.SLUG}"
        }
        sh '''
          set -euo pipefail
          . ci/ai-pipeline/lib/guardrails.sh
          assert_safe_branch "$BRANCH_NAME"
          git checkout -B "$BRANCH_NAME"
          podman build -t "$CI_AGENT_IMAGE" -f podman/ci-agent.Containerfile .
        '''
      }
    }

    stage('AI Implement') {
      steps {
        sh '''
          set -euo pipefail
          podman run --rm \
            -v "$WORKSPACE:/workspace:Z" -w /workspace \
            -e ISSUE_NUMBER -e ISSUE_TITLE -e ISSUE_BODY -e CLAUDE_CODE_OAUTH_TOKEN \
            "$CI_AGENT_IMAGE" \
            ci/ai-pipeline/ai-implement.sh
        '''
        sh '''
          set -euo pipefail
          . ci/ai-pipeline/lib/guardrails.sh
          check_forbidden_paths
          assert_safe_branch "$BRANCH_NAME"
          git add -A
          git commit -m "AI: implement issue #${ISSUE_NUMBER} - ${ISSUE_TITLE}"
          git push "https://x-access-token:${GITHUB_TOKEN}@github.com/${GIT_REPO_SLUG}.git" "$BRANCH_NAME"
        '''
      }
    }

    stage('Validate with bounded self-heal') {
      steps {
        script {
          int maxAttempts = params.MAX_FIX_ATTEMPTS.toInteger()
          env.MAX_FIX_ATTEMPTS = maxAttempts.toString()

          // Each closure runs one validation check inside the ci-agent
          // container. Order matters: cheapest/fastest checks first. Each
          // one is wrapped in its own stage(name) { } call below (not just
          // a declarative stage section) so it shows up as its own box in
          // the Stage View, same as a normal multi-stage pipeline would -
          // this is a step function, not special plugin config, and it
          // works nested inside a script{} block in declarative pipelines.
          def checks = [
            'build': {
              sh '''
                set -euo pipefail
                podman run --rm -v "$WORKSPACE:/workspace:Z" -w /workspace "$CI_AGENT_IMAGE" \
                  sh -c "npm ci && npm run build --if-present" 2>&1 | tee build.log
              '''
            },
            'unit-test': {
              sh '''
                set -euo pipefail
                podman run --rm -v "$WORKSPACE:/workspace:Z" -w /workspace "$CI_AGENT_IMAGE" \
                  npm test 2>&1 | tee unit-test.log
              '''
            },
            'sonarqube': {
              withSonarQubeEnv('SonarQube') {
                sh '''
                  set -euo pipefail
                  podman run --rm -v "$WORKSPACE:/workspace:Z" -w /workspace --network host \
                    -e SONAR_HOST_URL -e SONAR_AUTH_TOKEN "$CI_AGENT_IMAGE" \
                    sonar-scanner 2>&1 | tee sonarqube.log
                '''
              }
              timeout(time: 10, unit: 'MINUTES') {
                def qg = waitForQualityGate()
                if (qg.status != 'OK') {
                  writeFile file: 'sonarqube.log', text: "\nQuality gate failed: ${qg.status}\n", append: true
                  error("SonarQube quality gate failed: ${qg.status}")
                }
              }
            },
            'trivy': {
              sh '''
                set -euo pipefail
                podman run --rm -v "$WORKSPACE:/workspace:Z" -w /workspace "$CI_AGENT_IMAGE" \
                  trivy fs --exit-code 1 --severity HIGH,CRITICAL . 2>&1 | tee trivy.log
              '''
            }
          ]

          boolean passed = false
          String failedStage = ''

          for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            // Suffix every retry's stage names with the attempt number so
            // each attempt gets its own distinct boxes in Stage View,
            // instead of re-using the same stage name (which classic Stage
            // View does not render cleanly when a name repeats within one
            // build).
            String suffix = (attempt == 1) ? '' : " (attempt ${attempt})"
            failedStage = ''
            try {
              checks.each { name, body ->
                failedStage = name
                stage("${name}${suffix}") {
                  body.call()
                }
              }
              passed = true
              break
            } catch (err) {
              echo "Validation failed at stage '${failedStage}' (attempt ${attempt}/${maxAttempts}): ${err.getMessage()}"
              if (attempt == maxAttempts) {
                break
              }
              env.ATTEMPT = attempt.toString()
              env.FAILED_STAGE = failedStage
              env.FAILURE_LOG_FILE = "${failedStage}.log"
              stage("AI fix (attempt ${attempt}: ${failedStage})") {
                sh '''
                  set -euo pipefail
                  podman run --rm \
                    -v "$WORKSPACE:/workspace:Z" -w /workspace \
                    -e ISSUE_NUMBER -e CLAUDE_CODE_OAUTH_TOKEN -e FAILED_STAGE \
                    -e FAILURE_LOG_FILE -e ATTEMPT -e MAX_FIX_ATTEMPTS \
                    "$CI_AGENT_IMAGE" \
                    ci/ai-pipeline/ai-fix.sh
                '''
                sh '''
                  set -euo pipefail
                  . ci/ai-pipeline/lib/guardrails.sh
                  check_forbidden_paths
                  assert_safe_branch "$BRANCH_NAME"
                  git add -A
                  git commit -m "AI: fix attempt ${ATTEMPT} for issue #${ISSUE_NUMBER} (${FAILED_STAGE} failed)"
                  git push "https://x-access-token:${GITHUB_TOKEN}@github.com/${GIT_REPO_SLUG}.git" "$BRANCH_NAME"
                '''
              }
            }
          }

          env.VALIDATION_PASSED = passed as String
          env.FAILED_STAGE = failedStage
        }
      }
    }

    stage('Create PR') {
      when { environment name: 'VALIDATION_PASSED', value: 'true' }
      steps {
        script {
          env.PR_URL = sh(
            script: '''
              podman run --rm \
                -v "$WORKSPACE:/workspace:Z" -w /workspace \
                -e ISSUE_NUMBER -e ISSUE_TITLE -e BRANCH_NAME -e BASE_BRANCH -e GITHUB_TOKEN \
                "$CI_AGENT_IMAGE" \
                ci/ai-pipeline/create-pr.sh
            ''',
            returnStdout: true
          ).trim()
        }
        sh '''
          set -euo pipefail
          podman run --rm \
            -v "$WORKSPACE:/workspace:Z" -w /workspace \
            -e ISSUE_NUMBER -e GITHUB_TOKEN -e PR_URL \
            -e STATUS=success \
            "$CI_AGENT_IMAGE" \
            ci/ai-pipeline/notify-issue.sh
        '''
      }
    }

    stage('Report failure') {
      when { environment name: 'VALIDATION_PASSED', value: 'false' }
      steps {
        sh '''
          set -euo pipefail
          podman run --rm \
            -v "$WORKSPACE:/workspace:Z" -w /workspace \
            -e ISSUE_NUMBER -e GITHUB_TOKEN -e FAILED_STAGE -e MAX_FIX_ATTEMPTS \
            -e BUILD_URL="$BUILD_URL" -e STATUS=failure \
            "$CI_AGENT_IMAGE" \
            ci/ai-pipeline/notify-issue.sh
        '''
        script { currentBuild.result = 'FAILURE' }
      }
    }
  }

  post {
    always {
      sh 'podman rmi "$CI_AGENT_IMAGE" || true'
    }
  }

  // NO deploy stage below this line, and none should ever be added to this
  // file. Deployment for this project stays a manual, human-triggered action.
}
