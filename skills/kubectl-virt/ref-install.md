# oc virt Installation

Installation, PATH setup, and shell completion for `oc virt` (virtctl). `kubectl virt` also works as an alias.

See the main [SKILL.md](SKILL.md) for VM creation workflows and common operations.

---

## Via krew

```bash
kubectl krew install virt
```

Krew handles the `kubectl-virt` binary and shell completion automatically.

## Manual download

Download `virtctl` from the KubeVirt GitHub releases and install it as `kubectl-virt`
so that `oc virt` discovers it as a plugin.

```bash
# Option A: match the version running on your cluster
VERSION=$(oc get kubevirt.kubevirt.io/kubevirt -n kubevirt \
  -o jsonpath="{.status.observedKubeVirtVersion}")

# Option B: use the latest stable release
VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

# Download and install as kubectl-virt
curl -fSL -o virtctl \
  "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${OS}-${ARCH}"
mkdir -p ~/.local/bin
install -m 0755 virtctl ~/.local/bin/kubectl-virt
rm -f virtctl
```

Ensure `~/.local/bin` is in your PATH:

```bash
# bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Verify:

```bash
oc virt --help
```

## Shell Completion (Autocomplete)

If you installed via krew, completion is handled automatically. For manual installs,
create a `kubectl_complete-virt` helper so that `oc virt <TAB>` works.
This follows the same pattern used by kubectl-mtv and kubectl-metrics.

```bash
cat > ~/.local/bin/kubectl_complete-virt << 'SCRIPT'
#!/usr/bin/env bash
kubectl-virt __complete "$@"
SCRIPT
chmod +x ~/.local/bin/kubectl_complete-virt

# Symlink for oc completion on OpenShift
ln -sf ~/.local/bin/kubectl_complete-virt ~/.local/bin/oc_complete-virt
```

After this, tab-completion works for both `oc virt` and `kubectl virt` commands.
