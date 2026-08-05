---
name: mcp-setup
description: Install and configure the CLI plugins for Forklift/MTV, Prometheus metrics, and Kubernetes debug queries. Use when CLI tools (oc mtv, oc metrics, oc debug-queries) are not available, or when the user wants to set up the tools.
---

# CLI Plugin Setup

This skill helps you install the `oc` plugins required by the other skills in this collection.

## What to Check

First, check if the plugins are already installed:

```bash
oc mtv --help 2>/dev/null && echo "MTV_OK" || echo "MTV_MISSING"
oc metrics --help 2>/dev/null && echo "METRICS_OK" || echo "METRICS_MISSING"
oc debug-queries --help 2>/dev/null && echo "DEBUG_OK" || echo "DEBUG_MISSING"
```

## How to Respond

Based on the results above, tell the user **only** what is missing and provide
the relevant install instructions. If everything is already installed, confirm it and move on.

### Install all tools at once

Use the secure version-pinned installer (downloads binaries, verifies SHA256 checksums):

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh kubectl-mtv kubectl-metrics kubectl-debug-queries && rm install-tools.sh
```

Or install individually:

```bash
bash install-tools.sh kubectl-mtv
bash install-tools.sh kubectl-metrics
bash install-tools.sh kubectl-debug-queries
```

Verify:

```bash
oc mtv --help
oc metrics --help
oc debug-queries --help
```

Versions and SHA256 checksums are pinned in `tools/versions.json`. To update to
a new release, maintainers run `tools/update-versions.sh`.

### PATH setup

All three install to `~/.local/bin` by default. If it is not in the user's PATH:

```bash
# bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

## Tool Summary

| CLI Plugin | Commands | What It Does |
|------------|----------|--------------|
| [kubectl-mtv](https://github.com/yaacov/kubectl-mtv) | `oc mtv` | Manage MTV/Forklift migrations: providers, plans, inventory, health |
| [kubectl-metrics](https://github.com/yaacov/kubectl-metrics) | `oc metrics` | Query Prometheus/Thanos metrics, discover metrics, instant and range queries |
| [kubectl-debug-queries](https://github.com/yaacov/kubectl-debug-queries) | `oc debug-queries` | List/get Kubernetes resources, pod logs, events with TSL filtering |

Note: `kubectl mtv`, `kubectl metrics`, and `kubectl debug-queries` also work as aliases.

## Optional: MCP Server Configuration

If you are using an AI agent that supports MCP (Model Context Protocol), these plugins
can also run as MCP servers. This is optional — the skills work with the CLI directly.

### Claude Code (CLI)

```bash
claude mcp add kubectl-metrics -- oc metrics mcp-server
claude mcp add kubectl-mtv -- oc mtv mcp-server
claude mcp add kubectl-debug-queries -- oc debug-queries mcp-server
```

### Cursor IDE

Settings -> MCP -> Add Server for each:

| Name | Command | Args |
|------|---------|------|
| kubectl-metrics | `oc` | `metrics mcp-server` |
| kubectl-mtv | `oc` | `mtv mcp-server` |
| kubectl-debug-queries | `oc` | `debug-queries mcp-server` |

### Claude Desktop

Edit `claude_desktop_config.json` and add to the `mcpServers` section:

```json
{
  "mcpServers": {
    "kubectl-metrics": {
      "command": "oc",
      "args": ["metrics", "mcp-server"]
    },
    "kubectl-mtv": {
      "command": "oc",
      "args": ["mtv", "mcp-server"]
    },
    "kubectl-debug-queries": {
      "command": "oc",
      "args": ["debug-queries", "mcp-server"]
    }
  }
}
```

### SSE Mode (OpenShift Lightspeed or Remote Agents)

For remote or server-based agents, run each MCP server in SSE mode:

```bash
oc metrics mcp-server --sse --port 8080
oc mtv mcp-server --sse --port 8081
oc debug-queries mcp-server --sse --port 8082
```

### Container Images (no local binary needed)

Run MCP servers as containers instead of installing the plugins locally.
Requires Docker or Podman and a valid cluster token:

```bash
# kubectl-mtv
docker run --rm -p 8080:8080 \
  -e MCP_KUBE_SERVER=https://api.cluster.example.com:6443 \
  -e MCP_KUBE_TOKEN=sha256~xxxx \
  quay.io/yaacov/kubectl-mtv-mcp-server:v0.3.26

# kubectl-metrics
docker run --rm -p 8081:8080 \
  -e MCP_KUBE_SERVER=https://api.cluster.example.com:6443 \
  -e MCP_KUBE_TOKEN=sha256~xxxx \
  quay.io/yaacov/kubectl-metrics-mcp-server:v0.1.13

# kubectl-debug-queries
docker run --rm -p 8082:8080 \
  -e MCP_KUBE_SERVER=https://api.cluster.example.com:6443 \
  -e MCP_KUBE_TOKEN=sha256~xxxx \
  quay.io/yaacov/kubectl-debug-queries-mcp-server:v0.1.5
```

Then configure your agent to connect via SSE at `http://localhost:8080/sse`,
`http://localhost:8081/sse`, and `http://localhost:8082/sse`.

### Deploy on OpenShift

Deploy the MCP servers directly on the cluster (pin to the same versions as
in `tools/versions.json`):

```bash
# kubectl-mtv
oc apply -f https://raw.githubusercontent.com/yaacov/kubectl-mtv/v0.3.26/deploy/mcp-server.yaml

# kubectl-debug-queries
oc apply -f https://raw.githubusercontent.com/yaacov/kubectl-debug-queries/v0.1.5/deploy/mcp-server.yaml
```
