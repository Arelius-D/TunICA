#!/bin/bash
# TunICA installer - user space only, no sudo, nothing written outside your home.
#
#   curl -fsSL https://raw.githubusercontent.com/Arelius-D/TunICA/main/install.sh | bash
#
#   ./install.sh                 install (interactive)
#   ./install.sh --update        update an existing installation, keeping tunica.env and maps
#   ./install.sh --uninstall     remove the installation
#   ./install.sh --check         verify an installation and its dependencies
#
#   --path DIR   install location (default: $HOME/TunICA)
#   -y, --yes    accept every default, ask nothing (for scripted installs)
#   --no-alias   do not set an alias or touch any shell rc file
#   -v           print installer version
#   -h           this help
#
# The installer copies TunICA into a directory you name, optionally sets a `tunica`
# alias in the shells you choose, and writes a .env you can edit afterwards. It
# never uses sudo, never writes outside your home, and logs everything it does.
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
set -euo pipefail

CODE_VERSION="1.0.4"
REPO_SLUG="Arelius-D/TunICA"
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
  SOURCE_DIR="$(cd "$(dirname "$(readlink -f "$SELF")")" && pwd)"
else
  SOURCE_DIR="$PWD"
fi
HELP_LINES='2,19p'
NL=$'\n'
LOG_FILE="${TUNICA_INSTALL_LOG:-$HOME/.tunica-install.log}"
INSTALL_DIR="${TUNICA_INSTALL_DIR:-$HOME/TunICA}"
ASSUME_YES=no
ACTION=install
WIRE_PATH=yes
PAYLOAD=(tunica.sh install.sh lib viewer tunica.env LICENSE)

usage() {
  if [ -n "$SELF" ] && [ -f "$SELF" ]; then
    sed -n "$HELP_LINES" "$SELF" | sed 's/^# \{0,1\}//'
  else
    printf 'TunICA installer %s\n  --update --uninstall --check --path DIR -y --no-alias -v -h\n  https://github.com/%s\n' "$CODE_VERSION" "$REPO_SLUG"
  fi
}
log() {
  local level="$1"; shift
  printf '[%s] %s\n' "$level" "$*"
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE" 2>/dev/null || true
}
die() { log ERROR "$*"; exit 1; }
ask() {
  local prompt="$1" default="$2" reply
  if [ "$ASSUME_YES" = yes ] || [ ! -r /dev/tty ]; then printf '%s' "$default"; return; fi
  read -r -p "$prompt  [Enter = $default]: " reply < /dev/tty || reply=""
  printf '%s' "${reply:-$default}"
}
confirm() {
  local reply; reply="$(ask "$1 (y/n)" "$2")"
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------- args
while [ $# -gt 0 ]; do
  case "$1" in
    --update) ACTION=update; shift ;;
    --uninstall|--remove) ACTION=uninstall; shift ;;
    --check) ACTION=check; shift ;;
    --path) INSTALL_DIR="${2:?--path needs a directory}"; shift 2 ;;
    -y|--yes) ASSUME_YES=yes; shift ;;
    --no-alias|--no-path) WIRE_PATH=no; shift ;;
    -v|--version) printf 'TunICA installer %s\n' "$CODE_VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

# ---------------------------------------------------------------- dependencies
check_deps() {
  local missing=0 p
  for p in bash python3; do
    command -v "$p" >/dev/null || { log ERROR "$p is required and was not found"; missing=1; }
  done
  command -v git >/dev/null || log WARNING "git not found: local paths still work, URL targets do not"
  local claude; claude="${TUNICA_CLAUDE_BIN:-$(command -v claude || true)}"
  [ -n "$claude" ] || { [ -x "$HOME/.local/bin/claude" ] && claude="$HOME/.local/bin/claude"; }
  if [ -z "$claude" ] || [ ! -x "$claude" ]; then
    log ERROR "the Claude Code CLI was not found, and it is the model backend"
    log ERROR "  install it and log in, then run this installer again"
    missing=1
  fi
  printf '%s' "$claude" > /tmp/.tunica-claude-path.$$ 2>/dev/null || true
  [ "$missing" -eq 0 ] || return 1
  log INFO "dependencies ok"
  return 0
}

