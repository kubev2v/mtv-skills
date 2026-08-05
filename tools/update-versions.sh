#!/usr/bin/env bash
#
# Maintainer script: update tools/versions.json with new release versions
# and SHA256 hashes fetched from GitHub.
#
# Usage:
#   ./tools/update-versions.sh kubectl-mtv v0.4.0      # bump one tool
#   ./tools/update-versions.sh --all --latest           # bump all tools to latest
#   ./tools/update-versions.sh --all                    # re-hash current versions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${SCRIPT_DIR}/versions.json"
SHA256SUMS="${REPO_ROOT}/SHA256SUMS"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl    >/dev/null 2>&1 || error "curl is required"
command -v python3 >/dev/null 2>&1 || error "python3 is required"
[ -f "$MANIFEST" ]                 || error "Manifest not found: $MANIFEST"

# --- sha256 helper ------------------------------------------------------------
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# --- fetch latest release tag -------------------------------------------------
latest_tag() {
  local repo="$1"
  local response
  response="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")" \
    || error "Failed to fetch latest release for ${repo}"
  python3 -c "
import json, sys
data = json.loads(sys.argv[1])
tag = data.get('tag_name')
if not tag:
    raise SystemExit('No tag_name in GitHub API response')
print(tag)
" "$response" || error "Failed to parse latest release tag for ${repo}"
}

# --- resolve the asset URL for a given tool/platform/version ------------------
resolve_asset_url() {
  local tool="$1" platform="$2" version="$3"
  python3 -c "
import json, sys

tool, platform, version = '$tool', '$platform', '$version'

with open('$MANIFEST') as f:
    data = json.load(f)

entry = data[tool]
old_url = entry['assets'][platform]['url']
old_version = entry['version']

# Replace old version with new version in the URL
new_url = old_url.replace(old_version, version)
print(new_url)
"
}

# --- update one tool ----------------------------------------------------------
update_tool() {
  local tool="$1" new_version="$2"

  local repo
  repo="$(python3 -c "
import json
with open('$MANIFEST') as f:
    print(json.load(f)['$tool']['repo'])
")"

  local old_version
  old_version="$(python3 -c "
import json
with open('$MANIFEST') as f:
    print(json.load(f)['$tool']['version'])
")"

  if [ "$new_version" = "--latest" ]; then
    new_version="$(latest_tag "$repo")"
  fi

  info "$tool: $old_version -> $new_version (repo: $repo)"

  local tmpdir
  tmpdir="$(mktemp -d)"

  local platforms
  platforms="$(python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
for p in data['$tool']['assets']:
    print(p)
")"

  local all_hashes=""
  while IFS= read -r platform; do
    [ -n "$platform" ] || continue
    local url
    url="$(resolve_asset_url "$tool" "$platform" "$new_version")"
    local outfile="${tmpdir}/${tool}-${platform}"

    info "  Downloading $platform ..."
    if ! curl -fsSL -o "$outfile" "$url"; then
      warn "  Failed to download: $url"
      rm -rf "$tmpdir"
      return 1
    fi

    local hash
    hash="$(sha256_of "$outfile")"
    all_hashes="${all_hashes}${platform}|${url}|${hash}\n"
    ok "  $platform: ${hash:0:16}..."
  done <<< "$platforms"

  rm -rf "$tmpdir"

  # Apply updates to the manifest (atomic write)
  python3 -c "
import json, os, tempfile

manifest = '$MANIFEST'
with open(manifest) as f:
    data = json.load(f)

data['$tool']['version'] = '$new_version'

hashes_raw = '''$(printf '%b' "$all_hashes")'''.strip()
for line in hashes_raw.split('\n'):
    if not line.strip():
        continue
    platform, url, sha = line.split('|')
    data['$tool']['assets'][platform]['url'] = url
    data['$tool']['assets'][platform]['sha256'] = sha

manifest_dir = os.path.dirname(manifest) or '.'
fd, tmp_path = tempfile.mkstemp(dir=manifest_dir, prefix='.versions.', suffix='.json')
with os.fdopen(fd, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.replace(tmp_path, manifest)
"

  ok "$tool updated to $new_version"
}

# --- refresh SHA256SUMS for installer artifacts --------------------------------
update_sha256sums() {
  local files=(install.sh tools/install-tools.sh tools/versions.json)
  local f path

  info "Updating SHA256SUMS ..."
  tmp_sums="$(mktemp)"
  for f in "${files[@]}"; do
    path="${REPO_ROOT}/${f}"
    [ -f "$path" ] || error "Missing file for SHA256SUMS: $path"
    printf '%s  %s\n' "$(sha256_of "$path")" "$f" >> "$tmp_sums"
  done
  mv "$tmp_sums" "$SHA256SUMS"
  ok "SHA256SUMS updated: $SHA256SUMS"
}

# --- main ---------------------------------------------------------------------
if [ $# -eq 0 ]; then
  echo "Usage:"
  echo "  $0 <tool> <version>        # update one tool"
  echo "  $0 --all --latest          # update all tools to latest release"
  echo "  $0 --all                   # re-hash current versions"
  echo ""
  echo "Available tools:"
  python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
for name, info in sorted(data.items()):
    print(f'  {name:30s} {info[\"version\"]:12s} ({info[\"repo\"]})')
"
  exit 0
fi

if [ "$1" = "--all" ]; then
  version_flag="${2:---same}"
  tools="$(python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
for k in sorted(data.keys()):
    print(k)
")"
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    if [ "$version_flag" = "--latest" ]; then
      update_tool "$tool" "--latest"
    else
      current="$(python3 -c "
import json
with open('$MANIFEST') as f:
    print(json.load(f)['$tool']['version'])
")"
      update_tool "$tool" "$current"
    fi
    echo ""
  done <<< "$tools"
else
  tool="$1"
  version="${2:---latest}"
  update_tool "$tool" "$version"
fi

echo ""
update_sha256sums
echo ""
ok "Manifest updated: $MANIFEST"
info "Review the changes with: git diff tools/versions.json SHA256SUMS"
