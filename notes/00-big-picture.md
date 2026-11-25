# 00. 큰 그림

## EKS 사용자는 무엇을 요청하고 무엇을 받는가

사용자는 클러스터를 만들어 달라고 요청하고, AWS는 kubeconfig를 준다. 사용자는 그 kubeconfig로 일반 클러스터처럼 쓰기만 하고, 그 뒤에서 AWS가 네 가지 일을 대신 한다.

1. 컨트롤 플레인(etcd, kube-apiserver, controller-manager, scheduler)을 띄우고 운영한다.
2. 워커 노드를 만들어 클러스터에 조인시킨다.
3. LB, 디스크 같은 인프라를 클러스터에 연결한다.
4. 업그레이드, 백업, 장애 복구를 처리한다.

managed와 hosted는 서로 다른 축이다. managed(관리형)는 누가 운영하느냐에 관한 말이고, hosted control plane은 컨트롤 플레인을 다른 클러스터 안의 파드로 띄우는 구조를 가리킨다. EKS는 managed이지만 hosted 구조는 아니고, 이 프로젝트는 hosted 구조로 만드는 managed 서비스다.

Fargate는 2번, 즉 파드를 어디서 돌리느냐에 관한 선택지 중 하나다. EKS에서는 self-managed nodes, managed node group, EKS Auto Mode, Fargate, Hybrid Nodes 중에서 고르거나 섞어 쓸 수 있다. Fargate를 쓰면 사용자는 노드를 관리하지 않고, 파드마다 커널, CPU, 메모리, ENI를 다른 파드와 공유하지 않는 별도 경계에서 돈다.

## 관리 클러스터와 테넌트 클러스터

관리 클러스터는 운영자인 우리가 쓰는 kind 클러스터이고, 사용자에게는 보이지 않는다. 테넌트 클러스터는 사용자가 kubeconfig로 받는 클러스터다. 관리 클러스터에 `ManagedCluster` 리소스를 만들면, 관리 클러스터 안에서 도는 컨트롤러가 테넌트 클러스터를 하나 만든다.

- 테넌트의 컨트롤 플레인은 관리 클러스터의 네임스페이스(예: `tenant-a`) 안에서 파드로 돈다.
- 테넌트의 워커 노드는 관리 클러스터 바깥에 있다. 처음에는 Docker 컨테이너이고 Phase 5부터는 VM이며, 노드의 kubelet이 테넌트의 apiserver에 조인한다.
- 사용자는 테넌트의 apiserver만 본다. 컨트롤 플레인이 노드로 떠 있지 않으므로 `kubectl get nodes`에도 워커 노드만 나온다.

Gardener의 seed와 shoot가 같은 관계다. seed 클러스터가 여러 shoot 클러스터의 컨트롤 플레인을 띄우고, 사용자가 받는 shoot 클러스터에는 워커 노드만 있다.

"쿠버네티스를 만드는 쿠버네티스"에는 두 갈래가 있다. Cluster API는 관리 클러스터가 VM을 만들고 그 VM 위에 컨트롤 플레인을 올린다. HyperShift, Kamaji, Gardener와 이 프로젝트는 컨트롤 플레인을 관리 클러스터 안의 파드로 띄운다. OpenStack은 쿠버네티스가 아니라 VM을 만드는 클라우드 플랫폼이고, 그 위의 Magnum이 Nova VM으로 클러스터를 만든다. 그래서 구조는 오히려 VM을 쓰는 EKS에 가깝다.

## 컨트롤 플레인을 파드로 띄우는 이유와 그 대가

EKS는 클러스터마다 전용 컨트롤 플레인을 두고, 다른 클러스터나 다른 AWS 계정과 겹치지 않게 한다. API 서버 최소 2개와 etcd 3개를 AZ 3곳에 나눠 두고, EKS가 관리하는 VPC 안에서 돌린다. API 서버 노드는 auto scaling group에 속하고, 앞에서 NLB가 요청을 나눈다. 이렇게 하는 이유는 고객끼리 같은 호스트를 공유하지 않게 하고, 한 클러스터의 장애가 다른 클러스터로 번지지 않게 하기 위해서다.

