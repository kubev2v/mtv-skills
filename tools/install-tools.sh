#!/usr/bin/env bash
#
# Secure installer for MTV/Forklift CLI tools.
# Downloads version-pinned binaries, verifies SHA256 checksums,
# installs to ~/.local/bin, and creates shell completion helpers.
#
# Usage:
#   ./tools/install-tools.sh                       # install all tools
#   ./tools/install-tools.sh kubectl-mtv govc       # install specific tools
#   INSTALL_DIR=~/bin ./tools/install-tools.sh       # custom install directory
#
# Remote usage (no clone required — verify before running):
#   curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
#   curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
#   bash install-tools.sh kubectl-mtv kubectl-metrics && rm install-tools.sh

set -euo pipefail

MANIFEST_URL="https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/versions.json"
SHA256SUMS_URL="https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# --- dependency checks -------------------------------------------------------
command -v curl  >/dev/null 2>&1 || error "curl is required but not found in PATH"

# --- locate or fetch the version manifest ------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
MANIFEST="${SCRIPT_DIR:+${SCRIPT_DIR}/versions.json}"

_cleanup_manifest=""
if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  MANIFEST="$(mktemp)"
  _cleanup_manifest="$MANIFEST"
  info "Fetching version manifest from GitHub ..."
  curl -fsSL -o "$MANIFEST" "$MANIFEST_URL" || error "Failed to download version manifest from $MANIFEST_URL"

  # Verify manifest integrity against SHA256SUMS before trusting its contents
  _sha256sums="$(mktemp)"
  curl -fsSL -o "$_sha256sums" "$SHA256SUMS_URL" || error "Failed to download SHA256SUMS from $SHA256SUMS_URL"
  _expected_hash=$(grep -F 'tools/versions.json' "$_sha256sums" | awk '{print $1}')
  rm -f "$_sha256sums"
  [ -n "$_expected_hash" ] || error "tools/versions.json not found in SHA256SUMS — cannot verify manifest integrity"

  if command -v sha256sum >/dev/null 2>&1; then
    _actual_hash=$(sha256sum "$MANIFEST" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    _actual_hash=$(shasum -a 256 "$MANIFEST" | awk '{print $1}')
  else
    error "No sha256sum or shasum found — cannot verify manifest integrity"
  fi

  if [ "$_actual_hash" != "$_expected_hash" ]; then
    rm -f "$MANIFEST"
    error "SHA256 mismatch for versions.json!
  Expected: $_expected_hash
  Got:      $_actual_hash
  The manifest may have been tampered with. Aborting."
  fi
  ok "Version manifest verified (SHA256: ${_actual_hash:0:16}...)"
fi
trap '[ -n "$_cleanup_manifest" ] && rm -f "$_cleanup_manifest"' EXIT

[ -f "$MANIFEST" ] || error "Version manifest not found: $MANIFEST"

if command -v jq >/dev/null 2>&1; then
  json_get() { jq -r "$1" "$MANIFEST"; }
else
  if command -v python3 >/dev/null 2>&1; then
    json_get() {
      python3 -c "
import json, sys
with open('$MANIFEST') as f:
    data = json.load(f)
expr = '''$1'''
exec('import functools; result = functools.reduce(lambda d,k: d[k], ' + repr(expr.strip('.').split('.')) + ', data)')
print(result if result is not None else '')
" 2>/dev/null
    }
  else
    error "Either jq or python3 is required to parse the version manifest"
  fi
fi

# --- platform detection -------------------------------------------------------
detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    arm64)   arch="arm64" ;;
    *)       error "Unsupported architecture: $arch" ;;
  esac
  case "$os" in
    darwin|linux) ;;
    *)            error "Unsupported OS: $os" ;;
  esac
  PLATFORM="${os}-${arch}"
}

# --- sha256 helper ------------------------------------------------------------
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    error "No sha256sum or shasum found — cannot verify downloads"
  fi
}

# --- JSON helpers using jq or python3 -----------------------------------------
tool_field() {
  local tool="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r "
      .\"${tool}\".${field} // empty
      | if type == \"array\" then .[] else . end
    " "$MANIFEST"
  else
    python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
val = data.get('$tool', {})
for k in '$field'.split('.'):
  if isinstance(val, dict):
    val = val.get(k)
  else:
    val = None
    break
if val is not None:
  if isinstance(val, list):
    print('\n'.join(str(v) for v in val))
  else:
    print(val)
"
  fi
}

tool_asset_field() {
  local tool="$1" platform="$2" field="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".\"${tool}\".assets.\"${platform}\".${field} // empty" "$MANIFEST"
  else
    python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
val = data.get('$tool', {}).get('assets', {}).get('$platform', {}).get('$field')
if val is not None:
  print(val)
"
  fi
}

