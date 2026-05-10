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
| *"Install the CLI plugins so I can use these tools"* | **mcp-setup** |
| *"Write a verification script for MTV-4911"* | **mtv-test** |

## Quick Start

### Claude Code (plugin install)

```bash
# Add the marketplace and install the plugin
claude plugin marketplace add kubev2v/mtv-skills
claude plugin install kubev2v@mtv-skills
```

To update later:

```bash
claude plugin marketplace update kubev2v
claude plugin install kubev2v@mtv-skills
```

Or test locally from a cloned repo:

```bash
claude --plugin-dir ./mtv-skills
```

### Cursor (symlink install)

```bash
git clone https://github.com/kubev2v/mtv-skills.git
cd mtv-skills

mkdir -p ~/.cursor/skills
for skill in skills/*/; do
  ln -sfn "$(pwd)/$skill" ~/.cursor/skills/"$(basename "$skill")"
done
```

For Claude Code per-project installs, Cursor per-project installs, and removal see [docs/install.md](docs/install.md).

## Prerequisites

Several skills use CLI plugins that must be installed on your machine. The **mcp-setup** skill
can guide you through installation, or install manually:

```bash
# kubectl-mtv (https://github.com/yaacov/kubectl-mtv)
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-mtv/main/install.sh | bash

# kubectl-metrics (https://github.com/yaacov/kubectl-metrics)
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-metrics/main/install.sh | bash

# kubectl-debug-queries (https://github.com/yaacov/kubectl-debug-queries)
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-debug-queries/main/install.sh | bash
```

| Plugin | CLI command |
|---|---|
| [kubectl-mtv](https://github.com/yaacov/kubectl-mtv) | `oc mtv` |
| [kubectl-debug-queries](https://github.com/yaacov/kubectl-debug-queries) | `oc debug-queries` |
| [kubectl-metrics](https://github.com/yaacov/kubectl-metrics) | `oc metrics` |

Skills that do not require these plugins (**govc-vsphere**, **kubectl-virt**) use their own CLIs (`govc` and `oc virt`/virtctl). The **mtv-test** skill also uses the [Atlassian Rovo MCP](https://www.atlassian.com/rovo/mcp) for Jira ticket fetching and `gh` for GitHub PR details.

## Included Skills

| Skill | Description | Dependencies |
|-------|-------------|--------------|
| **check-ceph-health** | Check Ceph storage health on OpenShift OCS/ODF clusters | `oc metrics`, `oc debug-queries` |
| **check-ocp-health** | General OpenShift (OCP) cluster health check | `oc debug-queries`, `oc metrics` |
| **govc-vsphere** | Manage VMware vSphere VMs using the govc CLI | `govc` |
| **kubectl-mtv** | Manage MTV/Forklift VM migrations from vSphere, oVirt, OpenStack, OVA, EC2, or HyperV | `oc mtv`, `oc debug-queries` |
| **kubectl-virt** | Create, start, stop, and manage KubeVirt virtual machines | `oc virt` (virtctl) |
| **mcp-setup** | Install and configure CLI plugins (kubectl-mtv, kubectl-metrics, kubectl-debug-queries) | *(none)* |
| **mtv-test** | Generate bash e2e verification scripts for MTV/Forklift bugs and features | `oc mtv`, [Atlassian Rovo MCP](https://www.atlassian.com/rovo/mcp) (Jira), `gh` (GitHub PRs) |
| **observe-metrics** | Observe cluster metrics via Prometheus/Thanos (discovery, instant and range queries, PromQL) | `oc metrics` |
| **troubleshoot-virt** | Troubleshoot stuck VMs, DataVolumes, and migrations | `oc debug-queries`, `oc mtv`, `oc metrics` |

## Docs

| Path | Description |
|------|-------------|
| **[docs/install.md](docs/install.md)** | Full installation and removal instructions (Claude Code & Cursor) |
| **[docs/setup-mtv-agent.md](docs/setup-mtv-agent.md)** | Setting up the [mtv-agent](https://github.com/kubev2v/mtv-agent) AI assistant |
| **[docs/create-providers-cli.md](docs/create-providers-cli.md)** | Creating MTV source providers using `oc mtv` |
| **[examples/mtv-test/create-providers.sh](examples/mtv-test/create-providers.sh)** | Script that creates providers from environment variables |

## License

[Apache-2.0](LICENSE)
