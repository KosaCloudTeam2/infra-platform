# KOSA 인프라 프로젝트 — 자산 인벤토리

> 작성일: 2026-05-13
> 학습용 / 프로젝트용 문서 작성의 기반 자료. 분석 X, 사실만.

---

## 표 1: 인프라 컴포넌트

| 이름 | 버전 | 위치(namespace/path) | 동작 검증 명령 |
|---|---|---|---|
| Proxmox VE (kosa1) | VE 8.x | 192.168.21.2 | `ssh kosa1 'pve-version'` |
| Proxmox VE (kosa2) | VE 8.x | 192.168.21.3 | `ssh kosa2 'pve-version'` |
| Proxmox VE (kosa3) | VE 8.x | 192.168.21.4 | `ssh kosa3 'pve-version'` |
| Proxmox VE (kosa4) | VE 8.x | 192.168.21.5 | `ssh kosa4 'pve-version'` |
| pfSense HA (CARP) | 2.7+ | VIP 192.168.21.10 | `ping 192.168.21.10` |
| Cloud-init 템플릿 | Ubuntu Noble 24.04 | VMID 9000 / kosa1 / ceph-rbd-team2 | `[kosa1]# qm config 9000` |
| k8s-cp1 | VMID 210 / v1.30.14 | 172.16.23.10 / kosa4 (2026-05-13 마이그레이션) | `kubectl get node k8s-cp1` |
| k8s-cp2 | VMID 211 / v1.30.14 | 172.16.23.11 / kosa2 | `kubectl get node k8s-cp2` |
| k8s-cp3 | VMID 212 / v1.30.14 | 172.16.23.12 / kosa3 | `kubectl get node k8s-cp3` |
| k8s-w1 | VMID 220 / v1.30.14 | 172.16.23.20 / kosa3 | `kubectl get node k8s-w1` |
| k8s-w2 | VMID 221 / v1.30.14 | 172.16.23.21 / kosa4 | `kubectl get node k8s-w2` |
| k8s-w3 | VMID 222 / v1.30.14 | 172.16.23.22 / kosa2 | `kubectl get node k8s-w3` |
| bastion | VMID 230 | 172.16.24.10 / kosa3 | `ssh bastion 'kubectl version --client'` |
| containerd | 2.2.1 | k8s 전 노드 | `[k8s-XXX]$ systemctl is-active containerd` |
| Calico CNI | v3.27+ | namespace: calico-system | `kubectl -n calico-system get pods` |
| MetalLB | v0.13+ | metallb-system / pool: 172.16.23.100-150 | `kubectl get ipaddresspools -A` |
| cert-manager | v1.13+ | namespace: cert-manager | `kubectl -n cert-manager get pods` |
| Ceph 클러스터 (외부) | v18+ | 별도 6노드, 10GbE Spine-Leaf | `[ceph-mon]# ceph -s` |
| Ceph Pool (Proxmox) | `ceph-rbd-team2` | RBD 3-replica | `[ceph-mon]# ceph osd pool ls` |
| Ceph Pool (K8s) | `team2-k8s-pvc-rbd` | RBD 3-replica | `rbd ls -p team2-k8s-pvc-rbd` |
| ceph-csi-rbd (Helm) | 3.16.2 | namespace: ceph-csi-rbd | `kubectl -n ceph-csi-rbd get pods` |
| StorageClass | `team2-rbd-block` (default) | provisioner: rbd.csi.ceph.com | `kubectl get sc` |
| ceph-csi Secret | `team2-rbd-csi-secret` | namespace: ceph-csi-rbd | `kubectl -n ceph-csi-rbd get secret team2-rbd-csi-secret` |
| Ceph User | `client.team2-k8s-csi` | Ceph 클러스터 | `[ceph-mon]# ceph auth get client.team2-k8s-csi` |
| Percona Operator | 1.14.0 | namespace: pxc-operator | `kubectl -n pxc-operator get pods` |
| PXC (Percona XtraDB) | 8.0.36-28.1 / 3노드 | namespace: pii-protected | `kubectl get pxc kosa-pxc -n pii-protected` |
| ProxySQL | 2.5.5 / 2노드 | namespace: pii-protected | `kubectl -n pii-protected get pods -l app=proxysql` |
| Redis Sentinel | bitnami chart / 3노드 | namespace: kosa-app | `kubectl -n kosa-app get pods -l app=redis` |
| Prometheus | kube-prometheus-stack | namespace: monitoring | `kubectl -n monitoring get pods` |
| Grafana | v10+ | namespace: monitoring / LoadBalancer 172.16.23.102 | `kubectl -n monitoring get svc kube-prom-grafana` |
| ArgoCD | v2.10+ | namespace: argocd / LoadBalancer 172.16.23.101 | `kubectl -n argocd get pods` |
| ticket-app | Python 3.11 / FastAPI 0.115 | namespace: kosa-tickets / 172.16.23.103 | `kubectl -n kosa-tickets get pods,svc,hpa` |
| ticket-app DB Secret | `ticket-db-credentials` | namespace: kosa-tickets | `kubectl -n kosa-tickets get secret ticket-db-credentials` |
| ticket-app DB | `kosa_tickets` schema | PXC / user: kosa_app | `kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- mysql -ukosa_app -pkosa1004 kosa_tickets -e "SHOW TABLES;"` |

