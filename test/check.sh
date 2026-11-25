#!/usr/bin/env bash
# Usage: test/check.sh [NN]
#   With a step number, runs that step's check (test/steps/NN-*.sh).
#   Without one, runs every step's check in order and stops at the first that fails.
set -u
cd "$(dirname "$0")/steps" || exit 1

if [ $# -gt 0 ]; then
  case "$1" in
    '' | *[!0-9]*) echo "단계 번호는 숫자로 적습니다. 예: test/check.sh 01" >&2; exit 2 ;;
  esac
  n=$(printf '%02d' "$((10#$1))")
  set -- "$n"-*.sh
  if [ ! -e "$1" ]; then echo "${n}번 단계의 검사 스크립트가 아직 없습니다 (test/steps/$n-*.sh)" >&2; exit 2; fi
  exec bash "$1"
fi

for f in *.sh; do
  if ! bash "$f"; then
    printf '\n%s 단계에서 멈췄습니다.\n' "${f%.sh}"
    exit 1
  fi
done
printf '\n지금까지 있는 단계를 모두 통과했습니다.\n'
