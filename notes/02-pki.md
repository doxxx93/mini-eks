# 02. 테넌트 PKI 만들기

## 한 일

openssl로 `tenant-a`의 인증서 12개와 ServiceAccount 키 쌍을 만들었다. 파일 이름과 CN은 [Kubernetes PKI 문서](https://kubernetes.io/docs/setup/best-practices/certificates/)와 kubeadm의 배치를 따랐다. 개인 키가 들어 있는 `pki/tenant-a/`는 `.gitignore`로 커밋하지 않고, 인증서마다 붙일 용도와 SAN을 정의한 `manual/02-pki/openssl.cnf`만 커밋한다.

`openssl.cnf`에는 섹션이 네 개 있다.

- `[ ca ]`: `CA:TRUE`, `keyCertSign`. 다른 인증서를 서명할 수 있는 CA용.
- `[ client ]`: `extendedKeyUsage = clientAuth`. 접속하는 쪽이 내미는 인증서용.
- `[ etcd ]`: `serverAuth, clientAuth`와 etcd의 SAN(`localhost`, `127.0.0.1`, `etcd.tenant-a.svc`, `*.etcd.tenant-a.svc.cluster.local` 등). etcd는 서버이면서 다른 멤버에 접속하는 클라이언트이기도 해서 둘 다 넣었다.
- `[ apiserver ]`: `serverAuth`와 apiserver의 SAN.

인증서 하나는 세 단계로 만든다. 개인 키를 만들고(`genrsa`), 이름(subject)을 담은 서명 요청(CSR)을 만들고(`req`), CA가 용도를 붙여 서명한다(`x509 -req`). CA는 자기 자신이 서명하므로 `-signkey`를 쓰고, 나머지는 `-CA`와 `-CAkey`로 서명할 CA를 지정한다. 유효 기간은 kubeadm 기본값처럼 CA 10년, 나머지 1년으로 했다.

```console
$ cd pki/tenant-a && CNF=../../manual/02-pki/openssl.cnf
$ openssl genrsa -out ca.key 2048
$ openssl req -new -key ca.key -subj "/CN=kubernetes-ca" -out ca.csr
$ openssl x509 -req -in ca.csr -signkey ca.key -days 3650 -extfile $CNF -extensions ca -out ca.crt
Certificate request self-signature ok
subject=CN=kubernetes-ca

$ openssl genrsa -out apiserver.key 2048
$ openssl req -new -key apiserver.key -subj "/CN=kube-apiserver" -out apiserver.csr
$ openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -extfile $CNF -extensions apiserver -out apiserver.crt
Certificate request self-signature ok
subject=CN=kube-apiserver
```

나머지도 같은 패턴이고, 바뀌는 것은 파일 이름, `-subj`, 서명하는 CA, `-extensions` 네 가지뿐이다. ServiceAccount 키 쌍은 인증서가 아니라 키만 만든다.

```console
$ openssl genrsa -out sa.key 2048
$ openssl rsa -in sa.key -pubout -out sa.pub
writing RSA key
```

CA 인증서를 열어 보면 발급자(Issuer)와 주체(Subject)가 같다. 자기 자신이 서명했다는 뜻이다. `CA:TRUE`와 `Certificate Sign`은 이 인증서로 다른 인증서를 서명할 수 있다는 뜻이다.

```console
$ openssl x509 -in ca.crt -noout -text
        Issuer: CN=kubernetes-ca
        Validity
            Not Before: Nov 25 13:00:05 2026 GMT
            Not After : Nov 22 13:00:05 2036 GMT
        Subject: CN=kubernetes-ca
        X509v3 extensions:
            X509v3 Basic Constraints: critical
                CA:TRUE
            X509v3 Key Usage: critical
                Digital Signature, Certificate Sign, CRL Sign
```

apiserver 인증서에는 `openssl.cnf`에 적은 SAN이 그대로 들어갔다.

```console
$ openssl x509 -in pki/tenant-a/apiserver.crt -noout -text | grep -A1 'Alternative Name'
            X509v3 Subject Alternative Name:
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:kube-apiserver, DNS:kube-apiserver.tenant-a, DNS:kube-apiserver.tenant-a.svc, DNS:kube-apiserver.tenant-a.svc.cluster.local, DNS:localhost, DNS:mgmt-control-plane, IP Address:10.32.0.1, IP Address:127.0.0.1
```

etcd 인증서는 kubernetes-ca로 검증하면 실패하고, etcd-ca로 검증해야 통과한다.

```console
$ openssl verify -CAfile pki/tenant-a/ca.crt pki/tenant-a/etcd/server.crt
CN=kube-etcd
error 20 at 0 depth lookup: unable to get local issuer certificate
error pki/tenant-a/etcd/server.crt: verification failed

$ openssl verify -CAfile pki/tenant-a/etcd/ca.crt pki/tenant-a/etcd/server.crt
pki/tenant-a/etcd/server.crt: OK
```

확인:

```console
$ mise run check 02

== 02. 테넌트 PKI (/Users/doxxx/personal/mini-eks/pki/tenant-a)
  ✓ ca (CN=kubernetes-ca)
  ✓ etcd/ca (CN=etcd-ca)
  ✓ sa.key, sa.pub (ServiceAccount 토큰 서명 키 쌍)
  ✓ etcd/server (CN=kube-etcd)
  ✓ etcd/peer (CN=kube-etcd-peer)
  ✓ etcd/healthcheck-client (CN=kube-etcd-healthcheck-client)
  ✓ apiserver-etcd-client (CN=kube-apiserver-etcd-client)
  ✓ apiserver (CN=kube-apiserver)
  ✓ apiserver-kubelet-client (CN=kube-apiserver-kubelet-client,O=system:masters)
  ✓ admin (CN=kubernetes-admin,O=system:masters)
  ✓ controller-manager (CN=system:kube-controller-manager)
  ✓ scheduler (CN=system:kube-scheduler)

통과
```

## 왜 필요한가

쿠버네티스의 부품들은 서로 TLS로 통신하고, 인증서는 두 가지를 증명한다.

- 서버 인증서는 "내가 진짜 apiserver(또는 etcd)다"를 증명한다. 클라이언트가 접속한 주소가 인증서의 SAN에 없으면 TLS 검증이 실패한다. 그래서 apiserver 인증서에는 테넌트 안의 파드가 쓰는 `kubernetes.default.svc`와 `10.32.0.1`, 관리 클러스터 안에서 쓰는 `kube-apiserver.tenant-a.svc`, 바깥에서 쓰는 `127.0.0.1`을 모두 넣었다.
- 클라이언트 인증서는 "나는 누구다"를 증명한다. apiserver는 CN을 사용자 이름으로, O를 그룹으로 읽어 RBAC으로 권한을 판단한다. scheduler와 controller-manager는 필요한 권한이 다르므로 이름도 따로 있어야 한다.

연결마다 서버 쪽과 클라이언트 쪽이 있고 부품마다 이름이 달라야 하므로, 인증서가 여러 개 필요하다.

| 인증서 | 누가 누구에게 |
| --- | --- |
| `etcd/server`, `etcd/peer` | etcd가 클라이언트와 다른 멤버에게 (서버) |
| `etcd/healthcheck-client` | etcdctl과 헬스 체크가 etcd에 |
| `apiserver-etcd-client` | apiserver가 etcd에 |
| `apiserver` | apiserver가 모든 클라이언트에게 (서버) |
| `apiserver-kubelet-client` | apiserver가 kubelet에 (`kubectl logs`, `exec`) |
| `admin`, `controller-manager`, `scheduler` | 각자 apiserver에 |

etcd에 CA를 따로 두는 이유는 위의 `openssl verify` 결과와 같다. etcd는 자기가 믿는 CA가 서명한 클라이언트 인증서라면 누구든 받아들인다. 만약 etcd가 kubernetes-ca를 믿으면, admin이나 kubelet의 인증서로도 apiserver의 RBAC을 거치지 않고 etcd를 직접 읽고 쓸 수 있다. CA를 나누면 etcd에 접근할 수 있는 인증서를 etcd-ca가 서명한 것으로 제한할 수 있다.

admin에 `O=system:masters`를 쓴 이유는 갓 만든 테넌트에는 RBAC 바인딩이 하나도 없기 때문이다. `system:masters`는 RBAC을 건너뛰는 그룹이라 처음 접속할 수 있는 유일한 방법이다. kubeadm은 평소에 쓰는 `admin.conf`(`O=kubeadm:cluster-admins`)와 비상용 `super-admin.conf`(`O=system:masters`)를 나누는데, 여기서는 하나로 두었다.

`sa.key`와 `sa.pub`는 인증서가 아니라 ServiceAccount 토큰을 서명하고 검증하는 키 쌍이다. 관리 클러스터의 static pod 매니페스트를 보면 apiserver가 `sa.key`로 토큰을 서명하고 `sa.pub`로 검증하며, controller-manager도 `sa.key`를 받는다.

```console
$ docker exec mgmt-control-plane sh -c 'grep -H -E "service-account|sa\.(key|pub)" /etc/kubernetes/manifests/*.yaml'
/etc/kubernetes/manifests/kube-apiserver.yaml:    - --service-account-issuer=https://kubernetes.default.svc.cluster.local
/etc/kubernetes/manifests/kube-apiserver.yaml:    - --service-account-key-file=/etc/kubernetes/pki/sa.pub
/etc/kubernetes/manifests/kube-apiserver.yaml:    - --service-account-signing-key-file=/etc/kubernetes/pki/sa.key
/etc/kubernetes/manifests/kube-controller-manager.yaml:    - --service-account-private-key-file=/etc/kubernetes/pki/sa.key
/etc/kubernetes/manifests/kube-controller-manager.yaml:    - --use-service-account-credentials=true
```

## 실제 EKS·GKE에서는

- EKS: 컨트롤 플레인의 인증서는 AWS가 만들고 관리하며, 사용자가 받는 것은 클러스터 CA뿐이다. `aws eks update-kubeconfig`가 kubeconfig에 서버 주소와 CA(`certificate-authority-data`)를 채워 준다. 사용자 인증에는 클라이언트 인증서를 쓰지 않는다. kubeconfig의 exec 항목이 `aws eks get-token`을 실행해 IAM 자격 증명으로 서명한 토큰을 받고, 이 토큰은 15분 동안 유효하다. 클러스터 접근 권한은 access entry로 준다. ([Connect kubectl to an EKS cluster](https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html), [aws eks get-token](https://docs.aws.amazon.com/cli/latest/reference/eks/get-token.html), [EKS access control](https://docs.aws.amazon.com/eks/latest/userguide/cluster-auth.html))
- GKE: 클러스터마다 자기 root CA를 가져서, 한 클러스터의 CA가 노출되어도 다른 클러스터에는 영향이 없다. etcd에는 별도의 etcd API CA를 쓰고, 컨트롤 플레인 VM에서 etcd를 돌리는 클러스터는 etcd 멤버끼리 쓰는 etcd peer CA도 따로 둔다. 우리가 etcd CA를 나눈 것과 같은 구조다. credential rotation으로 cluster root CA, ServiceAccount 키, aggregation layer CA를 교체하며, CA 만료 30일 전부터는 GKE가 자동으로 교체를 시작한다. etcd 인증서의 교체는 사용자가 할 수 없고 GKE가 맡는다. ([Cluster trust](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-trust), [Rotate your cluster credentials](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/credential-rotation))

## 우리 환경과의 차이

- CA 개인 키가 노트북의 일반 파일(`pki/tenant-a/ca.key`)로 있다. 실제 서비스는 CA 키를 사용자가 볼 수 없는 곳에 두며, GKE는 원하면 Cloud KMS와 CA Service에 둘 수 있다.
- 인증서 교체 절차가 없다. 1년 뒤에 만료되면 손으로 다시 만들어야 한다. 실제 서비스는 만료 전에 자동으로 교체한다.
- admin이 `system:masters` 인증서 하나뿐이다. 이 인증서는 폐기할 방법이 없어서 유출되면 CA를 바꾸기 전까지 막을 수 없다. 사용자 인증은 20번에서 토큰 방식으로 바꾼다.
- front-proxy CA와 인증서는 만들지 않았다. aggregation layer(metrics-server 등)를 쓸 때 필요하다.
- kubelet 인증서도 만들지 않았다. 6번에서 bootstrap token으로 조인하면 kubelet이 CSR을 보내 인증서를 발급받는다.
- apiserver의 SAN이 고정되어 있다. 4번에서 노출하는 주소가 SAN에 없으면 apiserver 인증서를 다시 만들어야 한다.

## 막힌 것과 배운 것

- `vi manual/02-pki/openssl.cnf`로 내용을 다 쓰고 저장하려는데 `E212: Can't open file for writing`이 났다. `manual/02-pki` 디렉터리가 없어서다. vi를 닫지 않고 `:!mkdir -p %:h`로 디렉터리를 만든 뒤 `:w`로 저장했다. `%:h`는 편집 중인 파일의 디렉터리를 가리킨다.
- `-extensions`에 `openssl.cnf`에 없는 섹션 이름을 주면 `Error checking extension section scheduler`를 내며 서명이 실패한다. 섹션은 `ca`, `client`, `etcd`, `apiserver` 네 개뿐이고 scheduler는 `client`를 쓴다.
- macOS 기본 openssl은 LibreSSL 3.3.6이고 Homebrew의 openssl은 OpenSSL 4.1이다. 같은 명령으로 둘 다 인증서를 만들 수 있지만, 출력 형식이 조금 다르다. 개인 키 헤더가 LibreSSL은 `BEGIN RSA PRIVATE KEY`, OpenSSL은 `BEGIN PRIVATE KEY`다. 또 LibreSSL에는 `x509 -ext` 옵션이 없어서 `-text`로 확인해야 한다.
