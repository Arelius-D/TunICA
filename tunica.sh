#!/bin/bash
# TunICA - Layered repository maps drawn by YOUR OWN AI subscription (Claude CLI).
#
# No API keys, no hosted service, no lockouts: the engine builds the prompts, the
# `claude` CLI you already have does the thinking on the plan you already pay for,
# and the output is Markdown + Mermaid you can read anywhere.
#
#   tunica <repo-path|git-url|owner/repo> [options]   map a repository
#   tunica view [name] [port]                         serve the maps in a browser
#   tunica remove <name> [-y]                         delete a stored map
#   tunica service <install|remove|status>            optional: run the viewer as a
#                                                     systemd --user service. Off unless
#                                                     you ask; no sudo, no system unit.
#
#   -d 1|2      depth: 1 = system map only, 2 = + one map per component
#   -o DIR      write this run's map here (default: <out root>/<repo-name>)
#   -m MODEL    model passed to claude --model
#   -q          quiet: log to file only
#   -v          print version and exit
#   -h          this help
#
# A URL or owner/repo is cloned shallow into a temp dir and deleted afterwards.
# Configuration: tunica.env beside this script. Precedence is
# flag > shell environment > tunica.env > built-in default.
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
set -euo pipefail

CODE_VERSION="1.0.0-dev"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
HELP_LINES='2,24p'
QUIET=no

usage() { sed -n "$HELP_LINES" "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- configuration
load_env_file() {
  local file="$1" line key val
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"; key="${key#export }"; key="$(printf '%s' "$key" | tr -d '[:space:]')"
    case "$key" in TUNICA_*) ;; *) continue ;; esac
    [ -n "${!key:-}" ] && continue
    val="${line#*=}"
    val="$(eval "printf '%s' $val" 2>/dev/null || printf '%s' "$val")"
    export "$key=$val"
  done < "$file"
}
load_env_file "${TUNICA_ENV_FILE:-$SCRIPT_DIR/tunica.env}"

OUT_ROOT="${TUNICA_OUT_ROOT:-$SCRIPT_DIR/out}"
LOG_FILE="${TUNICA_LOG_FILE:-$SCRIPT_DIR/tunica.log}"
LOG_MAX_DAYS="${TUNICA_LOG_MAX_DAYS:-14}"
MODEL="${TUNICA_MODEL:-sonnet}"
DEPTH="${TUNICA_DEPTH:-2}"
TIMEOUT="${TUNICA_TIMEOUT:-600}"
VIEW_PORT="${TUNICA_VIEW_PORT:-8864}"
VIEW_BIND="${TUNICA_VIEW_BIND:-auto}"
MAX_FILES="${TUNICA_MAX_FILES:-4000}"
export TUNICA_MAX_FILE_BYTES="${TUNICA_MAX_FILE_BYTES:-60000}"
export TUNICA_MAX_COMPONENT_BYTES="${TUNICA_MAX_COMPONENT_BYTES:-120000}"

# ---------------------------------------------------------------- logging
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
: >> "$LOG_FILE" 2>/dev/null || LOG_FILE=/dev/null

log() {
  local level="$1"; shift
  [ "$QUIET" = yes ] || printf '[%s] %s\n' "$level" "$*"
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}
die() { log ERROR "$*"; exit 1; }

run_step() {
  local out
  if ! out="$("$@" 2>&1)"; then log ERROR "$out"; exit 1; fi
  [ -z "$out" ] && return 0
  while IFS= read -r line; do
    case "$line" in
      "[ERROR] "*)              log ERROR   "${line#\[ERROR\] }" ;;
      "[WARNING] "*|"[WARN] "*) log WARNING "${line#*\] }" ;;
      "[INFO] "*)               log INFO    "${line#\[INFO\] }" ;;
      *)                        log INFO    "$line" ;;
    esac
  done <<< "$out"
}

