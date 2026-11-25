#!/usr/bin/env bash
# Step 02: the tenant PKI exists under pki/$TENANT. Every certificate chains to the right CA,
# matches its private key, and carries the expected subject, extended key usage and SANs.
# Works with macOS's LibreSSL and with OpenSSL 3+.
set -u
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

PKI=${PKI_DIR:-$ROOT/pki/$TENANT}
title "02. 테넌트 PKI ($PKI)"

if ! command -v openssl >/dev/null 2>&1; then
  fail "openssl 명령이 없습니다"
  finish
fi

subject() { openssl x509 -in "$1" -noout -subject -nameopt RFC2253 | sed 's/^subject= *//'; }
key_matches() { [ "$(openssl x509 -in "$1" -noout -pubkey)" = "$(openssl pkey -in "$2" -pubout 2>/dev/null)" ]; }

# check_ca NAME CN
check_ca() {
  crt=$PKI/$1.crt key=$PKI/$1.key problems=''
  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
    fail "없음: $1.crt, $1.key"
    return
  fi
  [ "$(subject "$crt")" = "CN=$2" ] || problems="$problems subject가 $(subject "$crt");"
  openssl x509 -in "$crt" -noout -text | grep -q 'CA:TRUE' || problems="$problems CA:TRUE가 아님;"
  key_matches "$crt" "$key" || problems="$problems 키가 인증서와 맞지 않음;"
  if [ -z "$problems" ]; then pass "$1 (CN=$2)"; else fail "$1:$problems"; fi
}

# check_cert NAME CA SUBJECT USAGE [SAN...]
#   USAGE is server, client or both. SAN is "DNS:name" or "IP Address:1.2.3.4".
check_cert() {
  name=$1 ca=$2 want=$3 usage=$4
  shift 4
  crt=$PKI/$name.crt key=$PKI/$name.key problems=''
  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
    fail "없음: $name.crt, $name.key"
    return
  fi
  openssl verify -CAfile "$PKI/$ca.crt" "$crt" >/dev/null 2>&1 || problems="$problems $ca.crt로 검증되지 않음;"
  got=$(subject "$crt")
  [ "$got" = "$want" ] || problems="$problems subject가 $got;"
  text=$(openssl x509 -in "$crt" -noout -text)
  case $usage in
    server | both) printf '%s' "$text" | grep -q 'TLS Web Server Authentication' || problems="$problems serverAuth 없음;" ;;
  esac
  case $usage in
    client | both) printf '%s' "$text" | grep -q 'TLS Web Client Authentication' || problems="$problems clientAuth 없음;" ;;
  esac
  sans=$(printf '%s\n' "$text" | grep -A1 'Subject Alternative Name' | tail -n 1 | tr ',' '\n' | sed 's/^ *//')
  for san in "$@"; do
    printf '%s\n' "$sans" | grep -qxF "$san" || problems="$problems SAN에 $san 없음;"
  done
  key_matches "$crt" "$key" || problems="$problems 키가 인증서와 맞지 않음;"
  if [ -z "$problems" ]; then pass "$name ($want)"; else fail "$name:$problems"; fi
}

check_ca ca kubernetes-ca
check_ca etcd/ca etcd-ca

if [ -f "$PKI/sa.key" ] && [ -f "$PKI/sa.pub" ]; then
  if [ "$(openssl pkey -in "$PKI/sa.key" -pubout 2>/dev/null)" = "$(cat "$PKI/sa.pub")" ]; then
    pass "sa.key, sa.pub (ServiceAccount 토큰 서명 키 쌍)"
  else
    fail "sa.pub가 sa.key의 공개 키가 아닙니다"
  fi
else
  fail "없음: sa.key, sa.pub"
fi

etcd_sans=("DNS:localhost" "IP Address:127.0.0.1" "DNS:etcd.$TENANT.svc" "DNS:*.etcd.$TENANT.svc.cluster.local")
check_cert etcd/server etcd/ca "CN=kube-etcd" both "${etcd_sans[@]}"
check_cert etcd/peer etcd/ca "CN=kube-etcd-peer" both "${etcd_sans[@]}"
check_cert etcd/healthcheck-client etcd/ca "CN=kube-etcd-healthcheck-client" client
check_cert apiserver-etcd-client etcd/ca "CN=kube-apiserver-etcd-client" client

check_cert apiserver ca "CN=kube-apiserver" server \
  "DNS:kubernetes" "DNS:kubernetes.default" "DNS:kubernetes.default.svc" "DNS:kubernetes.default.svc.cluster.local" \
  "DNS:kube-apiserver.$TENANT.svc" "DNS:localhost" "IP Address:127.0.0.1" "IP Address:10.32.0.1"
check_cert apiserver-kubelet-client ca "CN=kube-apiserver-kubelet-client,O=system:masters" client
check_cert admin ca "CN=kubernetes-admin,O=system:masters" client
check_cert controller-manager ca "CN=system:kube-controller-manager" client
check_cert scheduler ca "CN=system:kube-scheduler" client

finish
