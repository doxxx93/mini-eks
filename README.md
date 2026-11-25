# mini-eks

EKS, GKE 같은 관리형 쿠버네티스 서비스를 직접 만들어 보면서 배우는 프로젝트입니다. 같은 컨트롤러를 Go와 Rust로 각각 구현하고, 단계마다 배운 것을 `notes/`에 글로 남깁니다. 진행 상황은 `STEPS.md` 한 곳에서만 관리합니다.

## 무엇을 만드는가

EKS에서 사용자는 클러스터를 만들어 달라고 요청하고 kubeconfig를 받습니다. 그 뒤에서 AWS는 네 가지 일을 합니다.

1. 컨트롤 플레인(etcd, kube-apiserver, controller-manager, scheduler)을 띄우고 운영합니다.
2. 워커 노드를 만들어 클러스터에 조인시킵니다.
3. 로드밸런서와 디스크 같은 인프라를 클러스터에 연결합니다.
4. 업그레이드, 백업, 장애 복구를 처리합니다.

이 프로젝트는 이 네 가지 일을 하는 프로그램을 만듭니다. 목표는 EKS가 사용자에게 주는 기능을 똑같이 제공하는 것이고, EKS의 내부 구조를 그대로 따라 하는 것은 아닙니다. 가장 큰 차이는 컨트롤 플레인을 띄우는 방식입니다. EKS는 클러스터마다 별도의 인스턴스에 컨트롤 플레인을 두지만, 이 프로젝트는 노트북 한 대에서 여러 클러스터를 돌리기 위해 컨트롤 플레인을 관리 클러스터의 파드로 띄웁니다(HyperShift, Kamaji와 같은 방식). 구조를 한 문장으로 말하면 "쿠버네티스 클러스터를 만드는 쿠버네티스 클러스터"입니다. 관리 클러스터에 `ManagedCluster` 리소스를 하나 만들면, 관리 클러스터 안에서 도는 컨트롤러가 테넌트 클러스터를 하나 만들어 줍니다.

```
사용자 ── kubectl apply (ManagedCluster) ──▶ 관리 클러스터
                                             ├─ 우리가 만드는 컨트롤러 (Go 또는 Rust)
                                             └─ ns/tenant-a
                                                ├─ etcd, kube-apiserver, controller-manager, scheduler (파드)
                                                └─ konnectivity-server

워커 노드 (처음엔 Docker 컨테이너, 나중엔 VM)
  └─ kubelet이 tenant-a의 apiserver에 조인

사용자 ── tenant-a용 kubeconfig ──▶ 테넌트 클러스터를 일반 클러스터처럼 사용
```

### 컨트롤 플레인을 띄우는 방식

| 방식 | 컨트롤 플레인이 도는 곳 | 사용자에게 보이는가 |
| --- | --- | --- |
| kubeadm 같은 직접 구축 | 클러스터 안의 컨트롤 플레인 노드(VM)에서 static pod로 실행 | `kubectl get nodes`에 control-plane 노드로 보임 |
| EKS | 클러스터마다 전용 인스턴스, EKS가 관리하는 VPC 안 | 보이지 않음 |
| 이 프로젝트 (HyperShift, Kamaji와 같은 방식) | 관리 클러스터 안의 일반 Deployment와 StatefulSet | 보이지 않음 |

EKS가 클러스터마다 전용 인스턴스를 쓰는 이유는 고객끼리 컨트롤 플레인이 같은 호스트를 공유하지 않게 하고, 한 클러스터의 장애가 다른 클러스터로 번지지 않게 하기 위해서입니다. 이 프로젝트가 파드를 쓰는 이유는 자원입니다. EKS처럼 API 서버 2개와 etcd 3개를 VM으로 띄우면 클러스터 하나에 VM이 5대 필요합니다. 파드로 띄우면 여러 클러스터가 관리 클러스터 하나를 함께 쓰고, 재시작과 롤링 업데이트도 쿠버네티스가 대신 처리합니다. 대신 관리 클러스터에 문제가 생기면 모든 테넌트가 함께 영향을 받습니다. EKS 방식은 Phase 5의 27번에서 선택적으로 시도해 봅니다.

