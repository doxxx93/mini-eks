# 01. 관리 클러스터 만들기

## 한 일

kind 설정 파일 `manual/01-mgmt-cluster/kind.yaml`로 관리 클러스터 `mgmt`를 만들었다.

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: mgmt
nodes:
  - role: control-plane
```

```console
$ kind create cluster --config manual/01-mgmt-cluster/kind.yaml
Creating cluster "mgmt" ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-mgmt"
You can now use your cluster with:

kubectl cluster-info --context kind-mgmt

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
```

kind가 내 kubeconfig에 `kind-mgmt` context를 추가하고 현재 context로 바꿨다.

```console
$ kubectl config get-contexts
CURRENT   NAME        CLUSTER     AUTHINFO    NAMESPACE
*         kind-mgmt   kind-mgmt   kind-mgmt
          orbstack    orbstack    orbstack
```

노드는 `mgmt-control-plane`이라는 Docker 컨테이너 하나다. 호스트의 `127.0.0.1:50201`이 컨테이너 안의 6443 포트(apiserver)로 연결된다.

```console
$ docker ps
CONTAINER ID   IMAGE                  COMMAND                  CREATED          STATUS          PORTS                       NAMES
400a64e3ae37   kindest/node:v1.37.0   "/usr/local/bin/entr…"   53 seconds ago   Up 52 seconds   127.0.0.1:50201->6443/tcp   mgmt-control-plane
```

관리 클러스터 자신의 컨트롤 플레인(etcd, kube-apiserver, kube-controller-manager, kube-scheduler)도 `kube-system`의 파드로 보인다. 이 네 파드는 이름 끝에 노드 이름 `-mgmt-control-plane`이 붙어 있다.

```console
$ kubectl get pods -n kube-system
NAME                                         READY   STATUS    RESTARTS   AGE
coredns-559f6c778d-j8jdx                     1/1     Running   0          54s
coredns-559f6c778d-mfdr5                     1/1     Running   0          54s
etcd-mgmt-control-plane                      1/1     Running   0          63s
kindnet-j88rt                                1/1     Running   0          55s
kube-apiserver-mgmt-control-plane            1/1     Running   0          62s
kube-controller-manager-mgmt-control-plane   1/1     Running   0          62s
kube-proxy-zptt9                             1/1     Running   0          55s
kube-scheduler-mgmt-control-plane            1/1     Running   0          62s
```

이 네 파드는 노드 안의 `/etc/kubernetes/manifests`에 있는 매니페스트로 kubelet이 직접 띄운 static pod다.

```console
$ docker exec mgmt-control-plane ls /etc/kubernetes/manifests
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

static pod는 apiserver가 관리하지 않고 kubelet이 직접 감시하고 재시작한다. 그래서 apiserver가 아직 없을 때도 컨트롤 플레인을 띄울 수 있다. kubelet은 static pod마다 mirror Pod라는 객체를 apiserver에 만들어서 kubectl로 보이게만 하고, 이름 끝에는 `-<노드 이름>`을 붙인다. mirror Pod에는 `kubernetes.io/config.mirror` 어노테이션이 붙는다.

```console
$ kubectl get pod -n kube-system etcd-mgmt-control-plane -o jsonpath='{.metadata.annotations.kubernetes\.io/config\.mirror}'
40190fe57a6074ea2da833f16beeb689
```

kind는 `kind.yaml`을 kubeadm 설정으로 바꿔 노드 안의 `/kind/kubeadm.conf`에 쓰고, 그 파일로 `kubeadm init`을 실행한다. 파일에는 `ClusterConfiguration`, `InitConfiguration`, `JoinConfiguration`, `KubeletConfiguration`, `KubeProxyConfiguration` 다섯 개가 들어 있다. 앞으로의 단계와 관련 있는 부분만 옮긴다.

```console
$ docker exec mgmt-control-plane cat /kind/kubeadm.conf
apiServer:
  certSANs:
  - localhost
  - 127.0.0.1
  ...
apiVersion: kubeadm.k8s.io/v1beta4
clusterName: mgmt
controlPlaneEndpoint: mgmt-control-plane:6443
kind: ClusterConfiguration
kubernetesVersion: v1.37.0
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/16
...
---
apiVersion: kubeadm.k8s.io/v1beta4
bootstrapTokens:
- token: abcdef.0123456789abcdef
kind: InitConfiguration
...
---
apiVersion: kubeadm.k8s.io/v1beta4
discovery:
  bootstrapToken:
    apiServerEndpoint: mgmt-control-plane:6443
    token: abcdef.0123456789abcdef
    unsafeSkipCAVerification: true
kind: JoinConfiguration
...
---
apiVersion: kubelet.config.k8s.io/v1beta1
evictionHard:
  imagefs.available: 0%
  nodefs.available: 0%
  nodefs.inodesFree: 0%
kind: KubeletConfiguration
...
```

- `certSANs`에 `127.0.0.1`이 들어 있다. 내 kubeconfig의 서버 주소가 `https://127.0.0.1:50201`이므로, apiserver 인증서에 이 주소가 없으면 TLS 검증이 실패한다. 2번과 4번에서 테넌트 apiserver의 인증서를 만들 때도 사용자가 접속할 주소를 SAN에 넣어야 한다.
- `controlPlaneEndpoint`는 Docker 네트워크 안에서 쓰는 컨테이너 이름 `mgmt-control-plane:6443`이다.
- 노드 조인에 쓰는 bootstrap token `abcdef.0123456789abcdef`는 kind 소스에 상수로 박혀 있는 값이다(`pkg/cluster/internal/kubeadm/const.go`의 "dummy, well known token"). 조인할 때 CA도 확인하지 않는다(`unsafeSkipCAVerification: true`). 로컬 실험용 설정이고, 6번에서는 토큰을 직접 만들고 CA를 확인하는 방식으로 조인한다.
- `evictionHard`를 모두 `0%`로 두어서 디스크가 부족해도 kubelet이 파드를 쫓아내지 않는다.