list_tools() {
  if command -v jq >/dev/null 2>&1; then
    jq -r 'keys[]' "$MANIFEST"
  else
    python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
for k in sorted(data.keys()):
    print(k)
"
  fi
}

# --- install a single tool ----------------------------------------------------
install_tool() {
  local tool="$1"
  local version binary_name archive_format url expected_hash

  version="$(tool_field "$tool" version)"
  binary_name="$(tool_field "$tool" binary_name)"
  archive_format="$(tool_field "$tool" archive_format)"
  url="$(tool_asset_field "$tool" "$PLATFORM" url)"
  expected_hash="$(tool_asset_field "$tool" "$PLATFORM" sha256)"

  [ -n "$version" ]       || { warn "Tool '$tool' not found in manifest — skipping"; return 1; }
  [ -n "$url" ]           || { warn "No asset for $tool on $PLATFORM — skipping"; return 1; }
  [ -n "$expected_hash" ] || { warn "No SHA256 hash for $tool on $PLATFORM — skipping"; return 1; }

  info "Installing $tool $version for $PLATFORM ..."

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap "rm -rf '$tmpdir'" RETURN

  local download_file="${tmpdir}/download"
  curl -fSL -o "$download_file" "$url" || error "Download failed: $url"

  local actual_hash
  actual_hash="$(sha256_of "$download_file")"
  if [ "$actual_hash" != "$expected_hash" ]; then
    error "SHA256 mismatch for $tool!
  Expected: $expected_hash
  Got:      $actual_hash
  The download may be corrupted or tampered with. Aborting."
  fi

  ok "SHA256 verified: ${actual_hash:0:16}..."

  mkdir -p "$INSTALL_DIR"
  local installed_binary="${INSTALL_DIR}/${binary_name}"

  case "$archive_format" in
    tar.gz)
      tar xzf "$download_file" -C "$tmpdir"
      # Find the binary — may have a platform suffix or be a plain name
      local extracted
      extracted="$(find "$tmpdir" -maxdepth 1 -type f -name "${binary_name}*" \
                    ! -name "*.tar.gz" ! -name "*.sha256*" ! -name "download" \
                    ! -name "LICENSE*" ! -name "README*" ! -name "CHANGELOG*" \
                    | head -1)"
      [ -n "$extracted" ] || error "Could not find $binary_name binary in archive"
      install -m 0755 "$extracted" "$installed_binary"
      ;;
    binary)
      install -m 0755 "$download_file" "$installed_binary"
      ;;
    *)
      error "Unknown archive_format '$archive_format' for $tool"
      ;;
  esac

  ok "Installed $installed_binary"

  # --- completion script ------------------------------------------------------
  local completion_cmd
  completion_cmd="$(tool_field "$tool" completion_cmd)"
  if [ -n "$completion_cmd" ]; then
    local comp_parts
    IFS=$'\n' read -r -d '' -a comp_parts <<< "$completion_cmd" || true

    if [ "${#comp_parts[@]}" -ge 2 ]; then
      local comp_binary="${comp_parts[0]}"
      local comp_arg="${comp_parts[1]}"

      # kubectl_complete-<subcommand> helper
      local plugin_suffix="${binary_name#kubectl-}"
      local comp_script="${INSTALL_DIR}/kubectl_complete-${plugin_suffix}"

      cat > "$comp_script" << COMPSCRIPT
#!/usr/bin/env bash
${comp_binary} ${comp_arg} "\$@"
COMPSCRIPT
      chmod +x "$comp_script"
      ok "Created completion helper: $comp_script"

      # oc / alias completion symlinks
      local aliases
      aliases="$(tool_field "$tool" completion_aliases)"
      if [ -n "$aliases" ]; then
        while IFS= read -r alias_name; do
          [ -n "$alias_name" ] || continue
          ln -sf "$comp_script" "${INSTALL_DIR}/${alias_name}"
          ok "Linked completion alias: ${INSTALL_DIR}/${alias_name}"
        done <<< "$aliases"
      fi
    fi
  fi
}

# --- main ---------------------------------------------------------------------
detect_platform

if [ $# -gt 0 ]; then
  tools_to_install=("$@")
else
  tools_to_install=()
  while IFS= read -r _tool; do
    [ -n "$_tool" ] || continue
    tools_to_install+=("$_tool")
  done < <(list_tools)
fi

failed=0
for tool in "${tools_to_install[@]}"; do
  echo ""
  if ! install_tool "$tool"; then
    failed=$((failed + 1))
  fi
done

echo ""

# PATH check
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    warn "$INSTALL_DIR is not in your PATH. Add it with:"
    info '  # bash'
    info "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
    info '  # zsh'
    info "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    echo ""
    ;;
esac

if [ "$failed" -gt 0 ]; then
  warn "$failed tool(s) failed to install."
  exit 1
fi

ok "All tools installed successfully to $INSTALL_DIR"
