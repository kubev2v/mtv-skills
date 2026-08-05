# Installation

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or [Cursor](https://www.cursor.com/) installed and configured

## Cursor / Claude Code

Download the installer, verify its checksum, and run it:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/install.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install.sh
rm install.sh
```

The script clones the repo to `~/.local/share/mtv-skills` (or pulls if already
present) and creates user-wide symlinks in `~/.cursor/skills` and/or
`~/.claude/skills` depending on which directories exist.

Run the same command again any time to update.

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
inspecting cluster resources. The secure installer downloads version-pinned
binaries, verifies SHA256 checksums, installs to `~/.local/bin`, and creates
shell completion helpers.

Download the CLI installer, verify its checksum, then run:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh            # all tools
rm install-tools.sh
```

To install specific tools only:

```bash
bash install-tools.sh kubectl-mtv kubectl-metrics
```

The script automatically fetches the version manifest
([tools/versions.json](../tools/versions.json)) from GitHub.

If `~/.local/bin` is not in your PATH the installer will print the command to add it.

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
