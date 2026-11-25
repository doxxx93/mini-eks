# 02. 테넌트 PKI

`openssl.cnf`는 인증서마다 붙일 용도(서버, 클라이언트, CA)와 SAN을 정의합니다. 인증서를 만드는 명령과 각 인증서가 필요한 이유는 [`notes/02-pki.md`](../../notes/02-pki.md)에 있습니다.

## 생성되는 파일

명령을 모두 실행하면 저장소 루트의 `pki/tenant-a/`에 아래 파일이 생깁니다. 개인 키가 들어 있으므로 `pki/`는 `.gitignore`로 커밋하지 않습니다.

```
pki/tenant-a/
├── ca.crt, ca.key                              kubernetes-ca
├── sa.key, sa.pub                              ServiceAccount 토큰 서명 키 쌍 (인증서 아님)
├── apiserver.crt, apiserver.key                kube-apiserver (서버)
├── apiserver-kubelet-client.crt, .key          apiserver → kubelet
├── apiserver-etcd-client.crt, .key             apiserver → etcd (etcd-ca가 서명)
├── admin.crt, admin.key                        kubectl → apiserver
├── controller-manager.crt, .key                controller-manager → apiserver
├── scheduler.crt, scheduler.key                scheduler → apiserver
└── etcd/
    ├── ca.crt, ca.key                          etcd-ca
    ├── server.crt, server.key                  etcd (서버)
    ├── peer.crt, peer.key                      etcd 멤버끼리
    └── healthcheck-client.crt, .key            etcdctl, 헬스 체크 → etcd
```

이 밖에 두 종류의 파일이 함께 생깁니다. 이후 단계에서는 쓰지 않으므로 지워도 됩니다.

- `*.csr`: 인증서마다 만든 서명 요청입니다.
- `ca.srl`, `etcd/ca.srl`: `-CAcreateserial`이 만드는 파일로, CA가 다음에 발급할 일련번호를 기록합니다.

## 확인

```sh
mise run check 02
```

빠진 파일이 있으면 `없음: etcd/server.crt, etcd/server.key`처럼 알려 줍니다.