ask_install_dir() {
  local def="$1" reply
  while :; do
    reply="$(ask "install to $def? (y/n, or another path under \$HOME)" "y")"
    case "$reply" in
      [yY]|[yY][eE][sS]) printf '%s' "$def"; return 0 ;;
      [nN]|[nN][oO]) return 1 ;;
      *)
        reply="${reply/#\~/$HOME}"
        case "$reply" in
          "$HOME"/*) printf '%s' "${reply%/}"; return 0 ;;
          *) log WARNING "  $reply is outside \$HOME. TunICA installs into your home directory only." >&2 ;;
        esac
        ;;
    esac
  done
}

# ---------------------------------------------------------------- source resolution
FETCH_ROOT=""
SRC=""
cleanup() { [ -n "$FETCH_ROOT" ] && rm -rf "$FETCH_ROOT"; rm -f /tmp/.tunica-claude-path.$$; }
trap cleanup EXIT

resolve_source() {
  local here="" there=""
  here="$(cd "$SOURCE_DIR" 2>/dev/null && pwd || true)"
  there="$(cd "$INSTALL_DIR" 2>/dev/null && pwd || true)"
  if [ -f "$SOURCE_DIR/tunica.sh" ] && [ -d "$SOURCE_DIR/lib" ] && [ "$here" != "$there" ]; then
    SRC="$SOURCE_DIR"; return
  fi
  command -v curl >/dev/null || die "curl is required to download TunICA"
  FETCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tunica-fetch-XXXXXX")"
  log INFO "downloading $REPO_SLUG (main)"
  curl -fsSL "https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/main" \
    | tar -xz -C "$FETCH_ROOT" || die "download failed. Check the network, or install from a checkout"
  SRC="$(find "$FETCH_ROOT" -maxdepth 1 -type d -name 'TunICA-*' | head -1)"
}

merge_env() {
  local shipped="$1" user="$2" version="$3" line key block="" added="" pending
  [ -f "$shipped" ] && [ -f "$user" ] || return 0
  pending="$(mktemp "${TMPDIR:-/tmp}/tunica-env-XXXXXX")" || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    key="$(printf '%s\n' "$line" | sed -n 's/^[[:space:]]*#\{0,1\}[[:space:]]*\(TUNICA_[A-Z0-9_]*\)=.*$/\1/p')"
    if [ -z "$key" ]; then
      if [ -z "$line" ]; then block=""; else block="$block$line$NL"; fi
      continue
    fi
    if grep -qE "^[[:space:]]*#?[[:space:]]*$key=" "$user"; then block=""; continue; fi
    printf '%s%s\n\n' "$block" "$line" >> "$pending"
    added="$added $key"
    block=""
  done < "$shipped"

  if [ -s "$pending" ]; then
    cp -p "$user" "$user.bak" 2>/dev/null || true
    {
      printf '\n# --- new in %s ------------------------------------------------------------\n' "$version"
      printf '# Added by the update because your file predates these. Commented out, so each is\n'
      printf '# still at its built-in default until you choose otherwise.\n\n'
      cat "$pending"
    } >> "$user"
    log INFO "tunica.env: added$added (previous kept as tunica.env.bak)"
  else
    log INFO "tunica.env: no new settings, left untouched"
  fi
  rm -f "$pending"
}

copy_payload() {
  local src="$1" dst="$2" item
  mkdir -p "$dst"
  for item in "${PAYLOAD[@]}"; do
    [ -e "$src/$item" ] || continue
    if [ "$item" = tunica.env ] && [ -f "$dst/tunica.env" ]; then continue; fi
    rm -rf "$dst/${item%/}"
    cp -R "$src/$item" "$dst/"
  done
  chmod +x "$dst/tunica.sh"
  mkdir -p "$dst/out"; : > "$dst/out/.gitkeep"
}

installed_version() { sed -n 's/^CODE_VERSION="\(.*\)"$/\1/p' "$1/tunica.sh" 2>/dev/null | head -1; }

# ---------------------------------------------------------------- alias wiring
BLOCK_START="# >>> TunICA >>>"
BLOCK_END="# <<< TunICA <<<"

shell_rc() {
  case "$(basename "${SHELL:-/bin/bash}")" in
    zsh)  printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash) printf '%s' "$HOME/.bashrc" ;;
    fish) printf '%s' "$HOME/.config/fish/config.fish" ;;
    *)    printf '%s' "$HOME/.profile" ;;
  esac
}

every_rc() {
  local rc
  for rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.config/fish/config.fish" "$HOME/.profile"; do
    [ -f "$rc" ] && printf '%s\n' "$rc"
  done
}

wire_path() {
  local rc found=0 wrote=0
  found="$(every_rc | wc -l)"
  if [ "$found" -eq 0 ]; then
    log WARNING "alias: found no shell rc file to write to. Run TunICA as: $INSTALL_DIR/tunica.sh"
    return
  fi
  log INFO "alias: 'tunica' -> $INSTALL_DIR/tunica.sh"
  while IFS= read -r rc; do
    confirm "  set it in $(basename "$rc")?" y || { log INFO "  skipped $(basename "$rc")"; continue; }
    remove_alias_block "$rc"
    {
      printf '\n%s\n' "$BLOCK_START"
      printf 'alias tunica="%s/tunica.sh"\n' "$INSTALL_DIR"
      printf '%s\n' "$BLOCK_END"
    } >> "$rc"
    log INFO "  added to $rc"
    wrote=$((wrote + 1))
  done < <(every_rc)
  if [ "$wrote" -eq 0 ]; then
    log WARNING "alias: set nowhere. Run TunICA as: $INSTALL_DIR/tunica.sh"
  else
    log INFO "alias: open in $wrote shell rc file(s). Open a new shell to use it."
  fi
}

remove_alias_block() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  grep -q "$BLOCK_START" "$rc" || return 0
  local tmp; tmp="$(mktemp)"
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
    $0 ~ s { skip = 1 } !skip { print } $0 ~ e { skip = 0 }
  ' "$rc" > "$tmp" && mv "$tmp" "$rc"
  log INFO "removed the TunICA block from $rc"
}

# ---------------------------------------------------------------- onboarding
set_setting() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^#?${key}=" "$file"; then
    sed -i "0,/^#\?${key}=.*$/s||${key}=\"${value//|/\\|}\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

onboard() {
  local fresh="${1:-no}"
  local env_file="$INSTALL_DIR/tunica.env" claude model out_root view_port
  if [ "$fresh" != yes ]; then
    log INFO "keeping the settings already in $env_file"
    return
  fi
  claude="$(cat /tmp/.tunica-claude-path.$$ 2>/dev/null || true)"
  log INFO "three questions, all changeable later in $env_file. Enter accepts each default."
  model="$(ask "  default model (sonnet / opus / haiku)" "sonnet")"
  out_root="$(ask "  where should generated maps be written" "$INSTALL_DIR/out")"
  out_root="${out_root/#\~/$HOME}"
  mkdir -p "$out_root"
  view_port="$(ask "  port for the local viewer" "8866")"
  set_setting "$env_file" TUNICA_MODEL "$model"
  set_setting "$env_file" TUNICA_VIEW_PORT "$view_port"
  set_setting "$env_file" TUNICA_OUT_ROOT "$out_root"
  set_setting "$env_file" TUNICA_LOG_FILE "$INSTALL_DIR/tunica.log"
  [ -n "$claude" ] && set_setting "$env_file" TUNICA_CLAUDE_BIN "$claude"
  log INFO "settings written into $env_file"
}

# ---------------------------------------------------------------- actions
do_install() {
  local src fresh=yes
  [ -d "$INSTALL_DIR/lib" ] && fresh=no
  log INFO "TunICA installer $CODE_VERSION"
  check_deps || die "the environment is not ready. Nothing was installed"

  if [ "$fresh" = yes ]; then
    INSTALL_DIR="$(ask_install_dir "$INSTALL_DIR")" || { log INFO "cancelled"; return; }
  fi
  case "$INSTALL_DIR" in
    "$HOME"/*|"$HOME") ;;
    *) die "refusing to install outside your home directory: $INSTALL_DIR" ;;
  esac

  resolve_source; src="$SRC"
  [ -n "$src" ] && [ -f "$src/tunica.sh" ] || die "could not resolve a TunICA source tree"
  log INFO "installing $(installed_version "$src") -> $INSTALL_DIR"
  copy_payload "$src" "$INSTALL_DIR"
  onboard "$fresh"
  [ "$WIRE_PATH" = yes ] && wire_path || log INFO "alias: skipped (--no-alias)"

  log INFO "verifying"
  "$INSTALL_DIR/tunica.sh" -v >/dev/null || die "installed copy does not run"
  log INFO "done. TunICA $(installed_version "$INSTALL_DIR") is installed."
  log INFO "  map a repo:   tunica ~/GitHub/some-repo"
  log INFO "  a URL:        tunica owner/repo"
  log INFO "  view maps:    tunica view"
  log INFO "  settings:     $INSTALL_DIR/tunica.env"
  log INFO "  install log:  $LOG_FILE"
}

do_update() {
  [ -f "$INSTALL_DIR/tunica.sh" ] || die "nothing installed at $INSTALL_DIR. Run without --update first"
  local src current candidate
  current="$(installed_version "$INSTALL_DIR")"
  resolve_source; src="$SRC"
  [ -n "$src" ] && [ -f "$src/tunica.sh" ] || die "could not resolve a TunICA source tree"
  candidate="$(installed_version "$src")"
  log INFO "installed $current -> available $candidate"
  if [ "$current" = "$candidate" ] && ! confirm "same version. Reinstall anyway?" n; then
    log INFO "nothing to do"; return
  fi
  cp -p "$INSTALL_DIR/tunica.env" "$INSTALL_DIR/.tunica.env.keep" 2>/dev/null || true
  copy_payload "$src" "$INSTALL_DIR"
  if [ -f "$INSTALL_DIR/.tunica.env.keep" ]; then
    mv "$INSTALL_DIR/.tunica.env.keep" "$INSTALL_DIR/tunica.env"
    merge_env "$src/tunica.env" "$INSTALL_DIR/tunica.env" "$candidate"
  fi
  "$INSTALL_DIR/tunica.sh" -v >/dev/null || die "updated copy does not run"
  log INFO "updated to $(installed_version "$INSTALL_DIR"); your settings and existing maps kept"
  if systemctl --user is-active tunica.service >/dev/null 2>&1; then
    log WARNING "tunica.service is running the previous version. Run:"
    log WARNING "  systemctl --user restart tunica.service"
  fi
}

do_uninstall() {
  [ -d "$INSTALL_DIR" ] || die "nothing installed at $INSTALL_DIR"
  local out_root
  out_root="$(sed -n 's/^TUNICA_OUT_ROOT="\(.*\)"$/\1/p' "$INSTALL_DIR/tunica.env" 2>/dev/null | head -1)"
  confirm "remove $INSTALL_DIR?" y || { log INFO "cancelled"; return; }
  local unit="$HOME/.config/systemd/user/tunica.service"
  if [ -f "$unit" ]; then
    if confirm "a systemd --user service is installed. Remove it too?" y; then
      systemctl --user disable --now tunica.service >/dev/null 2>&1 || true
      rm -f "$unit"
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      log INFO "removed $unit"
    else
      log WARNING "kept $unit, which now points at a path this is deleting."
      log WARNING "  it will fail and retry every 5s. Remove it with: tunica service remove"
    fi
  fi
  local rc
  while IFS= read -r rc; do remove_alias_block "$rc"; done < <(every_rc)
  if [ -n "$out_root" ] && [ "${out_root#$INSTALL_DIR}" = "$out_root" ] && [ -d "$out_root" ]; then
    if confirm "also delete your generated maps in $out_root?" n; then rm -rf "$out_root"; log INFO "removed $out_root"
    else log INFO "kept your maps in $out_root"; fi
  fi
  rm -rf "$INSTALL_DIR"
  log INFO "removed $INSTALL_DIR"
  confirm "remove the installer log $LOG_FILE too?" n && rm -f "$LOG_FILE" || true
}

do_check() {
  log INFO "TunICA installer $CODE_VERSION, checking $INSTALL_DIR"
  local ok=0
  if [ -f "$INSTALL_DIR/tunica.sh" ]; then log INFO "  installed version: $(installed_version "$INSTALL_DIR")"
  else log ERROR "  no installation at $INSTALL_DIR"; ok=1; fi
  local item
  for item in "${PAYLOAD[@]}"; do
    [ -e "$INSTALL_DIR/$item" ] && log INFO "  $item: present" || { log ERROR "  $item: MISSING"; ok=1; }
  done
  local part
  for part in vendor/mermaid/mermaid.esm.min.mjs index.html styles.css viewer.js theme.js serve.py; do
    [ -e "$INSTALL_DIR/viewer/$part" ] || { log ERROR "  viewer/$part: MISSING"; ok=1; }
  done
  [ "$ok" -eq 0 ] && log INFO "  viewer: page, styles, scripts, server and vendored renderer all present" || true
  [ -f "$INSTALL_DIR/tunica.env" ] && log INFO "  tunica.env: present" || log WARNING "  tunica.env: absent (defaults apply)"
  local aliased=0 rc
  while IFS= read -r rc; do grep -q "$BLOCK_START" "$rc" 2>/dev/null && aliased=$((aliased + 1)); done < <(every_rc)
  [ "$aliased" -gt 0 ] && log INFO "  alias: set in $aliased shell rc file(s)" \
    || log WARNING "  alias: not set. Run TunICA as: $INSTALL_DIR/tunica.sh"
  if [ -f "$HOME/.config/systemd/user/tunica.service" ]; then
    log INFO "  service: installed, $(systemctl --user is-active tunica.service 2>/dev/null || echo unknown)"
  else
    log INFO "  service: none. The viewer runs in a terminal until you ask otherwise"
  fi
  log INFO "dependencies:"
  check_deps || ok=1
  [ "$ok" -eq 0 ] && log INFO "check passed" || die "check failed"
}

case "$ACTION" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
  check)     do_check ;;
esac
