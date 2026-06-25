#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/kubev2v/mtv-skills.git"
INSTALL_DIR="${MTV_SKILLS_DIR:-$HOME/.local/share/mtv-skills}"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || error "git is required but not found in PATH"

if [ -d "$INSTALL_DIR/.git" ]; then
  info "Updating mtv-skills in $INSTALL_DIR ..."
  git -C "$INSTALL_DIR" pull --ff-only || error "git pull failed — resolve manually in $INSTALL_DIR"
  ok "Updated to $(git -C "$INSTALL_DIR" log -1 --format='%h (%ci)')"
elif [ -d "$INSTALL_DIR" ]; then
  error "$INSTALL_DIR exists but is not a git repo — remove it manually and re-run"
else
  info "Installing mtv-skills to $INSTALL_DIR ..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  ok "Cloned mtv-skills to $INSTALL_DIR"
fi

link_skills() {
  local target_dir="$1"
  local label="$2"
  mkdir -p "$target_dir"
  local count=0
  for skill in "$INSTALL_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    ln -sfn "$skill" "$target_dir/$(basename "$skill")"
    count=$((count + 1))
  done
  ok "Linked $count skills → $target_dir ($label)"
}

if [ -d "$HOME/.cursor" ]; then
  link_skills "$HOME/.cursor/skills" "Cursor user-wide"
fi

if [ -d "$HOME/.claude" ]; then
  link_skills "$HOME/.claude/skills" "Claude Code user-wide"
fi

if [ ! -d "$HOME/.cursor" ] && [ ! -d "$HOME/.claude" ]; then
  info "No ~/.cursor or ~/.claude directory found — creating Cursor skills dir"
  link_skills "$HOME/.cursor/skills" "Cursor user-wide"
fi

echo ""
ok "Done! Skills are ready to use."
info "Re-run this command any time to update."