---

## 표 2: 디버깅 함정

| 증상 | 원인 | 해결 명령 | 출처/적용 챕터 |
|---|---|---|---|
| PVC Pending, PV Released 안 빠짐 | finalizer 남음, RBD 이미지 삭제 무한 retry | `kubectl patch pv <PV> --type='merge' -p '{"metadata":{"finalizers":null}}'` | Phase 5.3 / 함정 4 |
| ceph-csi Secret 참조 4개 누락 | StorageClass의 controllerPublishSecret 등 미명시 | Helm values에 `provisionerSecret`, `controllerExpandSecret`, `controllerPublishSecret`, `nodeStageSecret` 4개 모두 명시 | Phase 5.2 / 함정 1 |
| ConfigMap fsid placeholder | values.yaml에 `<5.1의 fsid>` 그대로 적용 | sed로 진짜 fsid 치환 + helm upgrade + provisioner pod restart | Phase 5.2 / 함정 1 |
| PXC Operator가 PXC CR 못 봄 | WATCH_NAMESPACE가 자기 ns만 감시 | `kubectl edit deployment percona-xtradb-cluster-operator` → value: "pxc-operator,pii-protected" + Role/RoleBinding 복제 | Phase 6.3 / 함정 1 |
| PXC PVC가 옛 SC 참조 | spec.pxc.volumeSpec.persistentVolumeClaim.storageClassName immutable | CR 삭제 후 metadata/status 제거하고 재생성 | Phase 6.3 / 함정 2 |
| 옛 STS + PVC 잔재 | StatefulSet의 volumeClaimTemplate가 옛 SC로 PVC 생성 중 | `kubectl delete sts -n pii-protected --all --force --grace-period=0 && kubectl delete pvc -n pii-protected --all` | Phase 6.3 / 함정 3 |
| MetalLB External-IP 도달 불가 | pool이 VLAN 20인데 K8s 노드는 VLAN 30 → ARP 응답 못 함 | `kubectl -n metallb-system patch ipaddresspool kosa-pool --type='merge' -p '{"spec":{"addresses":["172.16.23.100-172.16.23.150"]}}'` + svc 토글 | Phase 6.5 |
| ImagePullBackOff (GHCR) | private 패키지 + organization 정책 | 패키지를 public으로 변경 (org 정책 허용 필요) 또는 imagePullSecret 생성 | Phase 6.2 |
| Docker 이미지 이름 거부 | 대문자 포함 (KosaCloudTeam2) | OWNER 변수를 소문자로 (kosacloudteam2 또는 sangchul1) | Phase 6.2 |
| cp1 자주 OOM/leader change | kosa1에 cp1 + pfSense-1 메모리 경쟁 | cp1 → kosa4 마이그레이션 (`qm migrate 210 kosa4`) | Session_Handoff |
| kosa3 호스트 자주 다운 | cp3 + w1 + bastion 3개 VM 부담 | bastion을 kosa4로 이동 권장 (선택) | Session_Handoff |
| etcd leader change 빈번 | CP 부하 + Ceph RBD IO 지연 | playbook task에 `retries: 5, delay: 15, until: succeeded` 추가 | Phase 4 Step 5 |
| K8s API server connection refused | etcd leader 일시 끊김 | `kubectl config set-cluster kubernetes --server=https://172.16.23.11:6443` (cp2로 우회) | Phase 4/5/6 공통 |
| newgrp docker 비밀번호 요구 | cloud-init user는 비밀번호 없음 | SSH 재로그인 (`exit && ssh bastion`) | Phase 6.2 |
| docker 그룹 변경 미적용 | 현재 세션은 옛 그룹 정보 | SSH 재로그인 또는 `newgrp docker` (위 함정) | Phase 6.2 |
| `helm install` 이름 중복 | 이미 같은 release 있음 | `helm upgrade --install` 사용 (idempotent) | Phase 5.2 |
| ticket-app Pod CrashLoopBackOff (DB 연결) | env 이름 미스매치 (DB_HOST vs DATABASE_HOST) | config.py 환경변수 받게 수정 + Secret 키 이름 통일 | Phase 6 (ticket-app) |

