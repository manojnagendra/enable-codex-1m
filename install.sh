#!/usr/bin/env bash
# enable-codex-1m — one-click 1M context window for OpenAI Codex
# Based on guidance from @thsottiaux (OpenAI Codex):
# https://x.com/thsottiaux/status/2089082893804896524
set -euo pipefail

VERSION="1.0.0"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_PATH="${CODEX_CONFIG:-$CODEX_HOME/config.toml}"
DEFAULT_MODEL="gpt-5.6-sol"
DEFAULT_WINDOW="1000000"
DEFAULT_COMPACT="900000"
PROFILE_NAME="1m"
INSTALL_DIR="${CODEX_1M_INSTALL_DIR:-$HOME/.local/bin}"

MODE="enable"          # enable | disable | status | run | uninstall
APPLY_MODEL=1
MODEL="$DEFAULT_MODEL"
WINDOW="$DEFAULT_WINDOW"
COMPACT="$DEFAULT_COMPACT"
USE_PROFILE=0
DRY_RUN=0
YES=0
SKIP_BIN=0

usage() {
  cat <<'EOF'
enable-codex-1m — one-click 1M context for OpenAI Codex

Usage:
  curl -fsSL <raw-install-url> | bash
  ./install.sh [command] [options]

Commands:
  enable      Write 1M settings (default)
  disable     Remove 1M settings / profile and restore from latest backup if needed
  status      Show current 1M-related config
  run         Launch a one-off Codex session with 1M overrides (no config edit)
  uninstall   Remove the installed codex-1m helper from PATH

Options:
  --model NAME          Model to set (default: gpt-5.6-sol)
  --keep-model          Do not change the model= line
  --window N            Context window tokens (default: 1000000)
  --compact N           Auto-compact token limit (default: 900000)
  --profile             Write ~/.codex/1m.config.toml instead of editing config.toml
  --profile-name NAME   Profile name when using --profile (default: 1m)
  --dry-run             Print the planned change without writing
  --yes, -y             Skip confirmation prompts
  --no-bin              Do not install the codex-1m helper
  -h, --help            Show help

Examples:
  ./install.sh
  ./install.sh --keep-model
  ./install.sh --profile
  ./install.sh run -- "refactor the auth module"
  ./install.sh status
  ./install.sh disable
EOF
}

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      enable|disable|status|run|uninstall)
        MODE="$1"
        shift
        ;;
      --model)
        MODEL="${2:?--model requires a value}"
        APPLY_MODEL=1
        shift 2
        ;;
      --keep-model)
        APPLY_MODEL=0
        shift
        ;;
      --window)
        WINDOW="${2:?--window requires a value}"
        shift 2
        ;;
      --compact)
        COMPACT="${2:?--compact requires a value}"
        shift 2
        ;;
      --profile)
        USE_PROFILE=1
        shift
        ;;
      --profile-name)
        PROFILE_NAME="${2:?--profile-name requires a value}"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --yes|-y)
        YES=1
        shift
        ;;
      --no-bin)
        SKIP_BIN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        break
        ;;
    esac
  done
  RUN_ARGS=("$@")
}

confirm() {
  [[ "$YES" -eq 1 ]] && return 0
  [[ ! -t 0 ]] && return 0  # non-interactive (curl | bash)
  local prompt="$1"
  local reply
  printf '%s [Y/n] ' "$prompt"
  read -r reply || true
  case "${reply:-Y}" in
    Y|y|yes|YES|"") return 0 ;;
    *) die "aborted" ;;
  esac
}

backup_config() {
  local src="$1"
  [[ -f "$src" ]] || return 0
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local dest="${src}.bak.${stamp}"
  cp "$src" "$dest"
  log "backup: $dest"
  printf '%s\n' "$dest"
}

