#!/usr/bin/env bash
# tools/godot.sh: the only way to run Godot in this repo (BRIEF 2 and 7). Git Bash on Windows, bash on Linux.
#
#   tools/godot.sh [wrapper flags] <godot args> [-- <user args>]
#
# Wrapper flags (consumed here, never passed to Godot; only before a literal --):
#   --lease=<n>          take n of the machine's Godot slots at once (default 1)
#   --lock-timeout=<s>   give up waiting for the slots after s seconds (default 2700): exit 75
#   --timeout=<s>        kill the whole Godot process tree after s seconds (default 1200): exit 124
#   --allow-hw           drop the hardware lock for this run (humans following docs/HARDWARE_TEST_PLAN.md only)
#   --allow-network      drop the network lock for this run (same)
#
# What it does:
#   - exports WATTLANDS_NO_HW_CONTROL=1 and WATTLANDS_NO_NETWORK_INTEGRATIONS=1 (unless dropped above);
#   - refuses -d and --debug (an automated run would hang at the debugger prompt);
#   - resolves the binary: $GODOT, tools/godot_bin.local in this checkout, the same file in the main
#     checkout (so git worktrees work), then godot or godot4 on PATH;
#   - points Godot's user dir at $WATTLANDS_USERDATA_DIR, else <checkout>/.userdata (APPDATA on Windows,
#     XDG_DATA_HOME on Linux), except for export runs, which need the installed export templates;
#   - runs Godot through tools/lib/godot_lock.mjs: machine-wide slot lock, stdin closed, run timeout.
#   Everything from the first -- on is passed to Godot untouched.
set -u

die() {
  local code=$1
  shift
  printf 'godot.sh: %s\n' "$*" >&2
  exit "$code"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checkout="$(dirname "$script_dir")"
lock_js="$script_dir/lib/godot_lock.mjs"

is_windows=0
case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*) is_windows=1 ;;
esac

# ------------------------------------------------------------------ arguments
allow_hw=0
allow_net=0
lock_opts=()
godot_args=()
user_args=()
seen_sep=0
for arg in "$@"; do
  if [ "$seen_sep" = 1 ]; then
    user_args+=("$arg")
    continue
  fi
  case "$arg" in
    --)
      seen_sep=1
      user_args+=("$arg")
      ;;
    --allow-hw) allow_hw=1 ;;
    --allow-network) allow_net=1 ;;
    --lease=* | --lock-timeout=* | --timeout=*) lock_opts+=("$arg") ;;
    --lease | --lock-timeout | --timeout) die 2 "$arg needs a value: $arg=<n>" ;;
    -d | --debug) die 2 "refusing to pass $arg to Godot: automated runs never start the debugger (BRIEF 7)" ;;
    *) godot_args+=("$arg") ;;
  esac
done

# ------------------------------------------------------------------ binary
trim() {
  local s="$1"
  s="${s%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

bin_from_file() {
  local file="$1" line=""
  [ -f "$file" ] || return 1
  IFS= read -r line <"$file" || true
  line="$(trim "$line")"
  [ -n "$line" ] || return 1
  if [ ! -e "$line" ]; then
    printf 'godot.sh: %s names %s, which does not exist; trying the next candidate\n' "$file" "$line" >&2
    return 1
  fi
  printf '%s' "$line"
}

main_checkout() {
  command -v git >/dev/null 2>&1 || return 1
  local common=""
  common="$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
  if [ -z "$common" ]; then
    common="$(git -C "$checkout" rev-parse --git-common-dir 2>/dev/null)" || return 1
    case "$common" in
      /* | [A-Za-z]:*) ;;
      *) common="$checkout/$common" ;;
    esac
  fi
  [ -n "$common" ] || return 1
  dirname "$common"
}

resolve_godot() {
  if [ -n "${GODOT:-}" ]; then
    printf '%s' "$GODOT"
    return 0
  fi
  bin_from_file "$checkout/tools/godot_bin.local" && return 0
  local main=""
  main="$(main_checkout)" || main=""
  if [ -n "$main" ]; then
    bin_from_file "$main/tools/godot_bin.local" && return 0
  fi
  local candidate
  for candidate in godot godot4; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

godot_bin="$(resolve_godot)" ||
  die 127 "no Godot binary: set GODOT, or put its path in tools/godot_bin.local (one line), or put godot on PATH"

# ------------------------------------------------------------------ locks
if [ "$allow_hw" = 1 ]; then
  unset WATTLANDS_NO_HW_CONTROL
  printf 'godot.sh: hardware lock dropped for this run (--allow-hw)\n' >&2
else
  export WATTLANDS_NO_HW_CONTROL=1
fi
if [ "$allow_net" = 1 ]; then
  unset WATTLANDS_NO_NETWORK_INTEGRATIONS
  printf 'godot.sh: network lock dropped for this run (--allow-network)\n' >&2
else
  export WATTLANDS_NO_NETWORK_INTEGRATIONS=1
fi

# ------------------------------------------------------------------ user dir per checkout
is_export=0
project_path=""
i=0
n=${#godot_args[@]}
while [ "$i" -lt "$n" ]; do
  a="${godot_args[$i]}"
  case "$a" in
    --export-release | --export-debug | --export-pack | --export-patch) is_export=1 ;;
    --path) project_path="${godot_args[$((i + 1))]:-}" ;;
    --path=*) project_path="${a#--path=}" ;;
  esac
  i=$((i + 1))
done

checkout_root() {
  if [ -n "$project_path" ]; then
    (cd "$project_path" 2>/dev/null && pwd) && return 0
    return 1
  fi
  if command -v git >/dev/null 2>&1; then
    git rev-parse --show-toplevel 2>/dev/null && return 0
  fi
  pwd
}

if [ "$is_export" = 0 ]; then
  root="$(checkout_root)" || root=""
  if [ -n "$root" ] && [ -d "$root" ]; then
    userdata="${WATTLANDS_USERDATA_DIR:-$root/.userdata}"
    case "$userdata" in
      /* | [A-Za-z]:*) ;;
      *) userdata="$PWD/$userdata" ;; # Godot changes directory to --path; this must not follow it
    esac
    mkdir -p "$userdata" 2>/dev/null || true
    if [ "$is_windows" = 1 ]; then
      if command -v cygpath >/dev/null 2>&1; then
        userdata="$(cygpath -m "$userdata")"
      fi
      export APPDATA="$userdata"
    else
      export XDG_DATA_HOME="$userdata"
    fi
  fi
fi

# ------------------------------------------------------------------ run under the lock
command -v node >/dev/null 2>&1 || die 127 "node not found on PATH (Node 22.12+ runs the Godot lock)"

exec node "$lock_js" run ${lock_opts[@]+"${lock_opts[@]}"} -- "$godot_bin" \
  ${godot_args[@]+"${godot_args[@]}"} ${user_args[@]+"${user_args[@]}"} </dev/null
