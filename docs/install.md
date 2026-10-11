# Installation

## Prerequisites

- An agent that loads skills from `~/.agents/skills`

## Install

Download the installer, verify its checksum, and run it:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/install.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install.sh
rm install.sh
```

The script clones the repo to `~/.local/share/mtv-skills` (or pulls if already
present), then opens a menu of skills to link into `~/.agents/skills`.

- A new install marks every skill for install.
- A skill that is already linked is marked for update.
- Unmark a linked skill to remove that link. Only symlinks that point at this
  checkout are removed; other files in `~/.agents/skills` are left in place.
- Move with `j`/`k` or the arrow keys, space to mark or unmark, and `a` to
  toggle all. Enter applies the selection. `q` leaves existing links unchanged.

Run the same command again any time to update. The menu is shown on every run.

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

### Skill symlinks

The installer menu removes a user-wide skill when you unmark it and press Enter.
To remove the links without a menu:

**User-wide:**

```bash
for skill in check-ceph-health check-ocp-health debug-ceph govc-vsphere kubectl-mtv kubectl-virt mcp-setup mtv-test observe-metrics troubleshoot-virt; do
  rm -f ~/.agents/skills/"$skill"
done
```

**Per-project:**

```bash
# From inside the target project directory
for skill in check-ceph-health check-ocp-health debug-ceph govc-vsphere kubectl-mtv kubectl-virt mcp-setup mtv-test observe-metrics troubleshoot-virt; do
  rm -f .agents/skills/"$skill"
done
```

### Cloned Repository

```bash
rm -rf ~/.local/share/mtv-skills
```
