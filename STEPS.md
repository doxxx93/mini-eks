# 진행표

위에서부터 하나씩 진행합니다. 단계를 마치면 `[x]`로 바꾸고, 화살표 뒤의 노트를 `notes/`에 남깁니다.

## Phase 0. 큰 그림

- [ ] 0. `README.md`를 읽고 무엇을 만드는지 내 말로 정리 → `00-big-picture.md`

## Phase 1. 손으로 테넌트 클러스터 하나 만들기 (kind, 코드 없음)

Kubernetes The Hard Way가 같은 과정을 VM 위에서 진행합니다. 여기서는 컨트롤 플레인을 관리 클러스터의 파드로 띄운다는 점이 다릅니다.

- [ ] 1. kind로 관리 클러스터 만들기 · 확인: `kubectl get nodes` → `01-mgmt-cluster.md`
- [ ] 2. 테넌트용 인증서(PKI) 만들기, 인증서가 왜 여러 개 필요한지 정리 → `02-pki.md`
- [ ] 3. etcd를 파드로 띄우기 · 확인: etcdctl로 키를 쓰고 읽기 → `03-etcd.md`
- [ ] 4. kube-apiserver를 파드로 띄우고 노출하기 · 확인: 테넌트 kubeconfig로 `kubectl get ns` → `04-apiserver.md`
- [ ] 5. controller-manager와 scheduler 띄우기 · 확인: Deployment를 만들면 ReplicaSet과 파드는 생기지만 노드가 없어서 파드가 Pending → `05-cm-scheduler.md`
- [ ] 6. 워커 컨테이너를 띄우고 bootstrap token으로 kubelet 조인 · 확인: `kubectl get nodes`에 노드가 NotReady로 보임 → `06-node-join.md`
- [ ] 7. CNI 설치 · 확인: 노드 Ready, 파드 Running → `07-cni.md`
- [ ] 8. 워커를 다른 Docker 네트워크로 분리 · 확인: `kubectl logs`가 실패하고, konnectivity를 설치하면 다시 동작 → `08-konnectivity.md`

## Phase 2. Go 컨트롤러로 옮기기

- [ ] 9. CRD 설계 (`ManagedCluster`, `NodePool`): 두 언어가 같이 쓰는 스키마 → `09-crd.md`
- [ ] 10. 언어와 무관한 검증 스크립트: Phase 1의 확인 항목을 자동화 → `10-e2e.md`
- [ ] 11. Go: 컨트롤 플레인 컨트롤러 (2~5단계 자동화), 10번 통과 → `11-go-controlplane.md`
- [ ] 12. Go: NodePool 컨트롤러와 Docker 드라이버 (6~8단계 자동화), 10번 통과 → `12-go-nodepool.md`

## Phase 3. Rust로 같은 것 만들기

- [ ] 13. Rust: 컨트롤 플레인 컨트롤러, 10번 통과 → `13-rust-controlplane.md`
- [ ] 14. Rust: NodePool 컨트롤러, 10번 통과 → `14-rust-nodepool.md`
- [ ] 15. 두 구현 비교 → `15-go-vs-rust.md`

## Phase 4. 운영 기능 (Go 먼저, Rust가 뒤따름)

- [ ] 16. 노드 자동 복구와 스케일 → `16-repair-scale.md`
- [ ] 17. 버전 업그레이드: 컨트롤 플레인을 먼저, 노드를 나중에, version skew 정책 준수 → `17-upgrade.md`
- [ ] 18. etcd 백업과 복구 → `18-etcd-backup.md`

## Phase 5. 진짜 VM으로 옮기기 (Lima + KubeVirt)

- [ ] 19. Lima VM(nestedVirtualization), kubeadm 관리 클러스터, KubeVirt · 확인: VM 하나를 띄워 SSH 접속 → `19-lima-kubevirt.md`
- [ ] 20. KubeVirt 드라이버 추가, 10번 통과 → `20-kubevirt-driver.md`
- [ ] 21. CCM과 CSI 연결 · 확인: LoadBalancer IP로 Mac에서 접속, 파드가 옮겨 가도 PVC 데이터 유지 → `21-ccm-csi.md`
- [ ] 22. 테넌트 간 네트워크 격리 → `22-isolation.md`