prune_log() {
  [ "$LOG_MAX_DAYS" -gt 0 ] 2>/dev/null || return 0
  [ -s "$LOG_FILE" ] || return 0
  local cutoff tmp
  cutoff="$(date -d "-$LOG_MAX_DAYS days" '+%Y-%m-%d' 2>/dev/null || true)"
  [ -n "$cutoff" ] || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/tunica-log-XXXXXX")"
  awk -v c="$cutoff" '
    match($0, /^\[[0-9]{4}-[0-9]{2}-[0-9]{2}/) { keep = (substr($0, 2, 10) >= c) }
    keep || keep == "" { print }
  ' "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
}

# ---------------------------------------------------------------- view mode
if [ "${1:-}" = "view" ]; then
  NAME="${2:-}"; PORT="${3:-$VIEW_PORT}"
  [ -n "$NAME" ] || NAME="$(ls -1 "$OUT_ROOT" 2>/dev/null | grep -v '^\.' | head -1 || true)"
  [ -n "$NAME" ] && [ -d "$OUT_ROOT/$NAME" ] || die "no maps found in $OUT_ROOT. Run an analysis first"
  ln -sfn "$OUT_ROOT" "$SCRIPT_DIR/viewer/out" 2>/dev/null || die "cannot expose $OUT_ROOT to the viewer"
  BIND="$VIEW_BIND"
  [ "$BIND" != auto ] || { [ -n "${SSH_CONNECTION:-}" ] && BIND=0.0.0.0 || BIND=127.0.0.1; }
  QUERY="?repo=$NAME&name=overview"

  if [ -n "${TUNICA_VIEW_URL:-}" ]; then
    log INFO "view: ${TUNICA_VIEW_URL%/}/$QUERY"
  elif [ "$BIND" = 127.0.0.1 ] || [ "$BIND" = localhost ]; then
    log INFO "view: http://127.0.0.1:$PORT/$QUERY"
  elif [ "$BIND" = 0.0.0.0 ] || [ "$BIND" = "::" ]; then
    log INFO "view: reachable on whichever of these your device can route to"
    while read -r iface addr; do
      [ -n "$addr" ] && log INFO "      http://${addr%%/*}:$PORT/$QUERY   ($iface)"
    done < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2, $4}')
    log INFO "      also http://127.0.0.1:$PORT/$QUERY   (on this host)"
  else
    log INFO "view: http://$BIND:$PORT/$QUERY"
  fi
  log INFO "      component map: same URL with &name=<component-id>"
  log INFO "      the server runs until you stop it with Ctrl+C"

  if [ "$BIND" = 0.0.0.0 ] || [ "$BIND" = "::" ]; then
    log INFO "      note: bound to every interface, so anything that can route to this host can read these maps"
    log INFO "      behind a reverse proxy? point it at 127.0.0.1:$PORT and set TUNICA_VIEW_URL to the public address"
  elif [ -n "${SSH_CONNECTION:-}" ]; then
    log INFO "      bound to loopback on a remote session. Tunnel it, or set TUNICA_VIEW_BIND=0.0.0.0"
    log INFO "      ssh -N -L $PORT:127.0.0.1:$PORT $(whoami)@$(printf '%s' "${SSH_CONNECTION:-}" | awk '{print $3}')"
  fi
  exec python3 "$SCRIPT_DIR/viewer/serve.py" "$PORT" "$BIND"
fi