## 학습 환경과 실제 서비스의 차이

관리형 쿠버네티스의 핵심 로직(컨트롤 플레인 호스팅, 인증서, 노드 조인, 업그레이드, 복구)은 어느 환경에서든 똑같이 만들어야 합니다. 환경에 따라 달라지는 것은 "노드가 무엇이냐"와 "인프라를 누가 제공하느냐"입니다.

| 항목 | Phase 1~4: kind | Phase 5: Lima + KubeVirt | 실제 EKS |
| --- | --- | --- | --- |
| 관리 클러스터 | kind (OrbStack 위의 컨테이너) | Lima VM 안의 kubeadm 클러스터 | AWS 내부 시스템 (공개되지 않음) |
| 테넌트 컨트롤 플레인 | 관리 클러스터의 파드 | 같음 | 클러스터마다 별도 컨트롤 플레인 (EKS가 관리하는 VPC) |
| 컨트롤 플레인 가용성 | 노트북 한 대 | 같음 | API 서버 2개 이상과 etcd 3개를 AZ 3곳에 분산 |
| 인프라와 관리 시스템 | 같은 Docker 위에서 함께 동작 | KubeVirt가 관리 클러스터 안에서 동작 | EC2, VPC, ELB, EBS가 각각 별도 서비스 |
| 노드와 사용자 인증 | bootstrap token과 인증서 | 같음 | IAM |
| 테넌트 격리 | 네임스페이스 | 네임스페이스와 네트워크 정책 | 클러스터 단위로 분리, VPC로 트래픽 제한 |
| 워커 노드 | Docker 컨테이너 (커널 공유) | KubeVirt VM (자체 커널) | 고객 계정의 EC2 |
| 노드 부팅과 조인 | 컨테이너 안에서 kubeadm join | cloud-init이 kubelet을 설치하고 조인 | 부트스트랩 스크립트와 IAM 인증 |
| apiserver에서 노드로 가는 경로 | 같은 Docker 네트워크면 그냥 닿음, 분리하면 konnectivity 필요 | 같은 파드 네트워크면 그냥 닿음, 격리하면 konnectivity 필요 | 고객 VPC에 ENI를 연결해 직접 닿게 함 |
| LoadBalancer | 없음 | KubeVirt CCM과 MetalLB | ELB |
| 디스크 | 노드 컨테이너의 로컬 디렉터리 | KubeVirt CSI (VM에 디스크 핫플러그) | EBS CSI |
| 자원과 속도 | 몇 GB, 노드가 몇 초 만에 뜸 | 12~16GB, 노드 부팅에 수십 초 이상 | 해당 없음 |

