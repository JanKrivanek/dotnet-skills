# Copilot Skills Evaluation

Automated pipeline for measuring whether [msbuild-skills](../msbuild-skills/) improve Copilot's responses to MSBuild-related problems.

## How It Works

Each scenario is run **twice** through Copilot CLI:

| Run | Plugins | Purpose |
|-----|---------|---------|
| **Vanilla** | None | Baseline — what Copilot produces on its own |
| **Skilled** | `msbuild-skills` installed | What Copilot produces with the skills plugin |

Both outputs are then scored by a separate Copilot invocation (acting as an evaluator) against an expected-output rubric, producing per-scenario quality scores (Accuracy, Completeness, Actionability, Clarity — each 1–5) along with token and time metrics.

## Folder Structure

```
evaluation/
├── scenarios/                    # One folder per test scenario
│   └── <scenario-name>/
│       ├── expected-output.md    # Rubric the evaluator scores against
│       └── scenario/             # Test project files (copied to temp dir at runtime)
│           └── <scenario files>
├── scripts/                      # Pipeline scripts (PowerShell 7+)
│   ├── run-scenario.ps1          # Copies scenario to temp dir, runs Copilot CLI
│   ├── evaluate-response.ps1     # Scores vanilla & skilled outputs against expected-output.md
│   ├── parse-copilot-stats.ps1   # Extracts token/time/model stats from Copilot output
│   └── generate-summary.ps1      # Produces the final markdown summary table
├── results/                      # Run outputs (git-ignored in CI, kept locally)
│   └── <run-id>/
│       ├── summary.md
│       └── <scenario-name>/
│           └── <scenario outputs>
└── README.md                     # This file
```

### Adding a New Scenario

1. Create `evaluation/scenarios/<name>/scenario/` with the project files that exhibit the build problem.
2. Create `evaluation/scenarios/<name>/expected-output.md` describing the expected diagnosis, key concepts, and fixes.
3. The pipeline will auto-discover any folder under `scenarios/` that contains a `scenario/` subfolder.

> **Note:** Only the `scenario/` subfolder is copied to a temp directory for each run, keeping the repository checkout clean. The `expected-output.md` stays in place and is read directly during evaluation.

## Pipeline Steps

1. **Discover scenarios** — finds all `evaluation/scenarios/*/scenario/` directories.
2. **Vanilla run** — uninstalls the skills plugin, runs each scenario through Copilot CLI.
3. **Skilled run** — installs `msbuild-skills` plugin, runs each scenario again.
4. **Evaluate** — uninstalls the plugin, then uses Copilot CLI (as a neutral evaluator) to score both outputs against `expected-output.md`.
5. **Generate summary** — aggregates scores and stats into a markdown table.

## Running Locally

### Prerequisites

| Tool | Purpose |
|------|---------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Container runtime for `act` |
| [act](https://github.com/nektos/act) | Runs GitHub Actions workflows locally |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli) (`npm i -g @github/copilot`) | Pre-installed in the Docker image |

### One-Time Setup

1. **Build the Docker image** with pwsh, dotnet, and copilot pre-installed (avoids repeated installs):

   ```powershell
   # Start from the base act image
   docker run --name act-pwsh-build -d catthehacker/ubuntu:act-latest tail -f /dev/null

   # Install pwsh, dotnet SDK, and copilot CLI inside the container
   docker exec act-pwsh-build bash -c '
     apt-get update && apt-get install -y wget apt-transport-https &&
     . /etc/os-release &&
     wget -q "https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb" &&
     dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb &&
     apt-get update && apt-get install -y powershell dotnet-sdk-8.0 &&
     export PATH=/opt/acttoolcache/node/24.13.0/x64/bin:$PATH &&
     npm install -g @github/copilot &&
     ln -sf /opt/acttoolcache/node/24.13.0/x64/bin/copilot /usr/local/bin/copilot
   '

   # Commit the container as a reusable image
   docker commit act-pwsh-build act-pwsh:latest
   docker stop act-pwsh-build && docker rm act-pwsh-build
   ```

2. **Create a `.secrets` file** in the repo root with your GitHub token:

   ```
   COPILOT_GITHUB_TOKEN=ghp_your_token_here
   ```

### Run the Pipeline

From the repository root, in **PowerShell**:

```powershell
$ErrorActionPreference = "Continue"
& act workflow_dispatch `
    --pull=false `
    -P ubuntu-latest=act-pwsh:latest `
    --use-new-action-cache `
    --secret-file .secrets `
    --bind `
    --artifact-server-path "$PWD/.act-artifacts" `
    --env "GITHUB_RUN_ID=local-run" `
    --env "GITHUB_RUN_ATTEMPT=1" `
    2>&1 | Tee-Object -FilePath act-eval.log
```

Results will appear in `evaluation/results/local-run-1/summary.md`.
Uploaded artifacts are stored in `.act-artifacts/` (git-ignored).

> **⚠️ Windows + act caveat:** You must invoke `act` directly from PowerShell with `2>&1 | Tee-Object` (or `2>&1 | Out-Host`). Using `cmd /c act ... > file 2>&1` causes `context canceled` errors that kill long-running Docker exec steps. This is a known issue with act v0.2.x on Windows.

### Understanding the Output

The summary table shows per-scenario comparisons:

| Column | Meaning |
|--------|---------|
| **Quality** | Score delta (e.g. `++ 1` means skilled scored 1 point higher) |
| **Time** | Wall-clock time delta (negative = skilled was faster) |
| **Tokens (in)** | Input token delta (negative = skilled used fewer tokens) |
| **Winner** | Which run produced the better result |

If the `Upload Artifacts` step fails with `Unable to get the ACTIONS_RUNTIME_TOKEN env variable`, ensure you are passing `--artifact-server-path` to act (see the command above). This flag starts a local artifact server; without it, the required runtime variables are not set.
