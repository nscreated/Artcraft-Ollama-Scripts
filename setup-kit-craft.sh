#!/usr/bin/env bash
#
# setup-kit-craft.sh
#
# 1. Installs Kit if it is missing.
# 2. Detects which Craft apps have a real (on-PATH, non-AppImage) *-cli installed.
# 3. For each detected app, writes a Kit config that uses Ollama + Qwen with only
#    the `ls` and `find` core tools, plus a launcher script (kit-<app>).
#    It also writes a combined ~/.kit.yml containing every detected app.
#
# The script asks for the Ollama PC's address (port 11434 is assumed) and the
# model name (the "ollama/" prefix is added for you). To skip the prompts, set
# OLLAMA_URL and/or MODEL in the environment, e.g.:
#   OLLAMA_URL=http://192.168.1.10:11434 MODEL=ollama/qwen3.6:35b-a3b ./setup-kit-craft.sh
#
# kit-<app> launchers
#   kit-<app> starts the app window with a fixed control port (unless something is
#   already listening on that port), waits for the port to open, then runs Kit with
#   the app's MCP server attached to it. If the app can't be started, or does not
#   open its port within 30 s, it falls back to the headless "<app>-cli mcp".
#   The ports below are hardcoded here and ignore each app's own default.
#
#   app           port   app started with        MCP server attaches with
#   photocraft    7980   --control 7980 (+token  --bridge 127.0.0.1:7980 (+token file)
#                         file and roots)
#   vectorcraft   7981   --control 7981          --connect 127.0.0.1:7981
#   filmcraft     7982   --control 7982          --bridge  127.0.0.1:7982
#   lightcraft    7983   --control 7983          --connect 127.0.0.1:7983
#   effectcraft   7984   --control 7984          --bridge  127.0.0.1:7984
#   designcraft   7985   --control 7985          --connect 127.0.0.1:7985
#   figcraft      7986   --control 7986          --connect 127.0.0.1:7986
#   texturecraft  7987   --control 7987          --connect 127.0.0.1:7987
#   materialcraft 7988   --control 7988          --connect 127.0.0.1:7988
#   wordcraft     7989   --control 7989          --connect 127.0.0.1:7989
#   soundcraft    7990   --control 7990          --connect 127.0.0.1:7990
#   deckcraft     7991   --control 7991          --connect 127.0.0.1:7991
#   cadcraft      7992   --control 7992          --connect 127.0.0.1:7992
#   gridcraft     7993   --control 7993          --connect 127.0.0.1:7993
#   pdfcraft, craft-anything: headless only ("<app>-cli mcp"); no window is started.
#
#   Environment variables for a launcher:
#     KIT_MCP_MODE=headless   never start the app; use headless mode
#     KIT_APP_ARGS="file"     extra arguments for the app (e.g. a file to open)
#   The app's output goes to ~/.config/kit-apps/<app>-app.log.
#   Plain "kit" (combined ~/.kit.yml) always uses headless "<app>-cli mcp".
#
# Apart from PhotoCraft's roots, no folder restrictions are passed, so the MCP
# servers are NOT confined to any folder. The script still creates these folders:
#   ~/Documents/Artcraft-In and ~/Documents/Artcraft-Out
# Override with READ_ROOT / WRITE_ROOT if needed.
#
# PATH: the kit-<app> launchers are saved in ~/.local/bin. If that folder is not on
# your PATH, the script offers to add it to your shell startup files (.bashrc,
# .zshrc, .profile, and fish if present). The launchers also remember Kit's full
# path, so they work even when PATH is not set up (e.g. in PRoot/containers).
#
# Options:
#   --no-path       do not offer to edit shell startup files
#   --no-combined   do not write/replace ~/.kit.yml
#   --dry-run       show what would be detected and written, change nothing

set -u

ORIG_PATH="$PATH"      # the PATH your shell had; this script adds to its own copy later

OLLAMA_URL="${OLLAMA_URL:-}"      # asked interactively if empty
MODEL="${MODEL:-}"                # asked interactively if empty
DEFAULT_HOST="192.168.1.10"
DEFAULT_MODEL="qwen3.6:35b-a3b"
OLLAMA_PORT=11434
READ_ROOT="${READ_ROOT:-$HOME/Documents/Artcraft-In}"
WRITE_ROOT="${WRITE_ROOT:-$HOME/Documents/Artcraft-Out}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/kit-apps}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
KIT_INSTALL_URL="https://raw.githubusercontent.com/mark3labs/kit/master/install.sh"

WRITE_COMBINED=1
UPDATE_PATH=1
KIT_BIN=""
PATH_MARK="# added by setup-kit-craft.sh"
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --no-combined) WRITE_COMBINED=0 ;;
    --no-path) UPDATE_PATH=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,/^set -u/{/^set -u/!p}' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# App names from https://getartcraft.com/apps. The CLI is assumed to be <name>-cli.