이 프로젝트가 파드로 띄우는 이유는 두 가지다.

- 자원: EKS처럼 하면 클러스터 하나에 VM이 5대 필요해서, 노트북 한 대로는 여러 클러스터를 돌릴 수 없다. 파드로 띄우면 여러 테넌트가 관리 클러스터 하나를 함께 쓴다.
- 운영: 재시작, 롤링 업데이트, 스케줄링을 관리 클러스터의 쿠버네티스가 대신 처리한다.

그 대가로 관리 클러스터에 문제가 생기면 모든 테넌트가 함께 영향을 받는다. 또 여러 테넌트의 컨트롤 플레인이 같은 노드와 커널을 공유하므로 EKS보다 격리가 약하다. EKS 방식은 27번에서 선택적으로 시도한다.

## kind 환경에서 흉내만 내는 것과 똑같이 만드는 것

어느 환경에서든 똑같이 만들어야 하는 핵심 로직은 컨트롤 플레인 호스팅, 인증서(PKI), 노드 조인, 업그레이드, 백업과 복구다.

환경 때문에 흉내만 내는 것은 다음과 같다.

- 워커 노드: EC2 대신 Docker 컨테이너라서 커널을 호스트와 공유한다. Phase 5에서 KubeVirt VM으로 바꾼다.
- 인프라: LoadBalancer와 디스크가 없다. Phase 5에서 KubeVirt CCM과 CSI를 연결하면 생긴다.
- 인증: 노드는 IAM 대신 bootstrap token과 인증서로 조인한다. 사용자 인증은 20번에서 작은 IAM 서비스를 만들어 흉내 낸다.
- 가용성: AZ 3곳 대신 노트북 한 대다. 16번에서 노드에 zone 라벨을 붙여 AZ를 흉내 낸다.
- 테넌트 격리: 클러스터와 VPC 단위가 아니라 네임스페이스 단위다.

Phase 5로 가도 노드와 인프라에 관한 차이만 줄어들고, 컨트롤 플레인의 위치와 가용성, 인증과 격리에 관한 차이는 그대로 남는다.

## 아직 모르는 것

- AWS는 EKS 컨트롤 플레인 노드들을 내부에서 무엇으로 관리할까? 공개 문서에는 나오지 않는다.
- AWS가 노드 10만 개짜리 ultra scale 클러스터를 설명한 글에 따르면, EKS는 etcd의 Raft 합의를 AWS 내부 컴포넌트인 journal로 넘기고, etcd의 저장소(BoltDB)를 EBS 대신 메모리(tmpfs)에 둔다. 그러면 etcd 멤버끼리 합의하지 않아도 쓰기 순서와 내구성은 무엇이 보장할까? 3번 etcd 단계에서 다시 본다.
- Fargate처럼 사용자에게 노드를 보여 주지 않는 방식을 이 프로젝트에서 만든다면 어떤 구조가 될까? 17번과 Phase 5의 노드 단계에서 비교해 본다.

## 참고

- [EKS architecture](https://docs.aws.amazon.com/eks/latest/userguide/eks-architecture.html)
- [EKS best practices: Control plane](https://docs.aws.amazon.com/eks/latest/best-practices/control-plane.html)
- [EKS compute 선택지](https://docs.aws.amazon.com/eks/latest/userguide/eks-compute.html)
- [EKS Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
- [Under the hood: Amazon EKS ultra scale clusters](https://aws.amazon.com/blogs/containers/under-the-hood-amazon-eks-ultra-scale-clusters/)
- [Cluster API concepts](https://cluster-api.sigs.k8s.io/user/concepts)
- [Gardener architecture](https://gardener.cloud/docs/gardener/concepts/architecture/)
- [HyperShift](https://hypershift-docs.netlify.app/)
- [OpenStack Magnum user guide](https://docs.openstack.org/magnum/latest/user/index.html)