---

## 표 3: 운영 명령어 (목적별 분류)

### 상태 확인

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| 노드 상태 | `kubectl get nodes -o wide` | [bastion] |
| 전체 Pod | `kubectl get pods -A` | [bastion] |
| 비정상 Pod만 | `kubectl get pods -A \| grep -vE "Running\|Completed"` | [bastion] |
| PVC | `kubectl get pvc -A` | [bastion] |
| StorageClass | `kubectl get storageclass` | [bastion] |
| LoadBalancer | `kubectl get svc -A \| grep LoadBalancer` | [bastion] |
| HPA | `kubectl get hpa -A` | [bastion] |
| Pod CPU/Mem | `kubectl top pods -A` | [bastion] |
| 노드 CPU/Mem | `kubectl top nodes` | [bastion] |
| Events | `kubectl get events -n <ns> --sort-by='.lastTimestamp' \| tail -20` | [bastion] |

### 클러스터 안정성

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| etcd 멤버 | `kubectl exec etcd-k8s-cp1 -n kube-system -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key member list` | [bastion] |
| etcd 헬스 | `kubectl exec etcd-k8s-cp1 -n kube-system -- etcdctl ... endpoint status --write-out=table` | [bastion] |
| API endpoint 변경 | `kubectl config set-cluster kubernetes --server=https://172.16.23.11:6443` | [bastion] |
| kubelet 재시작 | `ssh -i ~/.ssh/kosa_iac ubuntu@<IP> 'sudo systemctl restart kubelet'` | [bastion] |

### Ceph 측

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| 클러스터 상태 | `ceph -s` | [ceph-mon] |
| fsid | `ceph fsid` | [ceph-mon] |
| 모니터 IP | `ceph mon dump` | [ceph-mon] |
| Pool 목록 | `ceph osd pool ls` | [ceph-mon] |
| User 권한 | `ceph auth get client.team2-k8s-csi` | [ceph-mon] |
| RBD 이미지 목록 | `rbd ls -p team2-k8s-pvc-rbd` | [ceph-mon] |
| 고아 이미지 삭제 | `rbd rm team2-k8s-pvc-rbd/csi-vol-<id>` | [ceph-mon] |

### 배포/롤백

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| Manifest apply | `kubectl apply -f <file or dir>` | [bastion] |
| Helm idempotent install | `helm upgrade --install <name> <chart> -n <ns> --create-namespace -f values.yaml` | [bastion] |
| Rollout 상태 | `kubectl rollout status deployment/<name> -n <ns>` | [bastion] |
| 롤백 | `kubectl rollout undo deployment/<name> -n <ns>` | [bastion] |
| 이미지 갱신 | `kubectl set image deployment/<name> <cont>=<img:tag> -n <ns>` | [bastion] |

