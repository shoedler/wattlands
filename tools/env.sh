# tools/env.sh: the hardware and network locks for this shell (BRIEF 1).
#
#   . tools/env.sh        (source it; running it as a script changes nothing in your shell)
#
# It sets exactly these two variables and leaves every other variable alone,
# including the art pipeline's, which only Simon sets (BRIEF 3.10).
export WATTLANDS_NO_HW_CONTROL=1
export WATTLANDS_NO_NETWORK_INTEGRATIONS=1
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE:-}" = "$0" ]; then
  printf '%s\n' 'tools/env.sh: source this file (. tools/env.sh); running it does not change your shell' >&2
fi