# Only photocraft-cli is confirmed by its docs; the others follow the same pattern.
APPS=(
  photocraft vectorcraft filmcraft lightcraft pdfcraft effectcraft designcraft
  figcraft texturecraft materialcraft wordcraft soundcraft deckcraft cadcraft
  gridcraft craft-anything
)

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# ---------------------------------------------------------------- 1. Kit ----

add_common_paths() {
  for d in "$HOME/.local/bin" "$HOME/go/bin" "$HOME/.kit/bin" "/usr/local/bin"; do
    case ":$PATH:" in *":$d:"*) ;; *) [ -d "$d" ] && PATH="$d:$PATH" ;; esac
  done
  export PATH
}

ensure_kit() {
  add_common_paths
  if command -v kit >/dev/null 2>&1; then
    say "[ok] Kit found: $(command -v kit)"
    return 0
  fi

  say "[..] Kit not found."
  if [ "$DRY_RUN" -eq 1 ]; then
    say "     (dry run) would run: curl -fsSL $KIT_INSTALL_URL | bash"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl is required to install Kit."
    return 1
  fi

  say "[..] Installing Kit..."
  curl -fsSL "$KIT_INSTALL_URL" | bash || { warn "Kit install script failed."; return 1; }

  add_common_paths
  hash -r
  if command -v kit >/dev/null 2>&1; then
    say "[ok] Kit installed: $(command -v kit)"
  else
    warn "Kit installed but 'kit' is not on PATH yet. Open a new shell or add its install directory to PATH, then re-run this script."
    return 1
  fi
}

# ------------------------------------------------------- 2. Detect CLIs ----

cli_candidates() {
  case "$1" in
    craft-anything) echo "craft-anything-cli craftanything-cli" ;;
    *)              echo "$1-cli" ;;
  esac
}

