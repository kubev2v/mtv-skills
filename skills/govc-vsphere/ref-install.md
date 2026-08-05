# govc Installation

Installation methods, PATH setup, and verification for `govc`.

See the main [SKILL.md](SKILL.md) for connection setup, VM workflows, and common operations.

---

## Via Homebrew (macOS / Linux)

```bash
brew install govc
```

## Secure version-pinned install (recommended)

Use the project installer which downloads a pinned version and verifies the SHA256 checksum:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh govc && rm install-tools.sh
```

The version and checksums are tracked in `tools/versions.json`.

## Manual binary download

Download from the [govmomi releases](https://github.com/vmware/govmomi/releases) page.
Pin to a known version and verify the checksum:

```bash
VERSION="v0.55.1"

OS=$(uname -s)   # Darwin or Linux
ARCH=$(uname -m) # x86_64 or arm64

curl -fSL -o govc.tar.gz \
  "https://github.com/vmware/govmomi/releases/download/${VERSION}/govc_${OS}_${ARCH}.tar.gz"

# Verify SHA256 — compare against tools/versions.json
shasum -a 256 govc.tar.gz

tar xzf govc.tar.gz govc
mkdir -p ~/.local/bin
install -m 0755 govc ~/.local/bin/govc
rm -f govc govc.tar.gz
```

Ensure `~/.local/bin` is in your PATH:

```bash
# bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

## Via Go install

If you have Go installed:

```bash
go install github.com/vmware/govmomi/govc@latest
```

The binary is placed in `$GOPATH/bin` (or `~/go/bin` by default).

## Verify

```bash
govc version
```