# Upsert top-level TOML keys before the first [section] header.
# Usage: apply_toml_keys <file> key=value ...
apply_toml_keys() {
  local file="$1"
  shift
  require_cmd python3
  FILE="$file" DRY_RUN="$DRY_RUN" python3 - <<'PY'
import os, re, pathlib

path = pathlib.Path(os.environ["FILE"])
dry = os.environ.get("DRY_RUN") == "1"

pairs = []
for item in os.environ.get("CODEX_1M_PAIRS", "").split("\n"):
    item = item.strip()
    if not item or "=" not in item:
        continue
    k, v = item.split("=", 1)
    pairs.append((k.strip(), v.strip()))

text = path.read_text(encoding="utf-8") if path.exists() else ""
lines = text.splitlines(keepends=True)

# Split into preamble (before first [section]) and rest.
section_re = re.compile(r"^\s*\[")
pre_idx = len(lines)
for i, line in enumerate(lines):
    if section_re.match(line):
        pre_idx = i
        break
preamble = lines[:pre_idx]
rest = lines[pre_idx:]

key_re_cache = {}
def key_pattern(key):
    if key not in key_re_cache:
        key_re_cache[key] = re.compile(rf"^\s*{re.escape(key)}\s*=")
    return key_re_cache[key]

# Remove existing keys from preamble only (leave [section] tables untouched).
kept = []
for line in preamble:
    if any(key_pattern(k).match(line) for k, _ in pairs):
        continue
    kept.append(line)

# Drop leading/trailing blank lines in remaining preamble.
while kept and kept[0].strip() == "":
    kept.pop(0)
while kept and kept[-1].strip() == "":
    kept.pop()

block = []
for k, v in pairs:
    # Quote string values that aren't bare numbers/bools
    if re.fullmatch(r"-?\d+(\.\d+)?", v) or v in ("true", "false"):
        rendered = v
    else:
        # strip existing quotes if present
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            rendered = v if v.startswith('"') else f'"{v[1:-1]}"'
        else:
            rendered = f'"{v}"'
    block.append(f"{k} = {rendered}\n")

# Place 1M keys at the top of the file (matches official docs / tweet).
new_preamble = list(block)
if kept:
    new_preamble.append("\n")
    new_preamble.extend(kept)
    if not new_preamble[-1].endswith("\n"):
        new_preamble[-1] = new_preamble[-1] + "\n"
if rest:
    new_preamble.append("\n")

new_text = "".join(new_preamble + rest)
if not new_text.endswith("\n"):
    new_text += "\n"

if dry:
    print("--- planned config ---")
    print(new_text)
    print("--- end ---")
else:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new_text, encoding="utf-8")
PY
}

# Bash→Python bridge: export key pairs for the python helper.
export_pairs_and_apply() {
  local file="$1"
  shift
  local pairs=()
  local arg
  for arg in "$@"; do
    pairs+=("$arg")
  done
  local csv=""
  local p
  for p in "${pairs[@]}"; do
    csv+="${p}"$'\n'
  done
  CODEX_1M_PAIRS="$csv" apply_toml_keys "$file"
}

remove_toml_keys() {
  local file="$1"
  shift
  [[ -f "$file" ]] || return 0
  require_cmd python3
  CODEX_1M_REMOVE="$(printf '%s\n' "$@")" FILE="$file" DRY_RUN="$DRY_RUN" python3 - <<'PY'
import os, re, pathlib
path = pathlib.Path(os.environ["FILE"])
dry = os.environ.get("DRY_RUN") == "1"
keys = [k.strip() for k in os.environ.get("CODEX_1M_REMOVE", "").splitlines() if k.strip()]
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)
section_re = re.compile(r"^\s*\[")
pre_idx = len(lines)
for i, line in enumerate(lines):
    if section_re.match(line):
        pre_idx = i
        break
preamble, rest = lines[:pre_idx], lines[pre_idx:]
patterns = [re.compile(rf"^\s*{re.escape(k)}\s*=") for k in keys]
kept = [ln for ln in preamble if not any(p.match(ln) for p in patterns)]
while kept and kept[-1].strip() == "":
    kept.pop()
if kept and rest:
    kept.append("\n")
new_text = "".join(kept + rest)
if not new_text.endswith("\n"):
    new_text += "\n"
if dry:
    print("--- planned config ---")
    print(new_text)
    print("--- end ---")