Lima 단계로 가도 노드와 인프라에 관한 차이만 줄어들고, 컨트롤 플레인의 위치와 가용성, 인프라 분리, 인증과 격리에 관한 차이는 그대로 남습니다. 그래서 노트의 "실제 EKS·GKE에서는"과 "우리 환경과의 차이" 칸은 Phase 5까지 계속 씁니다. EKS 수치의 출처는 [EKS architecture](https://docs.aws.amazon.com/eks/latest/userguide/eks-architecture.html)와 [EKS best practices의 control plane 절](https://docs.aws.amazon.com/eks/latest/best-practices/control-plane.html)입니다.

## 환경을 이렇게 정한 이유

### Phase 1~4는 kind, Phase 5부터 Lima와 KubeVirt

핵심 로직은 어느 환경에서든 같기 때문에, 가볍고 빨리 다시 만들 수 있는 kind에서 먼저 만듭니다. Phase 5는 처음부터 다시 만드는 단계가 아닙니다. 그때까지 만든 CRD와 컨트롤러는 그대로 두고, NodePool 컨트롤러에 노드를 KubeVirt VM으로 만드는 드라이버를 하나 추가합니다. 그 뒤에도 kind 환경은 남겨 두고, 평소 개발과 테스트는 kind에서 하다가 진짜 VM과 LB, 디스크가 필요한 확인만 Lima에서 합니다.

Lima가 필요한 이유는 KubeVirt가 `/dev/kvm`을 요구하기 때문입니다. Lima의 `nestedVirtualization`은 `vmType: vz`에서 Apple M3 이후 칩과 macOS 15 이후에서만 지원되므로, M1과 M2 Mac에서는 Phase 5를 진행할 수 없습니다. OrbStack의 Docker VM에는 `/dev/kvm`이 없습니다.

### OrbStack 내장 Kubernetes 대신 kind

kind도 OrbStack의 Docker 위에서 돌기 때문에 OrbStack은 그대로 씁니다. OrbStack에 내장된 Kubernetes 기능만 쓰지 않습니다. 이유는 네 가지입니다.

- 버전 선택: kind는 `kindest/node:v1.xx` 이미지 태그로 Kubernetes 버전을 고를 수 있습니다. OrbStack 2.2.5의 설정에는 `k8s.enable`, `k8s.expose_services`, `k8s.kubeconfig_use_domain`, `k8s.tls_san`만 있고 버전을 정하는 항목이 없어서, 18번 업그레이드 실험처럼 버전을 맞춰야 하는 단계에서 불편합니다.
- 클러스터 개수: kind는 실험마다 클러스터를 몇 초 만에 만들고 지울 수 있고, 여러 개를 동시에 띄울 수도 있습니다. OrbStack은 클러스터를 하나만 제공합니다.
- 네트워크 제어: kind의 노드는 `kind`라는 Docker 네트워크에 붙은 컨테이너입니다. 그래서 워커 컨테이너를 같은 네트워크에 붙이거나 일부러 다른 네트워크로 떼어 내는 일을 `docker network` 명령으로 직접 할 수 있습니다. 8번 단계가 이것을 전제로 하고, Cluster API의 Docker provider(CAPD)도 같은 방식으로 동작합니다.
- 재현성: kind 설정은 YAML 파일 하나라서 저장소에 함께 남길 수 있고, 같은 설정으로 GitHub Actions에서 10번 검증 스크립트를 돌릴 수 있습니다. OrbStack은 macOS 앱의 설정이라 그렇게 할 수 없습니다.

OrbStack 내장 Kubernetes를 관리 클러스터로 쓰는 것도 가능하지만, 위의 네 가지를 포기해야 합니다.

## 진행 방식

단계마다 아래 순서를 따릅니다.

1. 손으로 해 보거나 구현합니다.
2. 실제 EKS와 GKE가 같은 문제를 어떻게 푸는지 찾아봅니다.
3. `notes/TEMPLATE.md` 형식으로 `notes/`에 글을 남깁니다.

Go와 Rust 구현은 같은 CRD를 쓰고, 언어와 무관한 같은 검증 스크립트를 통과해야 합니다. Go로 먼저 만들고 Rust가 뒤따라갑니다.

## 따라 하기

처음 따라 하는 사람도 단계마다 결과를 스스로 확인할 수 있도록 검사 스크립트를 둡니다. 필요한 것은 Docker 런타임(OrbStack, Docker Desktop 등)과 [mise](https://mise.jdx.dev)입니다.

```sh
mise trust && mise install   # mise.toml에 고정한 kubectl, kind, shellcheck 설치
mise run doctor              # Docker 연결과 도구 버전 확인
mise run check 01            # 01번 단계의 확인 항목 검사
mise run check               # 처음부터 차례로 검사해서 어디까지 왔는지 확인
```

검사 스크립트는 단계를 대신 해 주지 않고 결과만 확인합니다. 실패하면 무엇이 틀렸고 어디를 보면 되는지 알려 줍니다. 관리 클러스터 이름은 `mgmt`로 가정하며, 다른 이름을 썼다면 `MGMT_CLUSTER=<이름> mise run check 01`처럼 실행합니다. Phase 1의 명령은 직접 입력해 보는 것이 목적이므로 task로 감싸 두지 않습니다.

## Phase 4 구현 방향

Phase 4의 기능도 Phase 2와 같은 기술(컨트롤러와 API 서버)로 구현합니다.

- 16번 고가용성: kind 관리 클러스터를 노드 3개로 만들고, 노드마다 zone 라벨을 붙여 AZ를 흉내 냅니다. etcd는 3개짜리 StatefulSet으로 zone마다 하나씩 배치하고, apiserver는 2개짜리 Deployment 앞에 Service를 둡니다. EKS에서는 이 역할을 NLB가 맡습니다. controller-manager와 scheduler도 2개씩 띄우되, leader election으로 하나만 실제로 동작하게 합니다.
- 19번 애드온 관리: `ManagedCluster`의 spec에 애드온 이름과 버전 목록을 두고, 컨트롤러가 테넌트 클러스터에 server-side apply로 적용합니다. 버전을 바꾸면 컨트롤러가 다시 적용합니다. 사용자가 고친 값과 충돌할 때의 처리 방식은 EKS add-on의 `OVERWRITE`, `PRESERVE` 옵션과 비교해 봅니다.
- 20번 인증과 접근 권한: EKS에서는 `aws eks get-token`이 IAM 자격 증명으로 토큰을 만들고, apiserver가 webhook(aws-iam-authenticator)을 호출해 토큰을 검증합니다. 이 프로젝트에서는 사용자와 키를 관리하는 작은 IAM 서비스를 만들고, 테넌트 apiserver에 webhook 토큰 인증을 연결합니다. `AccessEntry` 리소스를 만들면 컨트롤러가 테넌트 안에 RBAC 바인딩을 만듭니다.
- 21번 생성 API와 CLI: 관리 영역에 `POST /clusters` 같은 API 서버를 두고, 이 서버가 CR을 대신 만들어서 사용자가 관리 클러스터를 직접 보지 않게 합니다. CLI의 `update-kubeconfig`는 kubeconfig에 exec 플러그인으로 `get-token`을 호출하도록 적습니다. `aws eks update-kubeconfig`와 같은 방식이라 20번과 이어집니다.

## 디렉터리와 브랜치

브랜치는 `main` 하나만 두고, 단계와 언어는 디렉터리로 나눕니다. Go와 Rust는 같은 CRD와 검증 스크립트를 공유하면서 나란히 비교해야 하므로 브랜치로 나누면 맞지 않습니다.

```
STEPS.md, README.md
notes/NN-*.md        단계마다 남기는 글
manual/NN-slug/      Phase 1에서 손으로 적용한 매니페스트와 명령 (그 단계에서 추가한 것만)
api/                 Go와 Rust가 함께 쓰는 CRD YAML
test/                언어와 무관한 검증 스크립트 (test/steps/NN-*.sh가 단계별 확인 항목)
go/                  Go 구현 (단계마다 계속 발전)
rust/                Rust 구현 (단계마다 계속 발전)
```

Phase 1은 단계마다 디렉터리를 따로 둡니다. 다만 앞 단계에서 만든 클러스터 상태를 그대로 이어서 쓰기 때문에, 디렉터리에는 그 단계에서 추가한 것만 넣습니다. Phase 2부터는 `go/`와 `rust/`의 코드가 계속 발전하므로 단계마다 복사본을 만들지 않고, 단계를 마칠 때마다 `step-NN` 태그를 붙여서 그 시점의 코드로 돌아갈 수 있게 합니다. 브랜치는 한 단계를 진행하는 동안만 쓰는 작업 공간으로 두고, 끝나면 `main`에 합칩니다.
