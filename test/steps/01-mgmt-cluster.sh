#!/usr/bin/env bash
# Step 01: the kind management cluster exists, its apiserver answers, every node is Ready,
# and kubectl is within one minor version of the apiserver.
set -u
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

title "01. 관리 클러스터 ($MGMT_CLUSTER)"

if kind get clusters 2>/dev/null | grep -qx "$MGMT_CLUSTER"; then
  pass "kind 클러스터가 있음: $MGMT_CLUSTER"
else
  fail "kind 클러스터가 없음: $MGMT_CLUSTER" \
    "kind get clusters로 이름을 확인하세요. 다른 이름으로 만들었다면 MGMT_CLUSTER=<이름>을 붙여 실행합니다."
  finish
fi

if ! server=$(kubectl --context "$MGMT_CONTEXT" get --raw /version 2>/dev/null); then
  fail "$MGMT_CONTEXT context로 apiserver에 접속할 수 없습니다" \
    "kubectl config get-contexts에 ${MGMT_CONTEXT}가 있는지, 노드 컨테이너가 떠 있는지(docker ps) 확인하세요."
  finish
fi
pass "apiserver가 응답함 ($(printf '%s' "$server" | json_field gitVersion))"

nodes=$(kubectl --context "$MGMT_CONTEXT" get nodes \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}')
if [ -z "$nodes" ]; then
  fail "노드가 하나도 없습니다"
fi
while read -r name ready; do
  [ -z "$name" ] && continue
  if [ "$ready" = True ]; then
    pass "Ready 노드: $name"
  else
    fail "Ready가 아닌 노드: $name (Ready=$ready)" "kubectl --context $MGMT_CONTEXT describe node ${name}의 Conditions를 보세요."
  fi
done <<EOF
$nodes
EOF

# kubectl supports apiservers one minor version older or newer than itself.
server_minor=$(printf '%s' "$server" | json_field minor | tr -dc 0-9)
client_minor=$(kubectl version --client -o json 2>/dev/null | json_field minor | tr -dc 0-9)
skew=$((client_minor - server_minor))
if [ "$skew" -ge -1 ] && [ "$skew" -le 1 ]; then
  pass "버전 차이가 마이너 1 이내: kubectl 1.$client_minor, apiserver 1.$server_minor"
else
  fail "버전 차이가 마이너 1을 넘음: kubectl 1.$client_minor, apiserver 1.$server_minor ($(command -v kubectl))" \
    "mise가 고정한 kubectl이 잡히는지 mise run doctor로 확인하세요."
fi

finish