else:
    path.write_text(new_text, encoding="utf-8")
PY
}

read_top_level_value() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  require_cmd python3
  FILE="$file" KEY="$key" python3 - <<'PY'
import os, re, pathlib
path = pathlib.Path(os.environ["FILE"])
key = os.environ["KEY"]
if not path.exists():
    raise SystemExit(0)
lines = path.read_text(encoding="utf-8").splitlines()
section_re = re.compile(r"^\s*\[")
pat = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(.*?)\s*$")
for line in lines:
    if section_re.match(line):
        break
    m = pat.match(line)
    if m:
        val = m.group(1).strip()
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        print(val)
        break
PY
}

status_cmd() {
  mkdir -p "$CODEX_HOME"
  echo "Codex home:  $CODEX_HOME"
  echo "Config:      $CONFIG_PATH"
  echo
  if [[ -f "$CONFIG_PATH" ]]; then
    local model window compact
    model="$(read_top_level_value "$CONFIG_PATH" model || true)"
    window="$(read_top_level_value "$CONFIG_PATH" model_context_window || true)"
    compact="$(read_top_level_value "$CONFIG_PATH" model_auto_compact_token_limit || true)"
    echo "config.toml"
    echo "  model                          = ${model:-<unset>}"
    echo "  model_context_window           = ${window:-<unset>}"
    echo "  model_auto_compact_token_limit = ${compact:-<unset>}"
  else
    echo "config.toml: missing"
  fi

  local profile_path="$CODEX_HOME/${PROFILE_NAME}.config.toml"
  echo
  if [[ -f "$profile_path" ]]; then
    echo "profile '${PROFILE_NAME}' ($profile_path)"
    echo "  model                          = $(read_top_level_value "$profile_path" model || true)"
    echo "  model_context_window           = $(read_top_level_value "$profile_path" model_context_window || true)"
    echo "  model_auto_compact_token_limit = $(read_top_level_value "$profile_path" model_auto_compact_token_limit || true)"
    echo "  launch with: codex --profile ${PROFILE_NAME}"
  else
    echo "profile '${PROFILE_NAME}': not installed"
  fi

  echo
  if [[ "${window:-}" == "$DEFAULT_WINDOW" || -f "$profile_path" ]]; then
    echo "1M context: configured (restart Codex / start a new session to apply)"
  else
    echo "1M context: not configured"
  fi
}

build_pair_list() {
  PAIRS=()
  if [[ "$APPLY_MODEL" -eq 1 ]]; then
    PAIRS+=("model=${MODEL}")
  fi
  PAIRS+=("model_context_window=${WINDOW}")
  PAIRS+=("model_auto_compact_token_limit=${COMPACT}")
}