# ---------------------------------------------------------------- remove mode
if [ "${1:-}" = "remove" ]; then
  NAME="${2:-}"; AGREED="${3:-}"
  [ -n "$NAME" ] || die "usage: tunica remove <map-name> [-y]"
  case "$NAME" in */*|.*) die "not a map name: $NAME" ;; esac
  GONE="$OUT_ROOT/$NAME"
  [ -f "$GONE/overview.md" ] || die "no map called $NAME in $OUT_ROOT"
  log INFO "$NAME: $(find "$GONE" -maxdepth 1 -name '*.md' | wc -l) map file(s) in $GONE"
  if [ "$AGREED" != "-y" ] && [ "$AGREED" != "--yes" ]; then
    [ -r /dev/tty ] || die "not a terminal. Pass -y to remove without being asked"
    printf 'remove %s permanently? [y/N]: ' "$NAME" > /dev/tty
    read -r REPLY < /dev/tty || REPLY=""
    case "$REPLY" in [yY]*) ;; *) log INFO "cancelled, $NAME kept"; exit 0 ;; esac
  fi
  rm -rf "$GONE"
  log INFO "removed $NAME"
  exit 0
fi

# ---------------------------------------------------------------- service mode
if [ "${1:-}" = "service" ]; then
  ACTION="${2:-status}"
  UNIT_DIR="$HOME/.config/systemd/user"
  UNIT="$UNIT_DIR/tunica.service"
  command -v systemctl >/dev/null || die "systemctl not found. This host does not use systemd; keep the viewer in a terminal, or use whatever supervisor it does have"

  case "$ACTION" in
    install)
      mkdir -p "$UNIT_DIR"
      EXEC="$SCRIPT_DIR/tunica.sh view"
      [ -n "${3:-}" ] && EXEC="$EXEC $3"
      [ -n "${4:-}" ] && EXEC="$EXEC $4"
      cat > "$UNIT" <<EOU
[Unit]
Description=TunICA map viewer
After=network-online.target

[Service]
Type=simple
ExecStart=$EXEC
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOU
      log INFO "wrote $UNIT"
      systemctl --user daemon-reload
      systemctl --user enable --now tunica.service || die "systemctl --user failed. Is a user session bus running?"
      log INFO "tunica.service is enabled and running"
      if [ "$VIEW_BIND" = auto ]; then
        log WARNING "TUNICA_VIEW_BIND is 'auto', which under a service means 127.0.0.1 only."
        log WARNING "  Set TUNICA_VIEW_BIND=0.0.0.0 in $SCRIPT_DIR/tunica.env to reach it from the network,"
        log WARNING "  then: systemctl --user restart tunica.service"
      fi
      if [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" != "yes" ]; then
        log WARNING "lingering is off: this stops when you log out. Enable it with:"
        log WARNING "  loginctl enable-linger $(id -un)"
        log WARNING "  (that one command may ask for your password; nothing else here does)"
      fi
      ;;
    remove)
      systemctl --user disable --now tunica.service 2>/dev/null || true
      rm -f "$UNIT"
      systemctl --user daemon-reload 2>/dev/null || true
      log INFO "removed $UNIT. Lingering, if you enabled it, is untouched: loginctl disable-linger $(id -un)"
      ;;
    status)
      if [ -f "$UNIT" ]; then
        systemctl --user status tunica.service --no-pager || true
      else
        log INFO "no service installed. TunICA runs in a terminal until you ask otherwise."
        log INFO "to run it as a user service (no sudo, no system units): tunica service install [name] [port]"
      fi
      ;;
    *) die "usage: tunica service <install|remove|status> [name] [port]" ;;
  esac
  exit 0
fi

# ---------------------------------------------------------------- args
OUT_DIR=""; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) DEPTH="${2:?-d needs 1 or 2}"; shift 2 ;;
    -o) OUT_DIR="${2:?-o needs a directory}"; shift 2 ;;
    -m) MODEL="${2:?-m needs a model name}"; shift 2 ;;
    -q|--quiet) QUIET=yes; shift ;;
    -v|--version) printf 'TunICA %s\n' "$CODE_VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || { usage; exit 2; }
[ "$DEPTH" = 1 ] || [ "$DEPTH" = 2 ] || die "-d must be 1 or 2 (got '$DEPTH')"
prune_log

# ---------------------------------------------------------------- resolve the target
CLONE_ROOT=""
cleanup() { [ -n "$CLONE_ROOT" ] && rm -rf "$CLONE_ROOT"; return 0; }
trap cleanup EXIT

URL=""
if [ -d "$TARGET" ]; then
  REPO="$(cd "$TARGET" && pwd)"
elif printf '%s' "$TARGET" | grep -qE '^(https?://|git@|ssh://)'; then
  URL="$TARGET"
elif printf '%s' "$TARGET" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
  URL="https://github.com/$TARGET"
else
  die "not a directory, URL, or owner/repo: $TARGET"
fi

if [ -n "$URL" ]; then
  command -v git >/dev/null || die "git is required to clone $URL"
  REPO_NAME="$(basename "${URL%/}" .git)"
  CLONE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tunica-clone-XXXXXX")"
  REPO="$CLONE_ROOT/$REPO_NAME"
  log INFO "cloning $URL (shallow, temporary)"
  git clone --quiet --depth 1 "$URL" "$REPO" || die "clone failed: $URL"
else
  REPO_NAME="$(basename "$REPO")"
fi

[ -n "$OUT_DIR" ] || OUT_DIR="$OUT_ROOT/$REPO_NAME"

WORK="$OUT_DIR/.work"
mkdir -p "$WORK"
RUN_STARTED="$(date +%s)"
{ printf 'target=%s\n' "${URL:-$REPO}"; printf 'depth=%s\n' "$DEPTH"; } > "$WORK/source.txt"
STDERR_LOG="$WORK/claude.stderr.log"
TALLY="$WORK/usage.json"
rm -f "$TALLY"

CLAUDE_BIN="${TUNICA_CLAUDE_BIN:-}"
[ -n "$CLAUDE_BIN" ] || CLAUDE_BIN="$(command -v claude || true)"
[ -n "$CLAUDE_BIN" ] || [ ! -x "$HOME/.local/bin/claude" ] || CLAUDE_BIN="$HOME/.local/bin/claude"
[ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ] \
  || die "claude CLI not found. Install it, or set TUNICA_CLAUDE_BIN in $SCRIPT_DIR/tunica.env"

GITREV="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "no-git")"
log INFO "TunICA $CODE_VERSION | repo $REPO_NAME @ $GITREV | depth $DEPTH | model $MODEL"
log INFO "out: $OUT_DIR"

# ---------------------------------------------------------------- ingestion
build_tree() {
  local -a skip=()
  local artefacts
  for artefacts in "$OUT_ROOT" "$OUT_DIR"; do
    case "$artefacts/" in "$REPO/"*) skip+=(-path "./${artefacts#"$REPO/"}" -prune -o) ;; esac
  done
  ( cd "$REPO" && find . "${skip[@]}" \
      \( -name .git -o -name node_modules -o -name vendor -o -name .next -o -name dist \
         -o -name build -o -name coverage -o -name __pycache__ -o -name .cache \
         -o -name .work -o -name temp -o -name .worktrees \) -type d -prune -o \
      -type f \
      ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' ! -name '*.gif' ! -name '*.ico' \
      ! -name '*.svg' ! -name '*.woff' ! -name '*.woff2' ! -name '*.ttf' ! -name '*.webp' \
      ! -name '*.pyc' ! -name '*.min.*' ! -name '*.map' ! -name '*.tar.gz' ! -name '*.log' \
      ! -name 'package-lock.json' ! -name 'yarn.lock' ! -name '*.lock' \
      -print | sed 's|^\./||' | sort ) | drop_ignored
}

drop_ignored() {
  TUNICA_REPO="$REPO" python3 "$SCRIPT_DIR/lib/gitignored.py"
}

TREE_FILE="$WORK/file-tree.txt"
build_tree > "$TREE_FILE"
NFILES=$(wc -l < "$TREE_FILE")
[ "$NFILES" -gt 0 ] || die "no analyzable files found in $REPO"
[ "$NFILES" -le "$MAX_FILES" ] || die "$NFILES files exceeds TUNICA_MAX_FILES ($MAX_FILES)"
log INFO "file tree: $NFILES files"

README_TEXT=""
for f in README.md README readme.md; do
  [ -f "$REPO/$f" ] && README_TEXT="$(head -c 50000 "$REPO/$f")" && break
done

# ---------------------------------------------------------------- model call
call_claude() {
  log INFO "claude call ($3)"
  local rc=0 envelope="${2%.response.txt}.envelope.json"
  timeout "$TIMEOUT" "$CLAUDE_BIN" -p \
    "The piped input is an instruction document. Follow it exactly and output ONLY what it demands, with no preamble and no code fences." \
    --model "$MODEL" --output-format json < "$1" > "$envelope" 2>>"$STDERR_LOG" || rc=$?
  [ "$rc" -eq 0 ] || die "claude call failed (rc=$rc, $3). See $STDERR_LOG"
  run_step python3 "$SCRIPT_DIR/lib/usage.py" record "$envelope" "$2" "$TALLY" "$3"
}

# ---------------------------------------------------------------- system map
SYSTEM_PROMPT="$WORK/system.prompt.txt"
{
  cat <<'EOP'
You are a principal software engineer mapping a repository's architecture.
Below are the repository's complete file tree and its README.

Return ONLY a JSON object (no markdown, no fences, no commentary) with EXACTLY this shape:
{
  "title": "short project title",
  "description": "2-3 sentence architecture summary",
  "groups": [ {"id": "snake_case_id", "label": "Short Group Label"} ],
  "components": [
    {
      "id": "snake_case_id",
      "label": "Short Human Label",
      "kind": "short type, e.g. CLI entry, config, CI workflow, docs",
      "description": "one sentence",
      "group": "id of the group this belongs to, or null",
      "files": ["exact/path/from/tree"],
      "calls": ["ids this component invokes, triggers, or sends data INTO"]
    }
  ]
}
Rules: 2-6 groups clustering related components; 6-16 components; every architecturally
relevant CODE file appears in exactly one component's "files" (copied EXACTLY from the
tree). "calls" is flow direction: entry points sit at the top and call downward, and
never point a callee back at its dispatcher. Do NOT create components for licenses, funding,
or pure documentation files. Only reference component ids that exist; invent nothing.
EOP
  printf '\n<file_tree>\n'; cat "$TREE_FILE"; printf '</file_tree>\n\n<readme>\n%s\n</readme>\n' "$README_TEXT"
} > "$SYSTEM_PROMPT"

SYSTEM_RESPONSE="$WORK/system.response.txt"
call_claude "$SYSTEM_PROMPT" "$SYSTEM_RESPONSE" "system map"

export TUNICA_META="TunICA $CODE_VERSION | backend: claude -p --model $MODEL (your subscription) | repo: $REPO_NAME @ $GITREV | $(date '+%Y-%m-%d %H:%M')"
GRAPH="$WORK/graph.json"
run_step python3 "$SCRIPT_DIR/lib/cover.py" "$REPO" "$OUT_DIR"
run_step python3 "$SCRIPT_DIR/lib/parse_system.py"   "$SYSTEM_RESPONSE" "$GRAPH" "$TREE_FILE"
run_step python3 "$SCRIPT_DIR/lib/compile_system.py" "$GRAPH" "$OUT_DIR" "$DEPTH"

# ---------------------------------------------------------------- component maps
if [ "$DEPTH" = 2 ]; then
  N=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["components"]))' "$GRAPH")
  i=0
  while [ "$i" -lt "$N" ]; do
    CID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["components"][int(sys.argv[2])]["id"])' "$GRAPH" "$i")
    PROMPT="$WORK/$CID.prompt.txt"
    STATUS=$(TUNICA_LIB="$SCRIPT_DIR/lib" python3 - "$GRAPH" "$i" "$REPO" "$PROMPT" <<'PYEOF'
import json, os, sys
sys.path.insert(0, os.environ["TUNICA_LIB"])
from doc_files import is_doc_only

g = json.load(open(sys.argv[1])); c = g["components"][int(sys.argv[2])]
repo, prompt_path = sys.argv[3], sys.argv[4]
max_file = int(os.environ.get("TUNICA_MAX_FILE_BYTES", 60000))
max_total = int(os.environ.get("TUNICA_MAX_COMPONENT_BYTES", 120000))
if not c["files"]:
    print("nofiles"); sys.exit()
if is_doc_only(c):
    print("docs"); sys.exit()
parts = [f'You are mapping the INTERNALS of one component of "{g.get("title", "")}".',
         f'Component: {c.get("label")}: {c.get("description", "")}',
         'Below are the full contents of its files.', '',
         'Return ONLY a JSON object (no markdown, no fences):',
         '{ "nodes": [ {"id": "snake_case", "label": "...", "kind": "function|section|config|flow", "description": "one sentence", "file": "path"} ],',
         '  "edges": [ {"from": "id", "to": "id", "label": "short verb phrase"} ] }',
         'Rules: 5-18 nodes covering every significant function/section; edges show real call/data flow; ids unique.',
         'Map ONLY what is actually present in the file contents below. If the component description',
         'mentions behaviour you cannot find in the content, ignore that part of the description.', '']
total = 0
for f in c["files"]:
    try:
        data = open(os.path.join(repo, f), encoding="utf-8", errors="replace").read()[:max_file]
    except OSError:
        continue
    if total + len(data) > max_total:
        break
    total += len(data)
    parts.append(f"<file path=\"{f}\">\n{data}\n</file>\n")
open(prompt_path, "w", encoding="utf-8").write("\n".join(parts))
print("ok")
PYEOF
)
    case "$STATUS" in
      ok)
        RESPONSE="$WORK/$CID.response.txt"
        call_claude "$PROMPT" "$RESPONSE" "component: $CID"
        run_step python3 "$SCRIPT_DIR/lib/compile_component.py" "$RESPONSE" "$OUT_DIR" "$CID"
        ;;
      docs)    log INFO "component: $CID is documentation, not mapped" ;;
      nofiles) log INFO "component: $CID has no files, skipped" ;;
    esac
    i=$((i + 1))
  done
fi

if [ -f "$OUT_DIR/overview.md" ]; then
  find "$OUT_DIR" -maxdepth 1 -name '*.md' ! -newermt "@$RUN_STARTED" -print -delete 2>/dev/null \
    | while IFS= read -r stale; do log INFO "swept stale map: $(basename "$stale")"; done
fi

run_step python3 "$SCRIPT_DIR/lib/usage.py" total "$TALLY"
log INFO "done -> $OUT_DIR/overview.md   (view it: tunica view $REPO_NAME)"
