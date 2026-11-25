#!/usr/bin/env bash
# Checks the host before step 01: a reachable Docker daemon and the tool versions mise.toml pins.
set -u
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

title "준비 상태"

if ! command -v mise >/dev/null 2>&1; then
  fail "mise가 없습니다" "https://mise.jdx.dev 에서 설치한 뒤 이 디렉터리에서 mise install을 실행하세요."
fi

if ! command -v docker >/dev/null 2>&1; then
  fail "docker 명령이 없습니다" "OrbStack이나 Docker Desktop 같은 Docker 런타임을 설치하세요."
elif docker info >/dev/null 2>&1; then
  pass "Docker 데몬에 연결됨 (context: $(docker context show 2>/dev/null))"
else
  fail "Docker 데몬에 연결할 수 없습니다" "Docker 런타임이 실행 중인지 확인하세요."
fi

# check_version TOOL ACTUAL: ACTUAL must start with the version mise.toml pins.
check_version() {
  want=$(pinned "$1")
  if [ -z "$2" ]; then
    fail "$1 명령이 없습니다" "이 디렉터리에서 mise install을 실행하세요."
    return
  fi
  case "$2." in
    "$want".*) pass "$1 $2 ($(command -v "$1"))" ;;
    *) fail "$1 버전이 다릅니다: $2 (mise.toml: $want, 경로: $(command -v "$1"))" \
      "mise가 PATH 앞에 오도록 mise activate를 설정하거나, mise run으로 실행하세요." ;;
  esac
}

kubectl_version=$(kubectl version --client -o json 2>/dev/null | json_field gitVersion)
check_version kubectl "${kubectl_version#v}"
check_version kind "$(kind version -q 2>/dev/null)"
check_version shellcheck "$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')"

finish