확인:

```console
$ mise run check 01

== 01. 관리 클러스터 (mgmt)
  ✓ kind 클러스터가 있음: mgmt
  ✓ apiserver가 응답함 (v1.37.0)
  ✓ Ready 노드: mgmt-control-plane
  ✓ 버전 차이가 마이너 1 이내: kubectl 1.37, apiserver 1.37

통과
```

## 왜 필요한가

관리 클러스터는 테넌트의 컨트롤 플레인을 담는 곳이다. 이 클러스터가 없으면 3번부터 띄울 테넌트의 etcd와 apiserver를 올려 둘 곳이 없다. 테넌트 컨트롤 플레인을 관리 클러스터의 파드로 띄우면, 프로세스가 죽었을 때 다시 띄우는 일, 파드를 노드에 배치하는 일, Service로 주소를 고정하는 일을 관리 클러스터의 쿠버네티스가 대신 해 준다. Phase 2부터는 테넌트를 만드는 컨트롤러도 이 클러스터 안에서 돈다.

같은 "컨트롤 플레인을 파드로 띄운다"여도 두 방식이 있다는 점을 이 단계에서 확인했다. 관리 클러스터 자신의 컨트롤 플레인은 kubelet이 직접 띄우는 static pod다. 반면 3번부터 만들 테넌트의 컨트롤 플레인은 관리 클러스터의 apiserver를 통해 만드는 일반 파드(Deployment, StatefulSet)다. 관리 클러스터는 자기 apiserver가 뜨기 전에 컨트롤 플레인을 띄워야 해서 static pod를 쓰고, 테넌트는 이미 동작하는 관리 클러스터가 있으므로 일반 파드로 띄울 수 있다.

## 실제 EKS·GKE에서는

- EKS: 관리 클러스터에 해당하는 AWS 내부 시스템은 공개되어 있지 않다. 공개된 것은 컨트롤 플레인이 EKS가 관리하는 VPC 안에서 돌고, apiserver, scheduler, controller-manager가 도는 API 서버 노드가 auto scaling group에 속하며, 앞에서 NLB가 요청을 나눈다는 점이다. 클러스터마다 컨트롤 플레인이 따로 있고 다른 클러스터나 계정과 겹치지 않는다. ([EKS architecture](https://docs.aws.amazon.com/eks/latest/userguide/eks-architecture.html), [EKS best practices: Control plane](https://docs.aws.amazon.com/eks/latest/best-practices/control-plane.html))
- GKE: 컨트롤 플레인은 Google이 소유한 Compute Engine 인스턴스에서 Google이 관리하는 프로젝트 안에 돌고, 인스턴스 하나는 한 클러스터만 맡는다. 클러스터 상태는 컨트롤 플레인 VM마다 도는 etcd나 Spanner에 저장한다. ([GKE cluster architecture](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture))
- ROSA with HCP(Red Hat OpenShift Service on AWS, hosted control planes): 이 프로젝트와 같은 hosted control plane 방식을 쓰는 관리형 서비스다. apiserver와 etcd 같은 컨트롤 플레인은 Red Hat 소유의 AWS 계정에 두고, 워커 노드만 고객 계정에 두며, 둘은 AWS PrivateLink로 통신한다. ([ROSA architecture models](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/architecture/rosa-architecture-models))

세 서비스 모두 사용자는 컨트롤 플레인이 도는 기계를 볼 수 없다. 우리 프로젝트에서 테넌트 사용자가 관리 클러스터를 볼 수 없게 하는 것과 같다.

## 우리 환경과의 차이

- 관리 클러스터가 노드 하나(컨테이너 하나)다. 이 컨테이너가 죽으면 그 위의 모든 테넌트 컨트롤 플레인이 함께 멈춘다. 실제 서비스는 컨트롤 플레인을 여러 AZ에 나눠 두며, 이 프로젝트에서는 16번에서 노드 3개와 zone 라벨로 흉내 낸다.
- kind 노드는 VM이 아니라 컨테이너라서 호스트(OrbStack VM)의 커널을 함께 쓴다.
- kind는 편의를 위해 고정된 bootstrap token을 쓰고 조인할 때 CA를 확인하지 않는다. 관리 클러스터에만 해당하는 설정이고, 테넌트 노드의 조인은 6번에서 제대로 만든다.
- 관리 클러스터 자신은 kubeadm으로 만든 일반 클러스터라서 이 클러스터의 업그레이드, 백업, 복구는 이 프로젝트의 범위 밖이다. 실제 서비스에서는 이 층도 운영자가 관리해야 한다.

## 막힌 것과 배운 것

- 만든 직후(13초 뒤)에 검사하면 노드가 NotReady였다. Ready 조건의 메시지는 `container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized`였고, CNI인 kindnet이 뜬 뒤 몇 초 만에 Ready가 됐다. 6번에서 테넌트 워커를 조인하면 같은 이유로 NotReady가 되고, 7번에서 CNI를 직접 설치하게 된다.
