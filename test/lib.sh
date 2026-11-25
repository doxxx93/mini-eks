# shellcheck shell=bash
# Shared helpers for the check scripts. Source this file; don't run it.
# Scripts must run on macOS's bash 3.2: no associative arrays, mapfile or ${var,,}.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

if [ -t 1 ]; then
  GREEN=$'\033[32m' RED=$'\033[31m' DIM=$'\033[2m' RESET=$'\033[0m'
else
  GREEN='' RED='' DIM='' RESET=''
fi

title() { printf '\n== %s\n' "$*"; }

pass() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }

# fail "what is wrong" ["where to look"]
fail() {
  failures=$((failures + 1))
  printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"
  if [ $# -gt 1 ]; then printf '    %s→ %s%s\n' "$DIM" "$2" "$RESET"; fi
}

# Exit with the result so far. Call it at the end, or early when later checks can't run.
finish() {
  if [ "$failures" -eq 0 ]; then
    printf '\n%s통과%s\n' "$GREEN" "$RESET"
    exit 0
  fi
  printf '\n%s실패 %d건%s\n' "$RED" "$failures" "$RESET"
  exit 1
}

# pinned TOOL: the version mise.toml pins for TOOL (e.g. "1.37").
pinned() { sed -n "s/^$1 = \"\(.*\)\"/\1/p" "$ROOT/mise.toml"; }

# Prints the JSON string value of KEY from stdin, e.g. json_field minor < version.json.
json_field() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" | head -n 1; }

# Read by the scripts that source this file.
export MGMT_CLUSTER=${MGMT_CLUSTER:-mgmt}
export MGMT_CONTEXT=kind-$MGMT_CLUSTER
