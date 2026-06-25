# Installation

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or [Cursor](https://www.cursor.com/) installed and configured

## Cursor / Claude Code

```bash
curl -sSL https://raw.githubusercontent.com/kubev2v/mtv-skills/main/install.sh | bash
```

The script clones the repo to `~/.local/share/mtv-skills` (or pulls if already
present) and creates user-wide symlinks in `~/.cursor/skills` and/or
`~/.claude/skills` depending on which directories exist.

Run the same command again any time to update.

To override the clone location:

```bash
MTV_SKILLS_DIR=~/my-custom-path curl -sSL https://raw.githubusercontent.com/kubev2v/mtv-skills/main/install.sh | bash
```

**Per-project** (available only in a specific project):

```bash
MTV_SKILLS_DIR="${MTV_SKILLS_DIR:-$HOME/.local/share/mtv-skills}"

# From inside the target project directory — Cursor
mkdir -p .cursor/skills
for skill in "$MTV_SKILLS_DIR"/skills/*/; do
  ln -sfn "$skill" .cursor/skills/"$(basename "$skill")"
done

# From inside the target project directory — Claude Code
mkdir -p .claude/skills
for skill in "$MTV_SKILLS_DIR"/skills/*/; do
  ln -sfn "$skill" .claude/skills/"$(basename "$skill")"
done
```

## Claude Code Plugin (alternative)

Install as a Claude Code plugin — no cloning or symlinks needed:

```bash
claude plugin marketplace add kubev2v/mtv-skills
claude plugin install mtv-skills@kubev2v
```

Skills appear as `/mtv-skills:<skill-name>` in Claude Code.

Every pushed commit is automatically a new version (no pinned SHA or version).
To update later:

```bash
claude plugin marketplace update kubev2v
claude plugin install mtv-skills@kubev2v
```

To uninstall:

```bash
claude plugin uninstall mtv-skills@kubev2v
```

## CLI Plugin Prerequisites

Several skills use `oc` plugins for querying metrics, managing migrations, and
inspecting cluster resources. Install them with the one-line installer (Linux / macOS):

```bash
# kubectl-mtv (https://github.com/yaacov/kubectl-mtv)
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-mtv/main/install.sh | bash

# kubectl-metrics (https://github.com/yaacov/kubectl-metrics)
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-metrics/main/install.sh | bash

# kubectl-debug-queries (https://github.com/yaacov/kubectl-debug-queries)
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-debug-queries/main/install.sh | bash
```

All installers place binaries in `~/.local/bin` by default. If that directory
is not in your PATH:

```bash
# bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Verify the installation:

```bash
oc mtv --help
oc metrics --help
oc debug-queries --help
```

The **mcp-setup** skill can guide you through installation interactively. Just ask
your agent: *"Install the CLI plugins so I can use these tools."*

## Removal

### Claude Code Plugin

```bash
claude plugin uninstall mtv-skills@kubev2v
```

### Claude Code Symlinks

**User-wide:**

```bash
for skill in check-ceph-health check-ocp-health govc-vsphere kubectl-mtv kubectl-virt mcp-setup mtv-test observe-metrics troubleshoot-virt; do
  rm -f ~/.claude/skills/"$skill"
done
```

**Per-project:**

```bash
# From inside the target project directory
for skill in check-ceph-health check-ocp-health govc-vsphere kubectl-mtv kubectl-virt mcp-setup mtv-test observe-metrics troubleshoot-virt; do
  rm -f .claude/skills/"$skill"
done
```

### Cursor

**User-wide:**

```bash
for skill in check-ceph-health check-ocp-health govc-vsphere kubectl-mtv kubectl-virt mcp-setup mtv-test observe-metrics troubleshoot-virt; do
  rm -f ~/.cursor/skills/"$skill"
done
```

**Per-project:**

```bash
# From inside the target project directory
for skill in check-ceph-health check-ocp-health govc-vsphere kubectl-mtv kubectl-virt mcp-setup mtv-test observe-metrics troubleshoot-virt; do
  rm -f .cursor/skills/"$skill"
done
```

### Cloned Repository

```bash
rm -rf ~/.local/share/mtv-skills
```
