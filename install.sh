#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/kubev2v/mtv-skills.git"
INSTALL_DIR="${MTV_SKILLS_DIR:-$HOME/.local/share/mtv-skills}"
SKILLS_TARGET="$HOME/.agents/skills"

skill_names=()
skill_descs=()
skill_installed=()
skill_selected=()
any_installed=0
NAME_WIDTH=0
cursor=0
menu_start=0
menu_active=0
SAVED_STTY=""
KEY=""

# 38;2 is an RGB font color. The 16-color codes (31–36) follow the terminal
# theme, which can map blue, green, yellow, and red all to gray.
info()  { printf '\033[38;2;70;140;255m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[38;2;40;180;90m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[38;2;210;140;0m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[38;2;220;60;60m[error]\033[0m %s\n' "$*" >&2; exit 1; }
code()  { printf '        \033[38;2;0;170;180m%s\033[0m\n' "$*"; }

cleanup_tty() {
  trap - INT
  if [ "$menu_active" -eq 1 ]; then
    menu_active=0
    if [ -n "$SAVED_STTY" ]; then
      stty "$SAVED_STTY" || true
      SAVED_STTY=""
    fi
    tput cnorm 2>/dev/null || printf '\033[?25h'
  fi
}
trap cleanup_tty EXIT

cancel_menu() {
  local code="$1"
  cleanup_tty
  printf '\033[H\033[2J'
  info "Aborted. No skills were changed."
  exit "$code"
}

canonical_script() {
  local src="$1"
  local dir base
  base=$(basename "$src")
  dir=$(cd "$(dirname "$src")" && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "$base"
}

# One-line summary from SKILL.md frontmatter, including folded description blocks.
skill_summary() {
  local file="$1"
  local line rest desc="" folding=0 in_front=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_front" -eq 0 ]; then
      [ "$line" = "---" ] && in_front=1
      continue
    fi
    if [ "$line" = "---" ]; then
      break
    fi
    if [ "$folding" -eq 1 ]; then
      case "$line" in
        [[:space:]]*)
          line="${line#"${line%%[![:space:]]*}"}"
          if [ -z "$desc" ]; then
            desc=$line
          else
            desc="$desc $line"
          fi
          ;;
        *)
          break
          ;;
      esac
      continue
    fi
    case "$line" in
      description:*)
        rest="${line#description:}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        case "$rest" in
          ">"|">-"|">+"|"|"|"|-"|"|+")
            folding=1
            ;;
          *)
            desc=$rest
            case "$desc" in
              \"*\") desc="${desc#\"}"; desc="${desc%\"}" ;;
              \'*\') desc="${desc#\'}"; desc="${desc%\'}" ;;
            esac
            break
            ;;
        esac
        ;;
    esac
  done < "$file"
  printf '%s\n' "$desc"
}

