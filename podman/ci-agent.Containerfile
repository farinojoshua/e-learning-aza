# CI agent image: everything the Jenkinsfile needs to run inside a container
# via `podman run`, per-stage. Built once per build with `podman build`.
#
# Pin every version here deliberately - do not float on ":latest". Bump the
# ARGs on a schedule, review the changelog, rebuild, re-test.
FROM node:20-bookworm-slim

ARG TRIVY_VERSION=0.55.2
ARG SONAR_SCANNER_VERSION=6.1.0.4477

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates unzip jq openjdk-17-jre-headless gnupg \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (gh) - used only by create-pr.sh / notify-issue.sh, never by Claude.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Trivy, pinned to the tag matching TRIVY_VERSION (not a mutable branch ref).
RUN curl -fsSL "https://raw.githubusercontent.com/aquasecurity/trivy/v${TRIVY_VERSION}/contrib/install.sh" \
      | sh -s -- -b /usr/local/bin "v${TRIVY_VERSION}"

# SonarQube Scanner CLI.
RUN curl -fsSL -o /tmp/sonar-scanner.zip \
      "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
    && unzip -q /tmp/sonar-scanner.zip -d /opt \
    && mv "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64" /opt/sonar-scanner \
    && rm /tmp/sonar-scanner.zip
ENV PATH="/opt/sonar-scanner/bin:${PATH}"

# Claude Code CLI - verify this is still the correct package name/version
# pin for the CLI release you intend to run before relying on this in prod.
RUN npm install -g @anthropic-ai/claude-code

WORKDIR /workspace