### 부하 테스트

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| k6 부하 시작 | `k6 run -e BASE_URL=http://172.16.23.103 /path/k6-test.js` | [노트북] |
| HPA 모니터링 | `watch -n 2 'kubectl get pods,hpa -n kosa-tickets'` | [bastion] |
| 결과 저장 | `k6 run ... --summary-export=result.json \| tee result.txt` | [노트북] |

### 트러블슈팅

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| Pod 상세 | `kubectl describe pod <name> -n <ns>` | [bastion] |
| Pod 로그 | `kubectl logs <pod> -n <ns> --tail=50` | [bastion] |
| 이전 컨테이너 로그 | `kubectl logs <pod> -n <ns> --previous --tail=50` | [bastion] |
| Pod 진입 | `kubectl exec -it <pod> -n <ns> -- bash` | [bastion] |
| Finalizer 제거 | `kubectl patch <type> <name> -n <ns> --type='merge' -p '{"metadata":{"finalizers":null}}'` | [bastion] |
| Port-forward | `kubectl port-forward -n <ns> svc/<svc> 8080:80 --address=0.0.0.0` | [bastion] |
| Pod 강제 삭제 | `kubectl delete pod <name> -n <ns> --force --grace-period=0` | [bastion] |

### Proxmox VM 관리

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| VM 목록 | `qm list` | [kosaN] |
| VM 상태 | `qm status <vmid>` | [kosaN] |
| VM 시작 | `qm start <vmid>` | [kosaN] |
| VM 종료 (graceful) | `qm shutdown <vmid>` | [kosaN] |
| VM 강제 종료 | `qm stop <vmid>` | [kosaN] |
| VM 마이그레이션 | `qm migrate <vmid> <target-node> [--online]` | [kosaN] |
| 메모리 변경 | `qm set <vmid> -memory <MB>` | [kosaN] |
| VM 설정 보기 | `qm config <vmid>` | [kosaN] |

### MySQL/PXC

| 목적 | 명령어 | 실행 위치 |
|---|---|---|
| root 접속 | `kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- mysql -uroot -pkosa1004` | [bastion] |
| Galera 사이즈 | `mysql> SHOW STATUS LIKE 'wsrep_cluster_size';` (값 3 기대) | [bastion] |
| Pod별 hostname | `mysql> SELECT @@hostname;` (어느 PXC 노드인지) | [bastion] |
| 앱 user 접속 | `kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- mysql -ukosa_app -pkosa1004 kosa_tickets` | [bastion] |
| Secret 비밀번호 추출 | `kubectl get secret kosa-pxc-secrets -n pii-protected -o jsonpath='{.data.root}' \| base64 -d; echo` | [bastion] |

---

## 표 4: 시연 시나리오

