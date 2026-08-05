# mtv-skills

AI agent skills for MTV/Forklift migrations on OpenShift and Kubernetes. Works with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Cursor](https://www.cursor.com/).

## What Can I Do with These Skills?

Just open a chat and ask. Here's one high-impact example per skill:

| Ask the agent to… | Skill used |
|--------------------|------------|
| *"Migrate my 20 VMs from vSphere to OpenShift"* | **kubectl-mtv** |
| *"Check why my cluster nodes are NotReady"* | **check-ocp-health** |
| *"My VM won't start — figure out what's wrong"* | **troubleshoot-virt** |
| *"Show me network traffic by namespace for the last hour"* | **observe-metrics** |
| *"Plot the forklift namespace RX/TX for the last 24h in a chart"* | **observe-metrics** |
| *"Create a Fedora VM with 4 GiB RAM and start it"* | **kubectl-virt** |
| *"Is Ceph healthy? Any OSDs near full?"* | **check-ceph-health** |
| *"Ceph is full — run ceph commands and reclaim stuck PVs"* | **debug-ceph** |
| *"Install the CLI plugins so I can use these tools"* | **mcp-setup** |
| *"Write a verification script for MTV-4911"* | **mtv-test** |

## Quick Start

### Cursor / Claude Code

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/install.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install.sh && rm install.sh
```

### Claude Code (plugin install)

```bash
claude plugin marketplace add kubev2v/mtv-skills
claude plugin install mtv-skills@kubev2v
```

To update later:

```bash
claude plugin update mtv-skills@kubev2v
```

For removal and other options see [docs/install.md](docs/install.md).

## Prerequisites

Several skills use CLI plugins that must be installed on your machine. The **mcp-setup** skill
can guide you through installation, or install manually using the version-pinned, hash-verified
installer:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh && rm install-tools.sh
```

| Plugin | CLI command |
|---|---|
| [kubectl-mtv](https://github.com/yaacov/kubectl-mtv) | `oc mtv` |
| [kubectl-debug-queries](https://github.com/yaacov/kubectl-debug-queries) | `oc debug-queries` |
| [kubectl-metrics](https://github.com/yaacov/kubectl-metrics) | `oc metrics` |

Skills that do not require these plugins (**govc-vsphere**, **kubectl-virt**) use their own CLIs (`govc` and `oc virt`/virtctl). The **mtv-test** skill also uses the [Atlassian Rovo MCP](https://support.atlassian.com/rovo/docs/getting-started-with-the-atlassian-remote-mcp-server/) for Jira ticket fetching and `gh` for GitHub PR details.

## Included Skills

See [docs/skills.md](docs/skills.md) for a full list of skills with descriptions, triggers, and dependencies.

## Docs

| Path | Description |
|------|-------------|
| **[docs/skills.md](docs/skills.md)** | Quick reference for every skill (what / when / trigger) |
| **[docs/install.md](docs/install.md)** | Full installation and removal instructions (Claude Code & Cursor) |
| **[docs/setup-mtv-agent.md](docs/setup-mtv-agent.md)** | Setting up the [mtv-agent](https://github.com/kubev2v/mtv-agent) AI assistant |
| **[docs/create-providers-cli.md](docs/create-providers-cli.md)** | Creating MTV source providers using `oc mtv` |
| **[examples/mtv-test/create-providers.sh](examples/mtv-test/create-providers.sh)** | Script that creates providers from environment variables |

## License

[Apache-2.0](LICENSE)