# Prints the command name if a working, installed (non-AppImage) CLI exists.
find_cli() {
  local app="$1" name path real
  for name in $(cli_candidates "$app"); do
    path="$(type -P "$name" 2>/dev/null)" || continue
    [ -n "$path" ] || continue
    real="$(readlink -f "$path" 2>/dev/null || echo "$path")"
    case "$real" in
      *.AppImage|*.appimage|*/squashfs-root/*|/tmp/.mount_*) continue ;;
    esac
    if timeout 10 "$name" --help >/dev/null 2>&1 || timeout 10 "$name" --version >/dev/null 2>&1; then
      echo "$name"
      return 0
    fi
  done
  return 1
}

# -------------------------------------------------------- 3. Write config ---

# Hardcoded control port per app (7980 upward). Empty = headless only.
app_port() {
  case "$1" in
    photocraft)    echo 7980 ;;
    vectorcraft)   echo 7981 ;;
    filmcraft)     echo 7982 ;;
    lightcraft)    echo 7983 ;;
    effectcraft)   echo 7984 ;;
    designcraft)   echo 7985 ;;
    figcraft)      echo 7986 ;;
    texturecraft)  echo 7987 ;;
    materialcraft) echo 7988 ;;
    wordcraft)     echo 7989 ;;
    soundcraft)    echo 7990 ;;
    deckcraft)     echo 7991 ;;
    cadcraft)      echo 7992 ;;
    gridcraft)     echo 7993 ;;
    *)             echo "" ;;     # pdfcraft, craft-anything
  esac
}

# How the MCP server attaches to the running app: the documented flag, or "" for headless only.
app_flag() {
  case "$1" in
    pdfcraft|craft-anything)       echo "" ;;
    photocraft|filmcraft|effectcraft) echo "--bridge" ;;
    *)                             echo "--connect" ;;
  esac
}

# server_block <app> <cli> [flag address [token-file]]
server_block() {
  cat <<EOF
  $1:
    type: local
    command:
      - "$2"
      - mcp
EOF
  if [ -n "${3:-}" ]; then
    cat <<EOF
      - $3
      - "$4"
EOF
  fi
  if [ -n "${5:-}" ]; then
    cat <<EOF
      - --control-token-file
      - "$5"
EOF
  fi
}

header_block() {
  cat <<EOF
# Generated by setup-kit-craft.sh
model: $MODEL
provider-url: $OLLAMA_URL
include-core-tools:
  - ls
  - find
thinking-level: off
max-tokens: 4096
stream: true

mcpServers:
EOF
}

write_app_config() {  # $1=app  $2=cli
  local app="$1" cli="$2"
  local port flag addr token="" app_args_line
  local headless="$CONFIG_DIR/$app.yml" live="$CONFIG_DIR/$app-live.yml"
  local log_file="$CONFIG_DIR/$app-app.log" launcher="$BIN_DIR/kit-$app"
  port="$(app_port "$app")"
  flag="$(app_flag "$app")"

  { header_block; server_block "$app" "$cli"; } > "$headless"
  say "     config:   $headless  ($cli mcp)"
  rm -f "$CONFIG_DIR/$app-connect.yml"          # name used by earlier versions

  if [ -n "$port" ] && [ -n "$flag" ]; then
    addr="127.0.0.1:$port"
    app_args_line="app_args=(--control $port)"
    if [ "$app" = photocraft ]; then
      # PhotoCraft's control channel needs a token file, and the app (not the MCP
      # bridge) is where its folder roots are configured.
      token="$CONFIG_DIR/photocraft-control.token"
      app_args_line="app_args=(--control $port --control-token-file \"$token\" --automation-read-root \"$READ_ROOT\" --automation-write-root \"$WRITE_ROOT\")"
    fi
    { header_block; server_block "$app" "$cli" "$flag" "$addr" "$token"; } > "$live"
    say "     config:   $live  ($cli mcp $flag $addr${token:+ --control-token-file ...})"
    say "     app:      $app --control $port"
  else
    port=""
    app_args_line="app_args=()"
    rm -f "$live"
    say "     (headless only; no window is started for $app)"
  fi

  {
    cat <<EOF
#!/usr/bin/env bash
# Launches Kit with the $app MCP server (generated by setup-kit-craft.sh)
# See setup-kit-craft.sh for what each mode does.
app="$app"
port="$port"
headless_cfg="$headless"
live_cfg="$live"
log_file="$log_file"
ollama_url="$OLLAMA_URL"
kit_bin="$KIT_BIN"
$app_args_line
EOF
    cat <<'EOF'

# Find Kit even when PATH is not set up (e.g. PRoot): use the path recorded at
# setup time, else search PATH. Put its folder first on PATH for the app and MCP servers.
[ -x "$kit_bin" ] || kit_bin="$(command -v kit 2>/dev/null)"
if [ -z "$kit_bin" ]; then
  echo "kit-$app: Kit was not found. Re-run setup-kit-craft.sh." >&2
  exit 127
fi
PATH="$(dirname "$kit_bin"):$HOME/.local/bin:/usr/local/bin:$PATH"
export PATH

listening() { (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; }

cfg="$headless_cfg"
if [ "${KIT_MCP_MODE:-auto}" != headless ] && [ -n "$port" ]; then
  if ! listening; then
    if command -v "$app" >/dev/null 2>&1; then
      echo "kit-$app: starting $app with --control $port ..." >&2
      mkdir -p "$(dirname "$log_file")"
      # KIT_APP_ARGS is word-split on purpose (e.g. KIT_APP_ARGS="$HOME/book.xlsx").
      # shellcheck disable=SC2086
      nohup "$app" "${app_args[@]}" ${KIT_APP_ARGS:-} >"$log_file" 2>&1 </dev/null &
      disown 2>/dev/null
      for _ in $(seq 1 60); do listening && break; sleep 0.5; done
    else
      echo "kit-$app: '$app' was not found on PATH, so its window can't be started." >&2
    fi
  fi
  if listening; then
    cfg="$live_cfg"
  else
    echo "kit-$app: nothing is listening on 127.0.0.1:$port; using headless mode." >&2
    [ -f "$log_file" ] && echo "          See $log_file for the app's output." >&2
  fi
fi
exec "$kit_bin" --config "$cfg" --provider-url "$ollama_url" "$@"
EOF
  } > "$launcher"
  chmod +x "$launcher"
  say "     launcher: $launcher"
}

write_combined_config() {  # args: "app:cli" pairs
  local target="$HOME/.kit.yml" tmp pair
  tmp="$(mktemp)"
  header_block > "$tmp"
  for pair in "$@"; do
    server_block "${pair%%:*}" "${pair#*:}" >> "$tmp"
  done

  if [ -f "$target" ] && ! cmp -s "$tmp" "$target"; then
    local bak="$target.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$bak"
    say "[ok] Backed up existing ~/.kit.yml to $bak"
  fi
  mv "$tmp" "$target"
  say "[ok] Wrote combined config: $target"
}

# ---------------------------------------------------------------- prompts ----

# Reads a line from the terminal with a default. Falls back to the default when
# there is no terminal (e.g. the script is piped or run from cron).
ask() {  # $1=prompt  $2=default
  local reply=""
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    { read -r -p "$1 [$2]: " reply < /dev/tty > /dev/tty 2>&1; } 2>/dev/null || reply=""
  fi
  printf '%s' "${reply:-$2}"
}

# Turns "192.168.1.10", "http://host", "host:8080/" etc. into http://host:port.
normalize_url() {
  local in="$1"
  in="${in#http://}"; in="${in#https://}"
  in="${in%%/*}"
  case "$in" in
    *:*) ;;                       # user supplied a port; keep it
    *)   in="$in:$OLLAMA_PORT" ;;
  esac
  printf 'http://%s' "$in"
}

prompt_settings() {
  if [ -z "$OLLAMA_URL" ]; then
    local host
    host="$(ask "Ollama PC address (IP or hostname, port $OLLAMA_PORT assumed)" "$DEFAULT_HOST")"
    OLLAMA_URL="$(normalize_url "$host")"
  else
    OLLAMA_URL="$(normalize_url "$OLLAMA_URL")"
  fi

  if [ -z "$MODEL" ]; then
    local name
    name="$(ask "Model name (after ollama/)" "$DEFAULT_MODEL")"
    name="${name#ollama/}"
    MODEL="ollama/$name"
  else
    case "$MODEL" in ollama/*) ;; *) MODEL="ollama/$MODEL" ;; esac
  fi

  say ""
  say "Using Ollama at: $OLLAMA_URL"
  say "Using model:     $MODEL"
  say "Working folders: $READ_ROOT"
  say "                 $WRITE_ROOT   (created for convenience; not enforced by the MCP servers)"
}

# -------------------------------------------------------- PATH persistence ----

ensure_path_persistent() {
  case ":$ORIG_PATH:" in
    *":$BIN_DIR:"*) say "[ok] $BIN_DIR is already on your PATH."; return 0 ;;
  esac
  say ""
  say "$BIN_DIR is not on your PATH, so kit-<app> can't be run by name yet."
  if [ "$UPDATE_PATH" -eq 0 ]; then
    say "(skipped: --no-path) Run the launchers by full path, e.g. $BIN_DIR/kit-<app>"
    return 0
  fi
  case "$(ask "Add it to your shell startup files?" "y")" in
    y|Y|yes|YES) ;;
    *) say "Skipped. Run the launchers by full path, e.g. $BIN_DIR/kit-<app>"; return 0 ;;
  esac

  local rc found_any=0
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$rc" ] || continue
    found_any=1
    if grep -qF "$PATH_MARK" "$rc" 2>/dev/null; then continue; fi
    printf '\n%s\nexport PATH="%s:$PATH"\n' "$PATH_MARK" "$BIN_DIR" >> "$rc"
    say "  [updated] $rc"
  done
  if [ "$found_any" -eq 0 ]; then
    printf '%s\nexport PATH="%s:$PATH"\n' "$PATH_MARK" "$BIN_DIR" >> "$HOME/.profile"
    say "  [created] $HOME/.profile"
  fi
  if command -v fish >/dev/null 2>&1 || [ -d "$HOME/.config/fish" ]; then
    mkdir -p "$HOME/.config/fish/conf.d"
    printf '%s\nfish_add_path -g "%s"\n' "$PATH_MARK" "$BIN_DIR" > "$HOME/.config/fish/conf.d/kit-craft.fish"
    say "  [updated] $HOME/.config/fish/conf.d/kit-craft.fish"
  fi
  say "  Open a new shell for this to take effect, or run:  export PATH=\"$BIN_DIR:\$PATH\""
}

# ------------------------------------------------------------------ main ----

ensure_kit || say "[!!] Continuing without a working Kit install."
KIT_BIN="$(command -v kit 2>/dev/null || true)"

say ""
say "Checking for installed Craft app CLIs..."
FOUND=()
MISSING=()
for app in "${APPS[@]}"; do
  if cli="$(find_cli "$app")"; then
    FOUND+=("$app:$cli")
    say "  [yes] $app  ($cli)"
  else
    MISSING+=("$app")
    say "  [no]  $app"
  fi
done

if [ "${#FOUND[@]}" -eq 0 ]; then
  say ""
  say "No installed Craft app CLIs were found on PATH. Nothing to configure."
  exit 0
fi

say ""
prompt_settings

if [ "$DRY_RUN" -eq 1 ]; then
  say ""
  say "(dry run) would configure: ${FOUND[*]}"
  exit 0
fi

mkdir -p "$CONFIG_DIR" "$BIN_DIR" "$READ_ROOT" "$WRITE_ROOT"

say ""
say "Writing Kit configs (model: $MODEL, core tools: ls, find)..."
for pair in "${FOUND[@]}"; do
  say "  ${pair%%:*}"
  write_app_config "${pair%%:*}" "${pair#*:}"
done

if [ "$WRITE_COMBINED" -eq 1 ]; then
  say ""
  write_combined_config "${FOUND[@]}"
fi

say ""
say "Done."
say "  Single app:   kit-<app>      (e.g. kit-${FOUND[0]%%:*}; starts the app window on its own control port, falls back to headless)"
[ "$WRITE_COMBINED" -eq 1 ] && say "  All apps:     kit            (uses ~/.kit.yml)"
ensure_path_persistent
