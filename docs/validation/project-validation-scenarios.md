# Project Overview Validation Scenarios

이 문서는 `C:/infra-platform/Project_Study_latest`를 기준으로 프로젝트 전체 구성요소를 검증하기 위한 실행형 테스트 시나리오다. 다른 팀원이 bastion VM 또는 각 관리 UI에서 그대로 따라 할 수 있도록 실행 위치, CLI 명령어, GUI 경로, 성공 기준, 원복 방법을 함께 적었다.

> 주의: `delete pod`, `shutdown`, `stop` 같은 장애 유도 테스트는 실제 서비스에 영향을 줄 수 있다. 발표/운영 중에는 반드시 담당자에게 알리고, 한 번에 하나의 장애만 유도한다.

## 목차

0. [공통 준비](#0-공통-준비)
1. [전체 서비스 경로 검증](#1-전체-서비스-경로-검증)
2. [pfSense HA / VLAN / 방화벽](#2-pfsense-ha--vlan--방화벽)
3. [Proxmox / VM 배치 / Cloud-init](#3-proxmox--vm-배치--cloud-init)
4. [Bastion / 운영 진입점](#4-bastion--운영-진입점)
5. [Kubernetes Control Plane / API LB](#5-kubernetes-control-plane--api-lb)
6. [Calico / MetalLB / Ingress](#6-calico--metallb--ingress)
7. [Edge HAProxy / 이중 TLS / PKI](#7-edge-haproxy--이중-tls--pki)
8. [Ceph / 10G Storage / CSI](#8-ceph--10g-storage--csi)
9. [Harbor / Ceph RGW Registry](#9-harbor--ceph-rgw-registry)
10. [Jenkins / Kaniko / CI](#10-jenkins--kaniko--ci)
11. [ArgoCD / GitOps](#11-argocd--gitops)
12. [PXC / ProxySQL / 데이터베이스](#12-pxc--proxysql--데이터베이스)
13. [Redis Sentinel](#13-redis-sentinel)
14. [Monitoring / Logging / Alert](#14-monitoring--logging--alert)
15. [HPA / k6 / ticket-app](#15-hpa--k6--ticket-app)
16. [AWS Hybrid / Site-to-Site VPN](#16-aws-hybrid--site-to-site-vpn)
17. [운영/복구 Runbook](#17-운영복구-runbook)
18. [우선순위별 실행 순서](#18-우선순위별-실행-순서)
19. [테스트 중단 기준](#19-테스트-중단-기준)

---

## 0. 공통 준비

### 0.1 실행 위치 표기

| 표기 | 의미 |
|---|---|
| bastion | `172.16.24.10` bastion VM에서 실행 |
| Proxmox UI | `https://kosa1:8006` 또는 각 Proxmox 노드 웹 UI |
| pfSense UI | pfSense Web UI에서 실행 |
| Ceph node | 보통 `ceph1` 또는 Ceph admin shell에서 실행 |
| AWS Console | AWS 웹 콘솔에서 확인 |
| Browser | 팀원 노트북 또는 bastion에서 접근 가능한 브라우저 |

### 0.2 현재 VM / VIP / IP 기준 정보

아래 정보는 `CLAUDE.md`의 운영 reference를 기준으로 한다. 테스트 중 실제 상태가 다르면 먼저 `CLAUDE.md`와 현재 클러스터 출력 중 무엇이 최신인지 확인하고 기록한다.

Proxmox 노드:

| 노드 | 관리 IP | 10G IP | 비고 |
|---|---|---|---|
| kosa1 | 192.168.21.2 | 10.10.10.35 | k8s-sys1 배치 |
| kosa2 | 192.168.21.3 | 10.10.10.36 | k8s-cp2, k8s-w3, lb-1 배치 |
| kosa3 | 192.168.21.4 | 10.10.10.37 | k8s-cp3, k8s-w1, bastion, edge-haproxy2 배치 |
| kosa4 | 192.168.21.5 | 10.10.10.38 | k8s-cp1, k8s-w2, lb-2, edge-haproxy 배치 |

배포 VM:

| VM | VMID | PVE 노드 | IP | 10G IP | 역할 |
|---|---:|---|---|---|---|
| k8s-cp1 | 210 | kosa4 | 172.16.23.10 | - | K8s Control Plane |
| k8s-cp2 | 211 | kosa2 | 172.16.23.11 | - | K8s Control Plane |
| k8s-cp3 | 212 | kosa3 | 172.16.23.12 | - | K8s Control Plane |
| k8s-w1 | 220 | kosa3 | 172.16.23.20 | 10.10.10.120 | production worker |
| k8s-w2 | 221 | kosa4 | 172.16.23.21 | 10.10.10.121 | production worker |
| k8s-w3 | 222 | kosa2 | 172.16.23.22 | 10.10.10.122 | production worker |
| k8s-sys1 | 223 | kosa1 | 172.16.23.23 | 10.10.10.123 | system worker |
| bastion | 230 | kosa3 | 172.16.24.10 | - | Ansible runner, kubectl |
| lb-1 | 240 | kosa2 | 172.16.23.6 | - | K8s API HAProxy + Keepalived MASTER |
| lb-2 | 241 | kosa4 | 172.16.23.7 | - | K8s API HAProxy + Keepalived BACKUP |
| edge-haproxy | 250 | kosa4 | 172.16.22.10 | - | Edge L7 MASTER |
| edge-haproxy2 | 251 | kosa3 | 172.16.22.11 | - | Edge L7 BACKUP |

VIP / 주요 엔드포인트:

| IP / 값 | 용도 |
|---|---|
| 192.168.21.1 | 외부 라우터 |
| 192.168.21.109 | pfSense WAN VIP, 외부 NAT 진입 |
| 172.16.21.1 | VLAN 10 gateway |
| 172.16.22.1 | VLAN 20 gateway |
| 172.16.23.1 | VLAN 30 gateway |
| 172.16.24.1 | VLAN 40 gateway |
| 172.16.22.5 | Edge HAProxy VIP |
| 172.16.23.5 | K8s API VIP |
| 172.16.23.50 | K8s Ingress LoadBalancer IP, MetalLB L2 |
| 10.10.10.11:7480 | Ceph RGW endpoint, ceph1 단일 daemon |
| 10.20.10.121 | AWS private EC2 검증 대상 |
| kosa-tickets-nlb-091d28bb8f4ca020.elb.ap-northeast-2.amazonaws.com | AWS NLB |

K8s 워크로드 배치 기준:

| 라벨 | 노드 | 용도 |
|---|---|---|
| `workload-type=system` | k8s-sys1 | ArgoCD, monitoring, Harbor, Jenkins, cert-manager |
| `workload-type=production` | k8s-w1/w2/w3 | ticket-app, Redis, 기타 비즈니스 워크로드 |

Ceph pool 기준:

- K8s CSI 실제 pool: `team2-k8s-pvc-rbd`
- 팀별 테스트 pool: `rbd-team1` ~ `rbd-team4`
- CephFS pool: `cephfs_metadata`, `cephfs_data`
- RGW backend pool: `default.rgw.*`

```bash
# bastion
# StorageClass 확인
kubectl get sc -o yaml | grep -E 'storageclass|pool:|team2'

# Ceph node
# Ceph 상태 확인
ceph osd pool ls
```

### 0.3 bastion 기본 점검

```bash
# bastion
# 호스트명 확인
hostname
# IP 설정 확인
ip addr
# kubectl 버전 확인
kubectl version --client
# K8s API 연결 확인
kubectl cluster-info
# K8s 노드 상태 확인
kubectl get nodes -o wide
```

성공 기준:

- `kubectl cluster-info`가 `172.16.23.5:6443` API VIP를 통해 응답한다.
- 전체 K8s 노드가 `Ready`다.

### 0.4 결과 기록 양식

각 테스트 완료 후 아래 형식으로 결과를 남긴다.

| 항목 | 기록 |
|---|---|
| 테스트 ID | 예: `8.4 Ceph CSI / PVC` |
| 실행자 | 이름 |
| 실행 일시 | YYYY-MM-DD HH:mm |
| 결과 | PASS / FAIL / PARTIAL |
| 주요 출력 | 명령 결과 핵심 3줄 |
| 특이사항 | 실패 원인, 복구 조치 |

## 1. 전체 서비스 경로 검증

### 1.1 외부 사용자가 ticket-app까지 접근

목적: 사용자 요청이 `pfSense WAN VIP 192.168.21.109 -> NAT -> Edge HAProxy VIP 172.16.22.5 -> K8s Ingress LB 172.16.23.50 -> Service -> Pod` 전체 경로를 통과하는지 확인한다.

CLI:

```bash
# bastion
# DNS 해석 확인
dig +short ticket.kosa.team2

# health check 응답 확인
curl -k -i https://ticket.kosa.team2/healthz

# ticket Ingress 존재 확인
kubectl get ingress -A | grep ticket

# Service/Pod 상태 확인
kubectl get svc,pod -n kosa-tickets -o wide

# 최근 앱 로그 확인
kubectl logs -n kosa-tickets -l app=ticket-app --tail=50
```

GUI:

- Browser: `https://ticket.kosa.team2` 접속
- pfSense UI: `Status > System Logs > Firewall`에서 관련 허용 로그 확인
- Grafana: ticket-app 또는 Ingress 대시보드에서 요청 증가 확인

성공 기준:

- DNS 결과가 Ingress VIP 또는 의도한 진입 IP를 가리킨다.
- `/healthz`가 HTTP 200을 반환한다.
- ticket-app Pod 로그에 요청이 기록된다.

문제 시 확인:

```bash
# bastion
# 상세 설정/이벤트 확인
kubectl describe ingress -n kosa-tickets
kubectl describe svc -n kosa-tickets ticket-app
# Service 연결 대상 확인
kubectl get endpoints -n kosa-tickets ticket-app
```

### 1.2 전체 장애 영향도 빠른 점검

목적: 발표/검증 시작 전 전체 플랫폼이 테스트 가능한 상태인지 빠르게 판단한다.

CLI:

```bash
# bastion
# K8s 노드 상태 확인
kubectl get nodes -o wide
# Pod 상태 확인
kubectl get pods -A
# ArgoCD 앱 상태 확인
kubectl get applications -n argocd -o wide
# HTTP 응답 확인
curl -k -sS https://ticket.kosa.team2/healthz
```

```bash
# Ceph node
# Ceph 전체 상태 확인
ceph -s
# Ceph 상태 확인
ceph osd tree
```

성공 기준:

- K8s Node는 `Ready`
- 주요 ArgoCD Application은 `Synced`와 `Healthy`
- Ceph는 `HEALTH_OK` 또는 사유가 명확한 `HEALTH_WARN`
- ticket-app health check 정상

## 2. pfSense HA / VLAN / 방화벽

### 2.1 pfSense 이중화 구성 검증

목적: MASTER pfSense 장애 시 BACKUP pfSense가 CARP VIP를 인수하고 VLAN 게이트웨이 기능을 유지하는지 확인한다.

사전 확인:

```bash
# bastion
# VLAN 20 gateway 확인
ping -c 3 172.16.22.1
# VLAN 30 gateway 확인
ping -c 3 172.16.23.1
# VLAN 40 gateway 확인
ping -c 3 172.16.24.1
# HTTP 응답 확인
curl -I https://ticket.kosa.team2 -k
```

GUI:

1. pfSense UI 접속
2. `Status > CARP (failover)`에서 MASTER/BACKUP 확인
3. `Status > Interfaces`에서 각 VLAN 인터페이스 상태 확인

장애 유도:

1. Proxmox UI 접속
2. MASTER pfSense VM 선택
3. `Shutdown` 클릭
4. 10~30초 대기

전환 확인:

```bash
# bastion
# 네트워크 연결 확인
ping -c 5 172.16.23.1
# HTTP 응답 확인
curl -k -i https://ticket.kosa.team2/healthz
```

GUI:

- pfSense BACKUP UI: `Status > CARP (failover)`에서 MASTER 승격 확인
- Proxmox UI: 기존 MASTER VM이 stopped 상태인지 확인

성공 기준:

- BACKUP이 MASTER로 승격된다.
- `172.16.22.1`, `172.16.23.1`, `172.16.24.1` 게이트웨이 ping이 유지된다.
- ticket-app 접근이 복구되거나 끊김이 짧다.

원복:

1. Proxmox UI에서 기존 MASTER pfSense VM `Start`
2. pfSense UI에서 CARP 상태 확인
3. 필요 시 `Status > CARP > Enable CARP` 확인

### 2.2 VLAN 간 정책 검증

목적: VLAN 간 허용/차단 정책이 의도대로 동작하는지 확인한다.

CLI:

```bash
# bastion, VLAN 40에서 Internal API 접근
# HTTP 응답 확인
curl -k --connect-timeout 3 https://172.16.23.5:6443/healthz

# bastion에서 Ingress VIP 접근
# HTTP 응답 확인
curl -k -I https://172.16.23.50

# 허용되지 않아야 하는 포트 예시
# 포트 연결 확인
nc -vz -w 3 172.16.23.20 22
nc -vz -w 3 172.16.22.10 80
```

GUI:

- pfSense UI: `Firewall > Rules`에서 VLAN별 룰 확인
- pfSense UI: `Status > System Logs > Firewall`에서 pass/block 로그 확인

성공 기준:

- 운영에 필요한 API, Ingress, DNS 경로는 허용된다.
- 문서상 차단해야 하는 방향/포트는 실패한다.
- pfSense 로그에서 어떤 룰에 의해 허용/차단됐는지 확인 가능하다.

### 2.3 DNS Host Override 검증

목적: 내부 도메인이 Ingress 또는 의도한 엔드포인트로 일관되게 해석되는지 확인한다.

CLI:

```bash
# bastion
# 여러 대상 반복 확인
for h in harbor jenkins grafana argocd ticket; do
  echo "=== $h.kosa.team2 ==="
# DNS 해석 확인
  dig +short $h.kosa.team2
done

# 테스트 Pod 생성
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup harbor.kosa.team2
```

GUI:

- pfSense UI: `Services > DNS Resolver > Host Overrides`
- K8s CoreDNS 확인:

```bash
# bastion
kubectl -n kube-system get configmap coredns -o yaml
```

성공 기준:

- `harbor`, `jenkins`, `grafana`, `argocd`, `ticket`이 의도한 IP를 반환한다.
- Pod 내부에서도 동일 도메인 해석이 가능하다.

## 3. Proxmox / VM 배치 / Cloud-init

### 3.1 Proxmox 4노드 클러스터 정상성

목적: Proxmox 4대가 quorum을 유지하고 VM이 anti-affinity 원칙대로 분산되어 있는지 확인한다.

CLI:

```bash
# bastion 또는 관리 노트북에서 Proxmox host SSH
# 여러 대상 반복 확인
for h in 192.168.21.2 192.168.21.3 192.168.21.4 192.168.21.5; do
  echo "=== $h ==="
# 원격 노드에서 확인
  ssh -o ConnectTimeout=3 root@$h "hostname; pvecm status | grep -E 'Quorate|Nodes|Votequorum'"
done
```

```bash
# Proxmox host 중 하나
# Proxmox VM 확인
qm list
# Proxmox 클러스터 확인
pvecm nodes
```

GUI:

- Proxmox UI: `Datacenter > Cluster`
- Proxmox UI: 각 노드 선택 후 VM 목록 확인

성공 기준:

- `Quorate: Yes`
- pfSense Primary/Secondary가 서로 다른 Proxmox 노드에 있다.
- K8s CP 3대가 같은 호스트에 몰려 있지 않다.
- lb-1/lb-2, edge-1/edge-2가 분산되어 있다.

### 3.2 Proxmox 호스트 장애 영향 검증

목적: 단일 Proxmox 호스트 장애 시 어떤 서비스가 유지되고 어떤 VM이 영향받는지 확인한다.

사전 확인:

```bash
# Proxmox host
# Proxmox VM 확인
qm list
```

테스트 방법:

1. Proxmox UI에서 장애 대상 노드의 VM 목록 확인
2. 영향이 작은 노드를 선정
3. 노드 자체 shutdown 대신 먼저 해당 노드의 비핵심 VM 1대만 shutdown하여 영향 확인
4. 필요 시 담당자 합의 후 노드 shutdown 수행

검증 CLI:

```bash
# bastion
# K8s 노드 상태 확인
kubectl get nodes
# Pod 상태 확인
kubectl get pods -A | grep -E 'Running|Pending|Unknown|CrashLoop'
# HTTP 응답 확인
curl -k -i https://ticket.kosa.team2/healthz
```

성공 기준:

- 단일 호스트 장애로 전체 서비스가 즉시 중단되지 않는다.
- 로컬 디스크 VM은 자동 이동되지 않으므로 영향 범위가 명확히 기록된다.

원복:

- Proxmox UI에서 노드 전원 복구
- 중지된 VM `Start`
- K8s 노드가 `Ready`로 복귀하는지 확인

### 3.3 Cloud-init / qemu-guest-agent 검증

목적: VM clone 시 hostname, IP, SSH key, DNS가 자동 적용되고 qemu-guest-agent가 동작하는지 확인한다.

VM 내부 CLI:

```bash
# 대상 VM
# 호스트명 확인
hostnamectl
# IP 설정 확인
ip addr
# 파일 내용 확인
cat /etc/netplan/*.yaml
# 서비스 상태 확인
systemctl is-active qemu-guest-agent
# cloud-init 상태 확인
cloud-init status --long
```

Proxmox host CLI:

```bash
# Proxmox host
# Proxmox VM 확인
qm list
# VM 내부 NIC 정보 확인
qm agent <VMID> network-get-interfaces
```

GUI:

- Proxmox UI: VM 선택 > `Summary`에서 IP 표시 확인
- Proxmox UI: VM 선택 > `Cloud-Init` 탭에서 IP, DNS, SSH key 확인

성공 기준:

- `cloud-init status`가 `done`
- `qemu-guest-agent`가 `active`
- Proxmox UI에서 VM IP가 보인다.

## 4. Bastion / 운영 진입점

### 4.1 bastion 운영 도구 검증

목적: bastion 하나로 대부분의 운영/검증 명령을 수행할 수 있는지 확인한다.

CLI:

```bash
# bastion
# 필수 CLI 설치 확인
for c in kubectl helm argocd aws docker k6 redis-cli jq curl dig nc; do
  echo "=== $c ==="
  command -v $c || echo "MISSING"
done

# kubeconfig API 서버 확인
kubectl config view --minify | grep server
# K8s 노드 상태 확인
kubectl get nodes -o wide
```

SSH 확인:

```bash
# bastion
# 여러 대상 반복 확인
for h in 172.16.23.10 172.16.23.11 172.16.23.12 172.16.23.20 172.16.23.21 172.16.23.22 172.16.23.23 172.16.22.10 172.16.22.11; do
  echo -n "$h: "
# 원격 노드에서 확인
  ssh -o BatchMode=yes -o ConnectTimeout=3 ubuntu@$h "hostname" 2>&1 | tail -1
done
```

성공 기준:

- 필수 CLI가 설치되어 있다.
- kubeconfig server가 `https://172.16.23.5:6443`이다.
- 주요 노드에 SSH 접속 가능하다.

## 5. Kubernetes Control Plane / API LB

### 5.1 API VIP 이중화 검증

목적: lb-1 장애 시 lb-2가 API VIP `172.16.23.5`를 인수하는지 확인한다.

사전 확인:

```bash
# bastion
# HTTP 응답 확인
curl -k https://172.16.23.5:6443/healthz
# 원격 노드에서 확인
ssh ubuntu@172.16.23.6 "ip addr | grep 172.16.23.5; systemctl is-active keepalived haproxy"
ssh ubuntu@172.16.23.7 "ip addr | grep 172.16.23.5; systemctl is-active keepalived haproxy"
```

장애 유도:

```bash
# bastion
# 원격 노드에서 확인
ssh ubuntu@172.16.23.6 "sudo systemctl stop keepalived"
```

전환 확인:

```bash
# bastion
# 원격 노드에서 확인
ssh ubuntu@172.16.23.7 "ip addr | grep 172.16.23.5"
# K8s 노드 상태 확인
kubectl get nodes
# HTTP 응답 확인
curl -k https://172.16.23.5:6443/healthz
```

성공 기준:

- VIP가 lb-2에 표시된다.
- `kubectl get nodes`가 계속 성공한다.

원복:

```bash
# bastion
# 원격 노드에서 확인
ssh ubuntu@172.16.23.6 "sudo systemctl start keepalived"
ssh ubuntu@172.16.23.6 "systemctl is-active keepalived"
```

### 5.2 Control Plane 1대 장애 검증

목적: CP 1대 장애에도 API와 etcd quorum이 유지되는지 확인한다.

사전 확인:

```bash
# bastion
# K8s 노드 상태 확인
kubectl get nodes -o wide
# 여러 대상 반복 확인
for cp in 172.16.23.10 172.16.23.11 172.16.23.12; do
  echo "=== $cp ==="
# HTTP 응답 확인
  curl -k --connect-timeout 3 https://$cp:6443/healthz
done
```

etcd 확인:

```bash
# CP 노드 중 하나
sudo ETCDCTL_API=3 etcdctl \
  --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster
```

장애 유도:

```bash
# bastion, 예: cp2 kubelet 중지
# 원격 노드에서 확인
ssh ubuntu@172.16.23.11 "sudo systemctl stop kubelet"
```

검증:

```bash
# bastion
# K8s 노드 상태 확인
kubectl get nodes
# 테스트 Pod 생성
kubectl run cp-test --image=nginx --restart=Never
# Pod 상태 확인
kubectl get pod cp-test -o wide
# 리소스 삭제/장애 유도
kubectl delete pod cp-test
# ArgoCD 앱 상태 확인
kubectl get applications -n argocd
```

성공 기준:

- API VIP는 계속 응답한다.
- 신규 Pod 생성이 가능하다.
- etcd quorum이 유지된다.

원복:

```bash
# bastion
# 원격 노드에서 확인
ssh ubuntu@172.16.23.11 "sudo systemctl start kubelet"
# K8s 노드 상태 확인
kubectl get nodes
```

### 5.3 Worker 노드 장애 검증

목적: worker 장애 시 ticket-app Pod가 다른 production worker로 재스케줄링되는지 확인한다.

사전 확인:

```bash
# bastion
# Pod 상태 확인
kubectl get pod -n kosa-tickets -o wide
# K8s 노드 상태 확인
kubectl get nodes --show-labels | grep workload-type
```

장애 유도, 권장 방식:

```bash
# bastion, 예: k8s-w1
# 노드 비우기
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data
```

검증:

```bash
# bastion
# Pod 상태 확인
kubectl get pod -n kosa-tickets -o wide -w
# Service 연결 대상 확인
kubectl get endpoints -n kosa-tickets ticket-app
# HTTP 응답 확인
curl -k -i https://ticket.kosa.team2/healthz
```

성공 기준:

- ticket-app replica가 다른 worker에서 `Running`
- Service Endpoint가 새 Pod IP로 갱신
- 사용자 요청이 복구

원복:

```bash
# bastion
# 노드 스케줄링 복구
kubectl uncordon <NODE_NAME>
# K8s 노드 상태 확인
kubectl get nodes
```

## 6. Calico / MetalLB / Ingress

### 6.1 Calico Pod 네트워크 검증

목적: 서로 다른 노드의 Pod 간 통신과 Calico 상태를 확인한다.

CLI:

```bash
# bastion
# Pod 상태 확인
kubectl get pods -n calico-system -o wide
kubectl get ippool -o wide 2>/dev/null || true

# 테스트 Pod 생성
kubectl run net-a --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl run net-b --image=busybox:1.36 --restart=Never -- sleep 3600
# Pod 상태 확인
kubectl get pod net-a net-b -o wide
# Pod 내부 명령 실행
kubectl exec net-a -- ping -c 3 $(kubectl get pod net-b -o jsonpath='{.status.podIP}')
# 리소스 삭제/장애 유도
kubectl delete pod net-a net-b
```

성공 기준:

- Calico Pod가 `Running`
- Pod 간 ping 성공
- Pod CIDR이 `192.168.21.0/24`와 겹치지 않음

### 6.2 MetalLB L2 Failover 검증

목적: Ingress LoadBalancer IP `172.16.23.50` 광고 노드 장애 시 다른 노드가 IP를 인수하는지 확인한다.

사전 확인:

```bash
# bastion
# Service 상태 확인
kubectl get svc -A | grep 172.16.23.50
# Pod 상태 확인
kubectl get pods -n metallb-system -o wide
# ARP 응답 확인
arp -an | grep 172.16.23.50 || true
arping -I eth0 -c 3 172.16.23.50 || true
```

참고: MetalLB L2 모드는 `172.16.23.50`을 노드 NIC에 secondary IP로 붙이지 않고 ARP 응답만 한다. 따라서 `ip addr | grep 172.16.23.50`로 진단하지 말고 `arping` 또는 실제 `curl`로 확인한다.

광고 노드 찾기:

```bash
# bastion
# 로그 확인
kubectl logs -n metallb-system -l component=speaker --tail=200 | grep 172.16.23.50
```

장애 유도:

```bash
# bastion, speaker Pod 1개 삭제
# 리소스 삭제/장애 유도
kubectl delete pod -n metallb-system <SPEAKER_POD_NAME>
```

검증:

```bash
# bastion
# Pod 상태 확인
kubectl get pods -n metallb-system -o wide
# HTTP 응답 확인
curl -k -i https://ticket.kosa.team2/healthz
```

성공 기준:

- speaker Pod가 재생성된다.
- `172.16.23.50` 접근이 복구된다.

복구가 안 될 때:

```bash
# bastion
# rollout 진행 확인
kubectl rollout restart ds -n metallb-system metallb-speaker

# edge-haproxy / edge-haproxy2
# 서비스 제어
sudo systemctl restart haproxy
```

### 6.3 HAProxy Ingress 라우팅 검증

목적: 단일 Ingress VIP에서 Host 기반 라우팅이 정상 동작하는지 확인한다.

CLI:

```bash
# bastion
# 여러 대상 반복 확인
for h in ticket grafana harbor argocd jenkins; do
  echo "=== $h.kosa.team2 ==="
# HTTP 응답 확인
  curl -k -I https://$h.kosa.team2
done

# Ingress 상태 확인
kubectl get ingress -A
# 상세 설정/이벤트 확인
kubectl describe ingress -A
```

잘못된 Host 헤더 테스트:

```bash
# bastion
# HTTP 응답 확인
curl -k -I https://172.16.23.50 -H "Host: wrong.kosa.team2"
```

성공 기준:

- 각 도메인이 의도한 서비스로 라우팅된다.
- 잘못된 Host는 기본 backend 또는 404/503 등 의도된 응답을 반환한다.

## 7. Edge HAProxy / 이중 TLS / PKI

### 7.1 Edge HAProxy HA 검증

목적: Active Edge HAProxy 장애 시 Backup이 VIP와 트래픽을 인수하는지 확인한다.

사전 확인:

```bash
# bastion
# 원격 노드에서 확인
ssh ubuntu@172.16.22.10 "ip addr | grep 172.16.22.5; systemctl is-active keepalived haproxy"
ssh ubuntu@172.16.22.11 "ip addr | grep 172.16.22.5; systemctl is-active keepalived haproxy"
# HTTP 응답 확인
curl -k -I https://ticket.kosa.team2
```

장애 유도:

```bash
# bastion, Active Edge에서 keepalived 중지
# 원격 노드에서 확인
ssh ubuntu@172.16.22.10 "sudo systemctl stop keepalived"
```

검증:

```bash
# bastion
# 원격 노드에서 확인
ssh ubuntu@172.16.22.11 "ip addr | grep 172.16.22.5"
# HTTP 응답 확인
curl -k -I https://ticket.kosa.team2
```

성공 기준:

- VIP가 Backup Edge에 표시된다.
- 외부 HTTPS 요청이 계속 Ingress까지 전달된다.

원복:

```bash
# bastion
# 원격 노드에서 확인
ssh ubuntu@172.16.22.10 "sudo systemctl start keepalived"
```

### 7.2 이중 TLS 검증

목적: Client -> Edge, Edge -> K8s Ingress 양쪽 TLS 인증서가 유효한지 확인한다.

Client -> Edge:

```bash
# bastion
# 인증서 정보 확인
openssl s_client -connect ticket.kosa.team2:443 -servername ticket.kosa.team2 </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

Edge -> Ingress:

```bash
# edge-1 또는 bastion에서 라우팅 가능 시
# 인증서 정보 확인
openssl s_client -connect 172.16.23.50:443 -servername ticket.kosa.team2 </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

K8s Secret 확인:

```bash
# bastion
# 인증서 리소스 확인
kubectl get certificates -A
# Secret 확인
kubectl get secret -n kosa-tickets ticket-tls -o yaml
```

성공 기준:

- Edge wildcard 인증서와 Ingress 인증서가 모두 내부 CA로 서명되어 있다.
- 만료일이 유효하다.

### 7.3 cert-manager 자동 발급 검증

목적: 새 Ingress/Certificate 생성 시 cert-manager가 자동으로 TLS Secret을 만드는지 확인한다.

테스트 리소스 생성:

```bash
# bastion
kubectl create ns cert-test
kubectl -n cert-test create deployment nginx --image=nginx
kubectl -n cert-test expose deployment nginx --port=80
# YAML/설정 입력
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cert-test
  namespace: cert-test
  annotations:
    kubernetes.io/ingress.class: haproxy
    cert-manager.io/cluster-issuer: kosa-ca-issuer
spec:
  ingressClassName: haproxy
  tls:
    - hosts:
        - cert-test.kosa.team2
      secretName: cert-test-tls
  rules:
    - host: cert-test.kosa.team2
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
EOF
```

검증:

```bash
# bastion
# 인증서 리소스 확인
kubectl get certificate,secret,ingress -n cert-test
# 상세 설정/이벤트 확인
kubectl describe certificate -n cert-test
```

성공 기준:

- `cert-test-tls` Secret이 생성된다.
- Certificate 상태가 `Ready=True`

원복:

```bash
# bastion
# 리소스 삭제/장애 유도
kubectl delete ns cert-test
```

## 8. Ceph / 10G Storage / CSI

### 8.1 Ceph 클러스터 정상성 검증

목적: MON, MGR, OSD, RGW 상태를 확인한다.

CLI:

```bash
# Ceph node
# Ceph 전체 상태 확인
ceph -s
# Ceph 상태 확인
ceph osd tree
ceph quorum_status --format json-pretty
# Ceph 상태 확인
ceph orch ps
# HTTP 응답 확인
curl -I http://10.10.10.11:7480
```

성공 기준:

- MON quorum 유지
- OSD 6개가 `up/in`
- MGR active/standby 확인
- RGW가 HTTP 응답

### 8.2 OSD 1개 장애 검증

목적: OSD 1개 장애에도 3-replica pool이 read/write를 유지하는지 확인한다.

사전 확인:

```bash
# Ceph node
# Ceph 전체 상태 확인
ceph -s
# Ceph 상태 확인
ceph osd tree
ceph osd pool ls detail | grep team2-k8s-pvc-rbd
```

OSD 중지:

```bash
# Ceph node, 예: osd.1
# Ceph 상태 확인
ceph osd tree
ceph orch daemon stop osd.1
```

상태 확인:

```bash
# Ceph node
# Ceph 전체 상태 확인
ceph -s
# Ceph 상태 확인
ceph health detail
```

K8s PVC read/write 확인:

```bash
# bastion
# 테스트 Pod 생성
kubectl run ceph-rw-test --image=busybox:1.36 --restart=Never -- sleep 3600
# Pod 내부 명령 실행
kubectl exec ceph-rw-test -- sh -c 'date > /tmp/osd-test.txt && cat /tmp/osd-test.txt'
# 리소스 삭제/장애 유도
kubectl delete pod ceph-rw-test
```

성공 기준:

- Ceph는 degraded 또는 recovery 상태를 표시하지만 cluster가 멈추지 않는다.
- 기존 PVC 사용 Pod의 read/write가 가능하다.

원복:

```bash
# Ceph node
# Ceph 상태 확인
ceph orch daemon start osd.1
# Ceph 전체 상태 확인
ceph -s
```

### 8.3 MON 1대 장애 검증

목적: MON 1대 장애에도 quorum이 유지되는지 확인한다.

사전 확인:

```bash
# Ceph node
# Ceph 상태 확인
ceph quorum_status --format json-pretty
ceph orch ps --daemon-type mon
```

MON 중지:

```bash
# Ceph node, 예: ceph3의 mon
# Ceph 상태 확인
ceph orch daemon stop mon.ceph3
```

검증:

```bash
# Ceph node
# Ceph 전체 상태 확인
ceph -s
# Ceph 상태 확인
ceph quorum_status --format json-pretty
```

성공 기준:

- 남은 MON 2대가 quorum을 유지한다.
- `ceph -s` 명령이 계속 동작한다.

원복:

```bash
# Ceph node
# Ceph 상태 확인
ceph orch daemon start mon.ceph3
# Ceph 전체 상태 확인
ceph -s
```

### 8.4 Ceph CSI / PVC 동적 프로비저닝 검증

목적: K8s PVC 생성 시 `team2-rbd-block` StorageClass로 RBD PV가 자동 생성되고, Pod 재생성 후에도 데이터가 유지되는지 확인한다.

참고: StorageClass 이름은 환경에 따라 `team2-rbd-block`으로 보일 수 있지만, 실제 Ceph pool은 `team2-k8s-pvc-rbd`가 기준이다. 테스트 전에 `kubectl get sc -o yaml | grep pool`로 실제 매핑을 확인한다.

사전 확인:

```bash
# bastion
# StorageClass 목록 확인
kubectl get storageclass
# StorageClass 확인
kubectl get sc -o yaml | grep -E 'name:|pool:'
# Pod 상태 확인
kubectl get pods -n ceph-csi-rbd -o wide
```

성공 기준:

- `team2-rbd-block` StorageClass가 보인다.
- ceph-csi provisioner와 nodeplugin Pod가 `Running`이다.

1단계: 테스트 namespace 생성

```bash
# bastion
# 테스트 namespace 생성
kubectl create namespace pvc-test
```

2단계: PVC 생성

```bash
# bastion
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rbd-test-pvc
  namespace: pvc-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: team2-rbd-block
  resources:
    requests:
      storage: 1Gi
EOF
```

3단계: PVC/PV 바인딩 확인

```bash
# bastion
# PVC/PV 상태 확인
kubectl get pvc,pv -n pvc-test
# 상세 설정/이벤트 확인
kubectl describe pvc -n pvc-test rbd-test-pvc
```

성공 기준:

- PVC 상태가 `Bound`
- PV가 자동 생성됨
- `StorageClass`가 `team2-rbd-block`

Ceph 쪽 확인:

```bash
# Ceph node
# RBD 이미지 확인
rbd ls team2-k8s-pvc-rbd
```

4단계: 테스트 Pod 생성 후 파일 쓰기

```bash
# bastion
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: rbd-writer
  namespace: pvc-test
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: rbd-test-pvc
EOF

# Ready 상태 대기
kubectl wait --for=condition=Ready pod/rbd-writer -n pvc-test --timeout=120s
# Pod 내부 명령 실행
kubectl exec -n pvc-test rbd-writer -- sh -c 'echo "ceph-csi-test-$(date +%s)" > /data/test.txt'
kubectl exec -n pvc-test rbd-writer -- cat /data/test.txt
```

성공 기준:

- Pod가 `Running`
- `/data/test.txt` 파일이 정상 생성되고 읽힌다.

5단계: Pod 삭제 후 재생성하여 데이터 유지 확인

```bash
# bastion
# 리소스 삭제/장애 유도
kubectl delete pod -n pvc-test rbd-writer
# YAML/설정 입력
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rbd-reader
  namespace: pvc-test
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: rbd-test-pvc
EOF

# Ready 상태 대기
kubectl wait --for=condition=Ready pod/rbd-reader -n pvc-test --timeout=120s
# Pod 내부 명령 실행
kubectl exec -n pvc-test rbd-reader -- cat /data/test.txt
```

성공 기준:

- 새 Pod에서도 기존 `test.txt` 내용이 그대로 출력된다.
- Pod 삭제/재생성과 무관하게 PVC 데이터가 유지된다.

GUI 확인:

- Grafana: `Kubernetes / Persistent Volumes` 대시보드에서 PVC 사용량 확인
- Ceph Dashboard: RBD image 또는 pool 사용량 확인

원복:

```bash
# bastion
# 리소스 삭제/장애 유도
kubectl delete namespace pvc-test

# Ceph node, 삭제 확인
# RBD 이미지 확인
rbd ls team2-k8s-pvc-rbd
```

### 8.5 10G 패브릭 성능 검증

목적: Proxmox/Ceph 노드 간 10G 네트워크 성능을 확인한다.

서버 실행:

```bash
# ceph1
# 네트워크 성능 측정
iperf3 -s
```

클라이언트 실행:

```bash
# ceph2 또는 Proxmox host
# 네트워크 성능 측정
iperf3 -c 10.10.10.11 -P 4 -t 30
```

여러 구간 반복:

```bash
# bastion에서 SSH 가능할 때
# 여러 대상 반복 확인
for h in 10.10.10.12 10.10.10.13 10.10.10.14 10.10.10.15 10.10.10.16; do
  echo "=== $h -> ceph1 ==="
# 원격 노드에서 확인
  ssh root@$h "iperf3 -c 10.10.10.11 -P 4 -t 10"
done
```

성공 기준:

- 1G 관리망보다 충분히 높은 처리량이 나온다.
- 특정 구간만 낮으면 케이블, SFP, leaf/spine uplink를 점검한다.

## 9. Harbor / Ceph RGW Registry

### 9.1 Harbor 기본 동작 검증

목적: Harbor UI, registry push/pull, Ceph RGW bucket 저장을 확인한다.

CLI:

```bash
# bastion
# Pod 상태 확인
kubectl get pods,pvc,svc,ingress -n harbor
# HTTP 응답 확인
curl -k -I https://harbor.kosa.team2
# Harbor 로그인 확인
docker login harbor.kosa.team2 -u admin
# 이미지 pull 확인
docker pull nginx:latest
# 이미지 태그 지정
docker tag nginx:latest harbor.kosa.team2/library/nginx:validation
# 이미지 push 확인
docker push harbor.kosa.team2/library/nginx:validation
# 이미지 pull 확인
docker pull harbor.kosa.team2/library/nginx:validation
```

RGW 확인:

```bash
# bastion 또는 Ceph node, AWS CLI 설정 필요
AWS_ACCESS_KEY_ID=<ACCESS_KEY> AWS_SECRET_ACCESS_KEY=<SECRET_KEY> \
# S3/RGW 확인
aws --endpoint-url http://10.10.10.11:7480 --region us-east-1 \
  s3 ls s3://harbor-registry --recursive | head
```

GUI:

- Browser: `https://harbor.kosa.team2`
- Harbor UI: `Projects > library > Repositories > nginx`

성공 기준:

- Docker login/push/pull 성공
- Harbor UI에 `nginx:validation` 태그가 보임
- RGW bucket에 object가 존재

### 9.2 RGW 장애 영향 검증

목적: RGW 1대 구성의 SPoF 영향을 확인한다.

사전 확인:

```bash
# bastion
# 이미지 pull 확인
docker pull harbor.kosa.team2/library/nginx:validation
```

장애 유도:

```bash
# Ceph node
# Ceph 상태 확인
ceph orch ps --daemon-type rgw
ceph orch daemon stop rgw.<DAEMON_NAME>
```

검증:

```bash
# bastion
# 이미지 pull 확인
docker pull harbor.kosa.team2/library/nginx:validation
# 이미지 push 확인
docker push harbor.kosa.team2/library/nginx:validation-rgw-down
```

성공 기준:

- RGW 중지 중 push/pull이 실패하거나 지연된다.
- Harbor UI 일부 기능은 열려도 이미지 blob 접근은 실패할 수 있다.

원복:

```bash
# Ceph node
# Ceph 상태 확인
ceph orch daemon start rgw.<DAEMON_NAME>

# bastion
# 이미지 pull 확인
docker pull harbor.kosa.team2/library/nginx:validation
```

## 10. Jenkins / Kaniko / CI

### 10.1 Jenkins Controller 검증

목적: Jenkins UI, Pod, PVC, 설정 보존을 확인한다.

CLI:

```bash
# bastion
# Pod 상태 확인
kubectl get pods,pvc,svc,ingress -n jenkins
# HTTP 응답 확인
curl -k -I https://jenkins.kosa.team2
```

GUI:

- Browser: `https://jenkins.kosa.team2`
- Jenkins UI: `Manage Jenkins > System`
- Jenkins UI: `Build History`, `Credentials`

Controller 재시작:

```bash
# bastion
# 리소스 삭제/장애 유도
kubectl delete pod -n jenkins -l app.kubernetes.io/component=jenkins-controller
# Pod 상태 확인
kubectl get pods -n jenkins -w
```

성공 기준:

- 재시작 후 Job, credential, plugin 설정이 유지된다.

### 10.2 Kaniko 기반 이미지 빌드 검증

목적: Jenkins가 K8s agent Pod를 생성하고 Kaniko로 Harbor에 이미지를 push한 뒤 GitOps repo를 갱신하는지 확인한다.

GUI:

1. Jenkins UI 접속
2. ticket-app 또는 kosa-tickets Job 선택
3. `Build Now` 클릭
4. `Console Output` 확인

CLI 모니터링:

```bash
# bastion
# Pod 상태 확인
kubectl get pods -n jenkins -w
# 로그 확인
kubectl logs -n jenkins <AGENT_POD_NAME> -c kaniko --tail=100
kubectl logs -n jenkins <AGENT_POD_NAME> -c git --tail=100
```

결과 확인:

```bash
# bastion
# 이미지 pull 확인
docker pull harbor.kosa.team2/library/kosa-tickets:<BUILD_NUMBER>
kubectl get deployment -n kosa-tickets ticket-app -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
# ArgoCD 앱 상태 확인
kubectl get applications -n argocd ticket-app
```

성공 기준:

- Jenkins build 성공
- Harbor에 새 이미지 태그 생성
- GitOps repo의 image tag 갱신
- ArgoCD가 배포 반영

### 10.3 CI 실패 시나리오 검증

목적: 빌드 실패 시 GitOps 배포 단계로 넘어가지 않는지 확인한다.

테스트 방법:

1. 테스트 브랜치에서 Dockerfile 또는 테스트 코드를 의도적으로 실패하게 변경
2. Jenkins Job을 해당 브랜치로 실행
3. Jenkins Console Output 확인

검증:

```bash
# bastion
kubectl get deployment -n kosa-tickets ticket-app -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
# ArgoCD 앱 상태 확인
kubectl get applications -n argocd ticket-app
```

성공 기준:

- Jenkins build가 실패 상태로 표시된다.
- Harbor에 실패 빌드 이미지가 push되지 않는다.
- GitOps repo image tag가 변경되지 않는다.

## 11. ArgoCD / GitOps

### 11.1 App-of-Apps 상태 검증

목적: root-app과 하위 Application이 Git 선언 상태와 일치하는지 확인한다.

CLI:

```bash
# bastion
# ArgoCD 앱 상태 확인
kubectl get applications -n argocd -o wide
# 상세 설정/이벤트 확인
kubectl describe application -n argocd root-app
kubectl describe application -n argocd ticket-app
```

GUI:

- Browser: `https://argocd.kosa.team2`
- ArgoCD UI: root-app 선택 후 하위 Application 상태 확인

성공 기준:

- 주요 Application이 `Synced`와 `Healthy`
- Degraded 또는 OutOfSync가 있으면 원인이 설명 가능

### 11.2 Self-heal 검증

목적: 수동 변경 drift를 ArgoCD가 Git 상태로 되돌리는지 확인한다.

사전 확인:

```bash
# bastion
kubectl get deploy -n kosa-tickets ticket-app
```

수동 drift 생성:

```bash
# bastion
# replica 수 변경
kubectl scale deployment -n kosa-tickets ticket-app --replicas=1
kubectl get deploy -n kosa-tickets ticket-app
```

복구 확인:

```bash
# bastion
# 주기적 모니터링
watch -n 3 'kubectl get deploy -n kosa-tickets ticket-app; kubectl get application -n argocd ticket-app'
```

GUI:

- ArgoCD UI: ticket-app Application의 sync event 확인

성공 기준:

- 잠시 후 replica 수가 Git manifest 값으로 복구된다.
- ArgoCD Application event에 self-heal 기록이 남는다.

### 11.3 Git commit 기반 배포 검증

목적: GitOps repo 변경만으로 배포가 이루어지는지 확인한다.

테스트 방법:

```bash
# bastion
# 작업 디렉터리 이동
cd ~/kosa-gitops
git pull
# 설정 값 검색
grep -n "image:" apps/ticket-app/deployment.yaml
```

1. image tag를 테스트 가능한 기존 태그로 변경
2. commit/push
3. ArgoCD sync 확인

```bash
# bastion
# ArgoCD 앱 상태 확인
kubectl get application -n argocd ticket-app -w
# rollout 진행 확인
kubectl rollout status deployment -n kosa-tickets ticket-app
# Pod 상태 확인
kubectl get pod -n kosa-tickets -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}'
```

성공 기준:

- 수동 `kubectl apply` 없이 Deployment image가 변경된다.

## 12. PXC / ProxySQL / 데이터베이스

현재 `CLAUDE.md` 기준으로 PXC + ProxySQL HA는 선택/추가 구축 항목이며, 현재 데모 앱은 in-memory 동작으로 정리되어 있다. 아래 테스트는 `pii-protected` namespace의 PXC가 실제 배포되어 있을 때 수행한다. 먼저 사전 확인에서 리소스가 없으면 이 섹션은 `SKIP`으로 기록한다.

### 12.1 PXC 클러스터 정상성 검증

목적: PXC cluster size, status, ready 상태를 확인한다.

CLI:

```bash
# bastion
# Pod 상태 확인
kubectl get pods,svc,pvc -n pii-protected
kubectl get pxc -n pii-protected 2>/dev/null || true
# Pod 내부 명령 실행
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "SHOW STATUS LIKE 'wsrep_cluster_status';"
# Pod 내부 명령 실행
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "SHOW STATUS LIKE 'wsrep_ready';"
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "SHOW DATABASES;"
```

성공 기준:

- `wsrep_cluster_status`가 `Primary`
- `wsrep_ready`가 `ON`
- cluster size가 기대 replica 수와 일치

### 12.2 PXC Pod 장애 검증

목적: PXC Pod 1개 장애에도 DB와 ticket-app 기능이 유지되는지 확인한다.

사전 확인:

```bash
# bastion
# Pod 상태 확인
kubectl get pods -n pii-protected -o wide
```

장애 유도:

```bash
# bastion
# 리소스 삭제/장애 유도
kubectl delete pod -n pii-protected kosa-pxc-pxc-1
```

검증:

```bash
# bastion
# Pod 상태 확인
kubectl get pods -n pii-protected -w
# Pod 내부 명령 실행
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
# HTTP 응답 확인
curl -k -i https://ticket.kosa.team2/healthz
```

성공 기준:

- 삭제된 Pod가 재생성된다.
- cluster size가 복구된다.
- ticket-app 기능이 유지된다.

### 12.3 DB 데이터 보존 검증

목적: 앱/DB Pod 재시작 후에도 데이터가 보존되는지 확인한다.

테스트 데이터 생성:

```bash
# bastion
# Pod 내부 명령 실행
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "
CREATE DATABASE IF NOT EXISTS validation;
CREATE TABLE IF NOT EXISTS validation.persistence_test (id INT PRIMARY KEY, note VARCHAR(100));
REPLACE INTO validation.persistence_test VALUES (1, 'before-restart');
SELECT * FROM validation.persistence_test;"
```

Pod 재시작:

```bash
# bastion
# 리소스 삭제/장애 유도
kubectl delete pod -n kosa-tickets -l app=ticket-app
kubectl delete pod -n pii-protected kosa-pxc-pxc-1
```

검증:

```bash
# bastion
# Pod 내부 명령 실행
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "SELECT * FROM validation.persistence_test;"
```

성공 기준:

- `before-restart` 데이터가 유지된다.

원복:

```bash
# bastion
# Pod 내부 명령 실행
kubectl exec -n pii-protected kosa-pxc-pxc-0 -- mysql -uroot -pkosa1004 -e "DROP DATABASE validation;"
```

## 13. Redis Sentinel

### 13.1 Redis HA 상태 검증

목적: Redis master/replica/sentinel 역할을 확인한다.

CLI:

```bash
# bastion
# Pod 상태 확인
kubectl get pods,svc,pvc -n redis -o wide
# Pod 내부 명령 실행
kubectl exec -n redis kosa-redis-node-0 -c sentinel -- \
  redis-cli -p 26379 -a kosa1004 sentinel get-master-addr-by-name mymaster
# Pod 내부 명령 실행
kubectl exec -n redis kosa-redis-node-0 -c sentinel -- \
  redis-cli -p 26379 -a kosa1004 sentinel ckquorum mymaster
# Pod 내부 명령 실행
kubectl exec -n redis kosa-redis-node-0 -c redis -- \
  redis-cli -a kosa1004 INFO replication | grep -E 'role|connected_slaves|master_host'
```

성공 기준:

- Redis StatefulSet은 `kosa-redis-node-*` 3개가 기준이다.
- Sentinel `ckquorum mymaster`가 `OK 3 usable Sentinels`를 반환한다.
- Sentinel이 현재 master 주소를 반환한다.

### 13.2 Redis master 장애 검증

목적: master 장애 시 Sentinel이 failover를 수행하는지 확인한다.

장애 유도:

```bash
# bastion
MASTER_IP=$(kubectl exec -n redis kosa-redis-node-0 -c sentinel -- \
  redis-cli -p 26379 -a kosa1004 sentinel get-master-addr-by-name mymaster \
  | head -1 | tr -d '\r')
MASTER_POD=$(kubectl get pod -n redis -o wide --no-headers | awk -v ip="$MASTER_IP" '$6==ip {print $1}')
echo "Current Redis master pod: $MASTER_POD"
# 리소스 삭제/장애 유도
kubectl delete pod -n redis "$MASTER_POD"
```

검증:

```bash
# bastion
# Pod 상태 확인
kubectl get pods -n redis -w
# Pod 내부 명령 실행
kubectl exec -n redis kosa-redis-node-0 -c sentinel -- \
  redis-cli -p 26379 -a kosa1004 sentinel get-master-addr-by-name mymaster
# Pod 내부 명령 실행
kubectl exec -n redis kosa-redis-node-0 -c sentinel -- \
  redis-cli -p 26379 -a kosa1004 sentinel ckquorum mymaster
# Pod 내부 명령 실행
kubectl exec -n redis kosa-redis-node-0 -c redis -- redis-cli -a kosa1004 SET validation-key ok
kubectl exec -n redis kosa-redis-node-0 -c redis -- redis-cli -a kosa1004 GET validation-key
```

성공 기준:

- Sentinel master 정보가 갱신된다.
- Redis read/write가 복구된다.

## 14. Monitoring / Logging / Alert

### 14.1 Prometheus Target 검증

목적: 주요 target이 Prometheus에 의해 scrape되는지 확인한다.

CLI:

```bash
# bastion
# Pod 상태 확인
kubectl get pods,svc,pvc -n monitoring
# Prometheus API 조회
kubectl get --raw /api/v1/namespaces/monitoring/services/kube-prom-kube-prometheus-prometheus:web/proxy/api/v1/targets \
  | jq '.data.activeTargets[] | select(.health!="up") | {job: .labels.job, instance: .labels.instance, health: .health, lastError: .lastError}'
```

GUI:

- Browser: Prometheus UI 접속
- `Status > Targets` 확인

성공 기준:

- kubelet, node-exporter, apiserver, etcd, kube-proxy target이 `up`

### 14.2 Grafana 대시보드 검증

목적: 인프라/앱 상태가 Grafana에서 관찰되는지 확인한다.

GUI:

1. `https://grafana.kosa.team2` 접속
2. `Kubernetes / Compute Resources / Cluster` 확인
3. `Node Exporter / Nodes` 확인
4. `Kubernetes / Persistent Volumes` 확인
5. 부하 테스트 중 CPU, memory, network, Pod 수 변화 확인

CLI 보조:

```bash
# bastion
# 리소스 사용량 확인
kubectl top nodes
kubectl top pods -A
```

성공 기준:

- 대시보드가 데이터 없음 상태가 아니다.
- 부하/장애 시 지표 변화가 보인다.

### 14.3 Alertmanager 규칙 검증

목적: 장애 발생 시 alert firing/resolved 흐름을 확인한다.

테스트 알림 유도:

```bash
# bastion
# replica 수 변경
kubectl scale deployment -n kosa-tickets ticket-app --replicas=0
```

검증:

```bash
# bastion
# Prometheus API 조회
kubectl get --raw /api/v1/namespaces/monitoring/services/kube-prom-kube-prometheus-prometheus:web/proxy/api/v1/alerts \
  | jq '.data.alerts[] | {name: .labels.alertname, state: .state}'
```

GUI:

- Prometheus UI: `Alerts`
- Alertmanager UI: active alert 확인

원복:

```bash
# bastion
# replica 수 변경
kubectl scale deployment -n kosa-tickets ticket-app --replicas=2
# rollout 진행 확인
kubectl rollout status deployment -n kosa-tickets ticket-app
```

성공 기준:

- replica 0 상태에서 관련 alert가 firing
- 원복 후 resolved

## 15. HPA / k6 / ticket-app

### 15.1 ticket-app 기본 기능 검증

목적: ticket-app의 Pod, Service, Ingress, HPA를 확인한다. 현재 데모 앱이 in-memory 모드이면 DB 연결 검증은 제외하고, DB 연동 버전이 배포된 경우에만 DB 관련 API를 추가 확인한다.

CLI:

```bash
# bastion
# Pod 상태 확인
kubectl get pod,svc,ingress,hpa -n kosa-tickets -o wide
# HTTP 응답 확인
curl -k -i https://ticket.kosa.team2/healthz
# 로그 확인
kubectl logs -n kosa-tickets -l app=ticket-app --tail=100
```

성공 기준:

- readiness/liveness probe 통과
- `/healthz` HTTP 200
- DB 연동 버전이 아니면 DB 오류가 없어야 하고, DB 연동 버전이면 DB 기반 API가 정상 응답한다.

### 15.2 HPA Scale-out 검증

목적: k6 부하로 CPU 사용률을 높여 HPA가 replica를 늘리는지 확인한다.

사전 확인:

```bash
# bastion
# HPA 상태 확인
kubectl get hpa -n kosa-tickets
# 리소스 사용량 확인
kubectl top pods -n kosa-tickets
```

부하 실행:

```bash
# bastion
# 작업 디렉터리 이동
cd /home/ubuntu/ticket-app
# 부하 테스트 실행
k6 run -e BASE_URL=https://ticket.kosa.team2 k6-test.js
```

동시 모니터링:

```bash
# bastion, 다른 터미널
# 주기적 모니터링
watch -n 5 'kubectl get hpa,pod -n kosa-tickets; kubectl top pods -n kosa-tickets'
```

GUI:

- Grafana: Kubernetes namespace/pod CPU 대시보드 확인

성공 기준:

- HPA `TARGETS`가 CPU 사용률을 표시한다.
- replica 수가 증가한다.
- 요청 성공률이 허용 범위에 머문다.

### 15.3 Pod 장애 중 사용자 요청 유지 검증

목적: ticket-app Pod 1개 삭제 중에도 서비스가 유지되는지 확인한다.

요청 발생:

```bash
# bastion
# 반복 요청 실행
while true; do date; curl -k -s -o /dev/null -w "%{http_code}\n" https://ticket.kosa.team2/healthz; sleep 1; done
```

장애 유도:

```bash
# bastion, 다른 터미널
# 리소스 삭제/장애 유도
kubectl delete pod -n kosa-tickets -l app=ticket-app
```

검증:

```bash
# bastion
# Pod 상태 확인
kubectl get pods -n kosa-tickets -w
# Service 연결 대상 확인
kubectl get endpoints -n kosa-tickets ticket-app
```

성공 기준:

- Pod가 재생성된다.
- 반복 curl의 실패가 없거나 매우 짧다.

## 16. AWS Hybrid / Site-to-Site VPN

### 16.1 AWS 기본 경로 검증

목적: AWS NLB와 Private Subnet EC2 상태를 확인한다.

CLI:

```bash
# bastion 또는 노트북
# HTTP 응답 확인
curl -I http://kosa-tickets-nlb-091d28bb8f4ca020.elb.ap-northeast-2.amazonaws.com/healthz
```

GUI:

- AWS Console: `EC2 > Target Groups > Targets`
- AWS Console: `EC2 > Instances > Connect > Session Manager`

성공 기준:

- NLB Target이 `healthy`
- EC2는 Public IP 없이 SSM 접속 가능

### 16.2 IPsec VPN 검증

목적: 온프레와 AWS VPC 간 양방향 라우팅을 확인한다.

CLI:

```bash
# bastion
# 네트워크 연결 확인
ping -c 5 10.20.10.121
# 라우팅 경로 확인
traceroute 10.20.10.121 || tracepath 10.20.10.121
```

EC2에서:

```bash
# AWS EC2, SSM Session
# 네트워크 연결 확인
ping -c 5 172.16.24.10
# IP 설정 확인
ip route
```

GUI:

- AWS Console: `VPC > Site-to-Site VPN Connections > Tunnel details`
- pfSense UI: `Status > IPsec`
- pfSense UI: `Diagnostics > States`에서 AWS/온프레 IP 검색

성공 기준:

- 터널 최소 1개 이상 `UP`
- bastion -> EC2, EC2 -> bastion 양방향 ping 성공
- NAT bypass로 source IP가 `172.16.0.0/12`로 유지

### 16.3 VPN 장애 전환 검증

목적: 터널 1개 장애 시 나머지 터널로 통신이 유지되는지 확인한다.

장애 유도:

1. pfSense UI: `VPN > IPsec > Tunnels`
2. Tunnel 1 disable 또는 disconnect
3. Apply

검증:

```bash
# bastion
# 네트워크 연결 확인
ping -c 10 10.20.10.121
```

GUI:

- AWS Console: Tunnel 1 DOWN, Tunnel 2 UP 확인
- pfSense UI: `Status > IPsec`

성공 기준:

- 터널 1 down 중에도 터널 2로 통신 가능

원복:

1. pfSense UI에서 Tunnel 1 enable
2. `Status > IPsec`에서 재연결 확인

## 17. 운영/복구 Runbook

### 17.1 GitOps 기반 재배포 검증

목적: 이전 정상 commit으로 롤백 가능한지 확인한다.

CLI:

```bash
# bastion
# 작업 디렉터리 이동
cd ~/kosa-gitops
# 최근 commit 확인
git log --oneline -5
# 문제 commit 되돌리기
git revert <BAD_COMMIT_SHA>
# 원격 저장소 반영
git push
# ArgoCD 앱 상태 확인
kubectl get application -n argocd ticket-app -w
# rollout 진행 확인
kubectl rollout status deployment -n kosa-tickets ticket-app
```

성공 기준:

- Git revert commit이 생성된다.
- ArgoCD가 롤백 manifest를 반영한다.
- ticket-app이 정상 응답한다.

### 17.2 인증서 만료/교체 검증

목적: CA, Edge wildcard, Ingress 인증서 만료일과 교체 절차를 확인한다.

CLI:

```bash
# bastion
# 인증서 정보 확인
openssl x509 -in ~/pki/ca.crt -noout -subject -issuer -dates
openssl x509 -in ~/pki/wildcard.crt -noout -subject -issuer -dates
# 인증서 리소스 확인
kubectl get certificates -A
```

Edge 반영:

```bash
# edge-1/edge-2
# HAProxy 설정 검증
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
# 서비스 제어
sudo systemctl reload haproxy
```

성공 기준:

- 인증서 만료일이 확인된다.
- HAProxy config test 통과 후 reload 성공
- HTTPS 접속 오류 없음

### 17.3 백업/복구 최소 검증

목적: 자동 복구 가능한 구성과 별도 백업이 필요한 데이터 계층을 구분한다.

체크:

```bash
# bastion
# PVC/PV 상태 확인
kubectl get pvc -A
# Secret 확인
kubectl get secret -A | grep -E 'backup|pxc|harbor|tls'
# ArgoCD 앱 상태 확인
kubectl get applications -n argocd
```

```bash
# Ceph node
# Ceph 전체 상태 확인
ceph -s
# RBD 이미지 확인
rbd ls team2-k8s-pvc-rbd
```

확인할 질문:

- GitOps repo만 있으면 재배포 가능한가?
- PXC 데이터 백업 파일 또는 백업 Job이 있는가?
- Harbor 이미지는 RGW bucket 장애 시 복구 가능한가?
- CA private key는 안전하게 백업되어 있는가?

성공 기준:

- 코드, manifest, IaC는 Git에서 복구 가능하다.
- PXC, Harbor/RGW, PVC, CA key는 별도 백업 필요 여부가 명확히 기록된다.

## 18. 우선순위별 실행 순서

| 우선순위 | 검증 항목 |
|---|---|
| 1 | 전체 서비스 경로, bastion 도구, K8s API VIP, K8s Node/Pod 상태 |
| 2 | pfSense HA, Edge HAProxy HA, MetalLB/Ingress, DNS |
| 3 | Ceph health, CSI PVC, PXC, Redis Sentinel |
| 4 | ArgoCD self-heal, Jenkins/Kaniko/Harbor CI/CD |
| 5 | HPA/k6, Prometheus/Grafana/Alertmanager |
| 6 | Proxmox 호스트 장애, AWS VPN, 백업/복구 |

## 19. 테스트 중단 기준

아래 상황이면 즉시 장애 유도를 멈추고 원복한다.

- K8s API VIP가 1분 이상 응답하지 않음
- Ceph가 `HEALTH_ERR`로 전환되고 recovery가 진행되지 않음
- pfSense CARP 양쪽이 동시에 MASTER 또는 동시에 BACKUP
- PXC `wsrep_cluster_status`가 `Primary`가 아님
- Harbor/Jenkins/ArgoCD 중 2개 이상 핵심 운영 도구 동시 장애
