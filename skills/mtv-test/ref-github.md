# Fetching GitHub PR Details

Use the `gh` CLI via the Shell tool to fetch PR information from GitHub.

## How to fetch

### 1. Get PR metadata

Run `gh pr view` to get the title, body, changed files, and reviews:

```bash
gh pr view <number> --repo kubev2v/forklift --json title,body,files,reviews,labels
```

If the PR is in a different repo (e.g. `kubev2v/forklift-console-plugin`), adjust `--repo`
accordingly.

### 2. Get the diff (optional, for understanding code changes)

```bash
gh pr diff <number> --repo kubev2v/forklift
```

Use this when you need to understand what exactly changed in the code to write accurate
test assertions.

## What to extract

- **PR title and description** — especially any "How to test" or "Testing" sections
- **Files changed** — which components were modified (controller, provider adapter, plan, UI, etc.)
- **Unit tests added** — what scenarios the unit tests cover (these reveal the edge cases)
- **Any "before/after" behavior** described in the PR body

## Questions the PR should answer

- What exact behavior changed? (informs the core test assertion)
- What are the edge cases or boundary conditions? (informs additional test scenarios)
- Are there "how to reproduce" steps in the PR? (informs the test steps)
- Which provider type(s) are involved?

## Setup — Installing the GitHub CLI

If `gh` is not installed, ask the user to install it:

- **macOS**: `brew install gh`
- **Fedora/RHEL**: `sudo dnf install gh`
- **Other**: See https://cli.github.com/ for all platforms

After installation, authenticate:

```bash
gh auth login
```

Follow the interactive prompts to authenticate with GitHub (browser-based OAuth or token).

## Fallback

If `gh` cannot be installed or authentication fails, ask the user to paste the PR
description and relevant code diffs directly into the chat.