load_skills() {
  local dir name desc installed
  skill_names=()
  skill_descs=()
  skill_installed=()
  skill_selected=()
  any_installed=0
  NAME_WIDTH=0
  for dir in "$INSTALL_DIR"/skills/*/; do
    [ -d "$dir" ] || continue
    [ -f "${dir}SKILL.md" ] || continue
    name=$(basename "$dir")
    desc=$(skill_summary "${dir}SKILL.md")
    if [ -L "$SKILLS_TARGET/$name" ]; then
      installed=1
      any_installed=1
    else
      installed=0
    fi
    skill_names+=("$name")
    skill_descs+=("$desc")
    skill_installed+=("$installed")
    skill_selected+=("$installed")
    if [ "${#name}" -gt "$NAME_WIDTH" ]; then
      NAME_WIDTH=${#name}
    fi
  done
  if [ "$any_installed" -eq 0 ] && [ "${#skill_names[@]}" -gt 0 ]; then
    local i
    for i in "${!skill_names[@]}"; do
      skill_selected[$i]=1
    done
  fi
}

link_points_at_skill() {
  local dest="$1"
  local name="$2"
  local target resolved expected
  [ -L "$dest" ] || return 1
  target=$(readlink "$dest") || return 1
  case "$target" in
    "$INSTALL_DIR/skills/$name"|"$INSTALL_DIR/skills/$name/")
      return 0
      ;;
  esac
  if [ "${target#/}" = "$target" ]; then
    target="$(dirname "$dest")/$target"
  fi
  [ -d "$target" ] || return 1
  resolved=$(cd "$target" && pwd -P) || return 1
  expected=$(cd "$INSTALL_DIR/skills/$name" && pwd -P) || return 1
  [ "$resolved" = "$expected" ]
}

apply_selection() {
  local i name dest src
  mkdir -p "$SKILLS_TARGET"
  for i in "${!skill_names[@]}"; do
    name="${skill_names[$i]}"
    dest="$SKILLS_TARGET/$name"
    src="$INSTALL_DIR/skills/$name"
    if [ "${skill_selected[$i]}" -eq 1 ]; then
      if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        warn "left $dest in place (refusing to replace a non-symlink)"
        continue
      fi
      ln -sfn "$src" "$dest"
      if [ "${skill_installed[$i]}" -eq 1 ]; then
        printf '  \033[38;2;0;170;180m%-9s\033[0m  %s\n' "updated" "$name"
      else
        printf '  \033[38;2;40;180;90m%-9s\033[0m  %s\n' "installed" "$name"
      fi
    elif [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
      continue
    elif link_points_at_skill "$dest" "$name"; then
      rm -f "$dest"
      printf '  \033[38;2;210;140;0m%-9s\033[0m  %s\n' "removed" "$name"
    else
      warn "left $dest in place (not an mtv-skills link)"
    fi
  done
}

term_cols() {
  local cols
  cols=$(tput cols 2>/dev/null || true)
  case "$cols" in
    ''|*[!0-9]*) cols=80 ;;
  esac
  printf '%s' "$cols"
}

term_rows() {
  local rows
  rows=$(tput lines 2>/dev/null || true)
  case "$rows" in
    ''|*[!0-9]*) rows=24 ;;
  esac
  printf '%s' "$rows"
}

fit_text() {
  local text="$1"
  local width="$2"
  if [ "$width" -le 0 ]; then
    return
  fi
  if [ "${#text}" -le "$width" ]; then
    printf '%s' "$text"
    return
  fi
  if [ "$width" -le 3 ]; then
    printf '%s' "${text:0:$width}"
    return
  fi
  printf '%s...' "${text:0:$((width - 3))}"
}

row_action() {
  local i="$1"
  if [ "${skill_selected[$i]}" -eq 1 ]; then
    if [ "${skill_installed[$i]}" -eq 1 ]; then
      printf 'update'
    else
      printf 'install'
    fi
  elif [ "${skill_installed[$i]}" -eq 1 ]; then
    printf 'remove'
  else
    printf 'skip'
  fi
}

print_row() {
  local i="$1"
  local marker box action_pad name_pad cols desc_width desc
  cols=$(term_cols)
  if [ "$i" -eq "$cursor" ]; then
    marker='>'
  else
    marker=' '
  fi
  if [ "${skill_selected[$i]}" -eq 1 ]; then
    box=$(printf '\033[38;2;40;180;90mx\033[0m')
  else
    box=' '
  fi
  action_pad=$(printf '%-7s' "$(row_action "$i")")
  case "$(row_action "$i")" in
    install) action_pad=$(printf '\033[38;2;40;180;90m%s\033[0m' "$action_pad") ;;
    update)  action_pad=$(printf '\033[38;2;0;170;180m%s\033[0m' "$action_pad") ;;
    remove)  action_pad=$(printf '\033[38;2;210;140;0m%s\033[0m' "$action_pad") ;;
    *)       action_pad=$(printf '\033[2m%s\033[0m' "$action_pad") ;;
  esac
  name_pad=$(printf '%-*s' "$NAME_WIDTH" "${skill_names[$i]}")
  if [ "$i" -eq "$cursor" ]; then
    name_pad=$(printf '\033[1m%s\033[0m' "$name_pad")
  fi
  desc_width=$((cols - 17 - NAME_WIDTH))
  desc=$(fit_text "${skill_descs[$i]}" "$desc_width")
  printf '%s [%s] %s  %s  %s\033[K\n' "$marker" "$box" "$action_pad" "$name_pad" "$desc"
}

draw_menu() {
  local rows body total i action
  local n_install=0 n_update=0 n_remove=0
  rows=$(term_rows)
  total=${#skill_names[@]}
  body=$((rows - 7))
  [ "$body" -lt 1 ] && body=1
  [ "$body" -gt "$total" ] && body=$total
  if [ "$cursor" -lt "$menu_start" ]; then
    menu_start=$cursor
  elif [ "$cursor" -ge $((menu_start + body)) ]; then
    menu_start=$((cursor - body + 1))
  fi

  printf '\033[H'
  printf '\033[1mmtv-skills\033[0m  %s\033[K\n' "$SKILLS_TARGET"
  printf '\033[K\n'
  if [ "$any_installed" -eq 1 ]; then
    printf 'Already linked skills can be updated or removed.\033[K\n'
  else
    printf 'Nothing is linked yet.\033[K\n'
  fi
  printf '\033[2mspace\033[0m mark   \033[2mj/k\033[0m move   \033[2ma\033[0m all   \033[2menter\033[0m apply   \033[2mq\033[0m abort\033[K\n'
  printf '\033[K\n'

  i=$menu_start
  while [ "$i" -lt $((menu_start + body)) ] && [ "$i" -lt "$total" ]; do
    print_row "$i"
    i=$((i + 1))
  done

  i=0
  while [ "$i" -lt "$total" ]; do
    action=$(row_action "$i")
    case "$action" in
      install) n_install=$((n_install + 1)) ;;
      update)  n_update=$((n_update + 1)) ;;
      remove)  n_remove=$((n_remove + 1)) ;;
    esac
    i=$((i + 1))
  done
  printf '\033[K\n'
  printf '%d \033[38;2;40;180;90minstall\033[0m, %d \033[38;2;0;170;180mupdate\033[0m, %d \033[38;2;210;140;0mremove\033[0m\033[K\n' "$n_install" "$n_update" "$n_remove"
  printf '\033[J'
}

enter_menu_tty() {
  SAVED_STTY=$(stty -g)
  menu_active=1
  # -icrnl keeps Enter as CR. Bash 3.2 read -n treats NL as a delimiter and
  # would otherwise drop it, so the key never reached the menu.
  stty -echo -icanon -icrnl min 1 time 0
  tput civis 2>/dev/null || printf '\033[?25l'
  trap 'cancel_menu 130' INT
}

read_key() {
  local ch="" extra=""
  KEY=""
  IFS= read -rsn1 KEY || return 1
  if [ "$KEY" = $'\033' ]; then
    stty -echo -icanon -icrnl min 0 time 1
    IFS= read -rsn1 ch || ch=""
    if [ -n "$ch" ]; then
      extra=$ch
      ch=""
      IFS= read -rsn1 ch || ch=""
      extra="$extra$ch"
    fi
    stty -echo -icanon -icrnl min 1 time 0
    KEY="${KEY}${extra}"
  fi
}

move_cursor() {
  local delta="$1"
  local last=$((${#skill_names[@]} - 1))
  cursor=$((cursor + delta))
  if [ "$cursor" -lt 0 ]; then
    cursor=0
  fi
  if [ "$cursor" -gt "$last" ]; then
    cursor=$last
  fi
}

toggle_current() {
  if [ "${skill_selected[$cursor]}" -eq 1 ]; then
    skill_selected[$cursor]=0
  else
    skill_selected[$cursor]=1
  fi
}

toggle_all() {
  local i all=1
  for i in "${!skill_selected[@]}"; do
    if [ "${skill_selected[$i]}" -eq 0 ]; then
      all=0
      break
    fi
  done
  if [ "$all" -eq 1 ]; then
    for i in "${!skill_selected[@]}"; do
      skill_selected[$i]=0
    done
  else
    for i in "${!skill_selected[@]}"; do
      skill_selected[$i]=1
    done
  fi
}

run_menu() {
  cursor=0
  menu_start=0
  enter_menu_tty
  while true; do
    draw_menu
    if ! read_key; then
      cancel_menu 0
    fi
    case "$KEY" in
      j|J|$'\033[B'|$'\033OB')
        move_cursor 1
        ;;
      k|K|$'\033[A'|$'\033OA')
        move_cursor -1
        ;;
      ' ')
        toggle_current
        ;;
      a|A)
        toggle_all
        ;;
      q|Q)
        cancel_menu 0
        ;;
      ''|$'\r'|$'\n')
        break
        ;;
    esac
  done
  cleanup_tty
  printf '\033[H\033[2J'
}

choose_and_link() {
  if [ "${#skill_names[@]}" -eq 0 ]; then
    warn "No skills found in $INSTALL_DIR/skills"
    return
  fi
  if [ ! -t 0 ]; then
    error "A terminal is required to choose which skills to link."
  fi
  run_menu
  apply_selection
}

command -v git >/dev/null 2>&1 || error "git is required but not found in PATH"

if [ "${1:-}" != "--from-checkout" ]; then
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

  # A curled install.sh sits alone and can be older than the checkout just pulled.
  # Hand off to that copy when it knows this flag. A script next to skills/ is
  # already a checkout, so keep running it instead of the installed copy.
  script_dir=$(cd "$(dirname "$0")" && pwd -P) || script_dir=""
  if [ -n "$script_dir" ] && [ ! -d "$script_dir/skills" ] && [ -f "$INSTALL_DIR/install.sh" ]; then
    if grep -q -- '--from-checkout' "$INSTALL_DIR/install.sh"; then
      here=$(canonical_script "$0") || here=""
      there=$(canonical_script "$INSTALL_DIR/install.sh") || there=""
      if [ -n "$here" ] && [ -n "$there" ] && [ "$here" != "$there" ]; then
        exec "${BASH:-bash}" "$INSTALL_DIR/install.sh" --from-checkout
      fi
    fi
  fi
fi

load_skills
choose_and_link

echo ""
ok "Done! Skills are ready to use."
info "Re-run this command any time to update."

# --- optional: install CLI tools with hash verification -----------------------
if [ "${INSTALL_CLI_TOOLS:-0}" = "1" ]; then
  echo ""
  printf '\033[38;2;70;140;255m[info]\033[0m  Installing CLI tools (\033[38;2;0;170;180mINSTALL_CLI_TOOLS=1\033[0m) ...\n'
  "$INSTALL_DIR/tools/install-tools.sh"
else
  echo ""
  info "To also install the CLI plugins (kubectl-mtv, kubectl-metrics, etc.):"
  code "INSTALL_CLI_TOOLS=1 bash \"$INSTALL_DIR/install.sh\""
  info "Or run directly:"
  code "$INSTALL_DIR/tools/install-tools.sh"
fi