enable_cmd() {
  require_cmd python3
  mkdir -p "$CODEX_HOME"
  build_pair_list

  if [[ "$USE_PROFILE" -eq 1 ]]; then
    local profile_path="$CODEX_HOME/${PROFILE_NAME}.config.toml"
    log "Writing profile: $profile_path"
    if [[ "$APPLY_MODEL" -eq 1 ]]; then
      echo "  model = \"${MODEL}\""
    else
      echo "  model = (unchanged)"
    fi
    echo "  model_context_window = ${WINDOW}"
    echo "  model_auto_compact_token_limit = ${COMPACT}"
    confirm "Create/update profile '${PROFILE_NAME}'?"
    if [[ "$DRY_RUN" -eq 0 && -f "$profile_path" ]]; then
      backup_config "$profile_path" >/dev/null
    fi
    export_pairs_and_apply "$profile_path" "${PAIRS[@]}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      log "Enabled. Launch with: codex --profile ${PROFILE_NAME}"
      log "Or one-off: codex -m ${MODEL} -c model_context_window=${WINDOW} -c model_auto_compact_token_limit=${COMPACT}"
    fi
  else
    log "Updating: $CONFIG_PATH"
    if [[ "$APPLY_MODEL" -eq 1 ]]; then
      echo "  model = \"${MODEL}\""
    else
      echo "  model = (unchanged)"
    fi
    echo "  model_context_window = ${WINDOW}"
    echo "  model_auto_compact_token_limit = ${COMPACT}"
    confirm "Apply 1M context settings to config.toml?"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      backup_config "$CONFIG_PATH" >/dev/null || true
    fi
    export_pairs_and_apply "$CONFIG_PATH" "${PAIRS[@]}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      log "Enabled. Restart Codex and start a new session."
      log "One-off alternative: codex -m ${MODEL} -c model_context_window=${WINDOW} -c model_auto_compact_token_limit=${COMPACT}"
    fi
  fi

  if [[ "$SKIP_BIN" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    install_helper
  fi
}

disable_cmd() {
  if [[ "$USE_PROFILE" -eq 1 ]]; then
    local profile_path="$CODEX_HOME/${PROFILE_NAME}.config.toml"
    if [[ -f "$profile_path" ]]; then
      confirm "Remove profile ${profile_path}?"
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log "would remove $profile_path"
      else
        backup_config "$profile_path" >/dev/null
        rm -f "$profile_path"
        log "Removed profile '${PROFILE_NAME}'"
      fi
    else
      log "Profile '${PROFILE_NAME}' not found"
    fi
    return 0
  fi

  [[ -f "$CONFIG_PATH" ]] || die "no config at $CONFIG_PATH"
  confirm "Remove 1M context keys from config.toml?"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    backup_config "$CONFIG_PATH" >/dev/null
  fi
  local keys=(model_context_window model_auto_compact_token_limit)
  # Only remove model if it matches our default 1M model and user didn't ask to keep it
  local current_model
  current_model="$(read_top_level_value "$CONFIG_PATH" model || true)"
  if [[ "$APPLY_MODEL" -eq 1 && "$current_model" == "$MODEL" ]]; then
    keys+=(model)
    warn "Also removing model=${MODEL}. Re-set your preferred model afterward if needed."
  fi
  remove_toml_keys "$CONFIG_PATH" "${keys[@]}"
  log "Disabled 1M overrides in config.toml"
}

run_cmd() {
  require_cmd codex
  local args=(-m "$MODEL" -c "model_context_window=${WINDOW}" -c "model_auto_compact_token_limit=${COMPACT}")
  if [[ ${#RUN_ARGS[@]} -gt 0 ]]; then
    exec codex "${args[@]}" "${RUN_ARGS[@]}"
  else
    exec codex "${args[@]}"
  fi
}

install_helper() {
  mkdir -p "$INSTALL_DIR"
  local dest="$INSTALL_DIR/codex-1m"
  local installed=0

  # Prefer copying this script when it lives on disk (clone / saved file).
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" && -r "${BASH_SOURCE[0]}" ]]; then
    cp "${BASH_SOURCE[0]}" "$dest"
    chmod +x "$dest"
    installed=1
  elif [[ -n "${CODEX_1M_INSTALL_URL:-}" ]]; then
    require_cmd curl
    curl -fsSL "$CODEX_1M_INSTALL_URL" -o "$dest"
    chmod +x "$dest"
    installed=1
  fi

  if [[ "$installed" -eq 0 ]]; then
    warn "Could not install codex-1m helper (script was piped without a file path)."
    warn "Re-run via: curl -fsSL <url> -o /tmp/codex-1m.sh && bash /tmp/codex-1m.sh"
    return 0
  fi

  log "Installed helper: $dest"
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      warn "$INSTALL_DIR is not on your PATH"
      warn "Add: export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
  log "Try: codex-1m status"
}

uninstall_cmd() {
  local dest="$INSTALL_DIR/codex-1m"
  if [[ -f "$dest" ]]; then
    rm -f "$dest"
    log "Removed $dest"
  else
    log "Helper not found at $dest"
  fi
}

main() {
  parse_args "$@"
  case "$MODE" in
    enable) enable_cmd ;;
    disable) disable_cmd ;;
    status) status_cmd ;;
    run) run_cmd ;;
    uninstall) uninstall_cmd ;;
    *) die "unknown command: $MODE" ;;
  esac
}

main "$@"
