# oc virt Installation

Installation, PATH setup, and shell completion for `oc virt` (virtctl). `kubectl virt` also works as an alias.

See the main [SKILL.md](SKILL.md) for VM creation workflows and common operations.

---

## Via krew

```bash
kubectl krew install virt
```

Krew handles the `kubectl-virt` binary and shell completion automatically.

## Secure version-pinned install (recommended)

Use the project installer which downloads a pinned version and verifies the SHA256 checksum:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh kubectl-virt && rm install-tools.sh
```

The version and checksums are tracked in `tools/versions.json`.

## Manual download

Download `virtctl` from the KubeVirt GitHub releases and install it as `kubectl-virt`
so that `oc virt` discovers it as a plugin. Pin to a known version and verify:

```bash
VERSION="v1.9.0"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

curl -fSL -o virtctl \
  "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${OS}-${ARCH}"

# Verify SHA256 — compare against tools/versions.json
shasum -a 256 virtctl

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

If you used the secure installer or krew, completion is set up automatically.
For manual installs, create a `kubectl_complete-virt` helper so that
`oc virt <TAB>` works:

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