| 시나리오 | 단계 | 명령 | 기대 결과 |
|---|---|---|---|
| **좌석 페이지 + 예약** | 1. 서비스 IP | `kubectl -n kosa-tickets get svc ticket-app` | EXTERNAL-IP: 172.16.23.103 |
| | 2. 브라우저 접속 | `http://172.16.23.103` | 100개 좌석 그리드 로드 |
| | 3. 좌석 클릭 | A1 클릭 | 회색 + flash + "예약 완료 pod: ticket-app-xxx" |
| | 4. 충돌 시연 | A1 재클릭 | "이미 예약됨" 메시지 (HTTP 409) |
| | 5. 새로고침 | 페이지 새로고침 | 예약 상태 유지 (PXC INSERT 영속) |
| | 6. 리셋 | "전체 리셋" 버튼 | 100개 모두 available |
| **PXC 동기 복제** | 1. pxc-0에 INSERT | `kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- mysql -ukosa_app -pkosa1004 kosa_tickets -e "INSERT INTO seat (seat_no, status) VALUES ('TEST', 'available');"` | Query OK |
| | 2. pxc-1에서 조회 | `kubectl exec kosa-pxc-pxc-1 -n pii-protected -- mysql -ukosa_app -pkosa1004 kosa_tickets -e "SELECT * FROM seat WHERE seat_no='TEST';"` | 1행 조회 |
| | 3. pxc-2에서 조회 | `kubectl exec kosa-pxc-pxc-2 -n pii-protected -- mysql -ukosa_app -pkosa1004 kosa_tickets -e "SELECT * FROM seat WHERE seat_no='TEST';"` | 1행 조회 (3노드 동기 복제) |
| | 4. cluster size | `mysql -uroot -pkosa1004 -e "SHOW STATUS LIKE 'wsrep_cluster_size';"` | 3 |
| **HPA 자동 스케일** | 1. 초기 | `kubectl get pods,hpa -n kosa-tickets` | Pod 2, CPU 5% |
| | 2. k6 시작 | `k6 run -e BASE_URL=http://172.16.23.103 k6-test.js` | warming up |
| | 3. 0~30초 (10 VU) | watch | Pod 2 유지 |
| | 4. 30~90초 (100 VU) | watch | Pod 2 → 4 → 6 |
| | 5. 90~150초 (500 VU) | watch | Pod 6 → 10 (max) |
| | 6. Grafana | `http://172.16.23.102` → kube-prom dashboard | CPU/Pod 그래프 폭발 |
| | 7. 150~180초 cooldown | k6 종료 | Pod 10 → 점진 감소 |
| | 8. 5분 후 | watch | Pod 2로 복귀 |
| **Pod 강제 삭제 후 복구** | 1. Pod 확인 | `kubectl get pods -n kosa-tickets` | ticket-app-XXX 2개 |
| | 2. 강제 삭제 | `kubectl delete pod ticket-app-XXX -n kosa-tickets` | deleted |
| | 3. 자동 재생성 | `kubectl get pods -n kosa-tickets -w` | 새 Pod 5~10초 내 Running |
| | 4. 데이터 유지 확인 | 브라우저 새로고침 | 예약 상태 그대로 (PXC 영속) |
| **VM 강제 종료 (HA)** | 1. 노드 상태 | `kubectl get nodes` | 6/6 Ready |
| | 2. cp 종료 | `ssh root@192.168.21.5 'qm stop 210'` | cp1 stopped |
| | 3. 즉시 상태 | `kubectl get nodes` | cp1 NotReady (cp2/cp3는 Ready) |
| | 4. etcd quorum | `kubectl exec etcd-k8s-cp2 ... member list` | 2/3 quorum 유지 |
| | 5. API 동작 | `kubectl get pods -A` | 정상 응답 |
| | 6. cp1 재시작 | `qm start 210` | 1~2분 후 Ready 복귀 |
| **Grafana 대시보드** | 1. 접속 | `http://172.16.23.102` | admin / kosa1004 |
| | 2. 대시보드 선택 | "Kubernetes / Compute Resources / Namespace (Pods)" | 로드 |
| | 3. namespace 필터 | kosa-tickets | ticket-app만 표시 |
| | 4. 시간 범위 | "Last 30 minutes" | 부하 테스트 전체 보임 |
| | 5. 핵심 그래프 | CPU / Memory / Pod count | 산 모양 (2→10→2) |
| **Ceph RBD 직접 확인** | 1. Ceph 노드 SSH | `ssh root@10.10.10.12` | 프롬프트 |
| | 2. K8s pool 이미지 | `rbd ls -p team2-k8s-pvc-rbd` | csi-vol-... 다수 |
| | 3. 이미지 상세 | `rbd info team2-k8s-pvc-rbd/csi-vol-XXX` | size, features, journal |
| | 4. Proxmox pool 비교 | `rbd ls -p ceph-rbd-team2` | vm-XXX-disk-N (별도 pool) |
| | 5. 용량 | `ceph df` | pool별 사용량 |
| **(로드맵) AWS Karpenter burst** | 1. 컨셉 | — | "온프레미스 max 10 pod → AWS EKS spot 5대 spawn" |
| | 2. 구현 단계 | — | VPC → NLB → EKS → Karpenter → Route 53 |
| | 3. 발표 멘트 | — | "다음 단계: 평시 비용 0 + 티켓 오픈 1시간 $3 burst" |
