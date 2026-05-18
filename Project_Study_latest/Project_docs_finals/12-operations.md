# 12. 운영 & 백업

> **이 챕터에서 다루는 것**<br> 시스템을 만든 다음에 어떻게 살아남게 하는가. 일/주/월 단위 운영
> 루틴, 백업 전략, 노드 교체/확장 절차, K8s 업그레이드, 인증서 갱신 캘린더, 그리고 앞 11챕터의
> 트러블슈팅을 통합한 인덱스.

## 목차

1. [운영 마인드셋](#1-운영-마인드셋)
2. [일/주/월 체크리스트](#2-일주월-체크리스트)
3. [백업 전략](#3-백업-전략)
4. [노드 교체/확장](#4-노드-교체확장)
5. [K8s 업그레이드](#5-k8s-업그레이드)
6. [인증서 갱신 캘린더](#6-인증서-갱신-캘린더)
7. [SPoF 매트릭스](#7-spof-매트릭스)
8. [통합 트러블슈팅 인덱스](#8-통합-트러블슈팅-인덱스)
9. [추천 다음 단계](#9-추천-다음-단계)

---

## 1. 운영 마인드셋

### 1.1 SRE 4대 신호 (Google SRE book)

| 신호           | 무엇        | 우리 측정                          |
| -------------- | ----------- | ---------------------------------- |
| **Latency**    | 응답 시간   | Prometheus (haproxy\_\*\_duration) |
| **Traffic**    | 요청 양     | Prometheus (haproxy\_\*\_rate)     |
| **Errors**     | 실패율      | Prometheus (status=5xx)            |
| **Saturation** | 자원 사용률 | node-exporter (CPU/mem/disk)       |

### 1.2 운영의 3원칙

1. **자동화 가능한 건 자동화** (Ansible, ArgoCD, cert-manager)
2. **수동 작업은 문서화** (이 문서)
3. **장애는 학습 기회** (post-mortem → "트러블슈팅" 섹션에 추가)

### 1.3 운영자가 항상 보유해야 할 것

- bastion 접속 권한 + kubeconfig
- pfSense Web UI admin 계정
- Proxmox root 계정
- Ceph admin keyring
- 자체 CA private key (`~/pki/ca.key`) 백업
- ArgoCD/Harbor/Jenkins/Grafana admin 비번
- GitHub deploy key

---

## 2. 일/주/월 체크리스트

### 2.1 일일 (5분)

```bash
# Grafana UI 한 번 보기
open https://grafana.kosa.team2
# - Cluster overview: 노드 자원 normal?
# - Alertmanager: active alert?

# K8s 상태
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Ceph
ssh ceph1 "ceph -s"
# HEALTH_OK 인지

# ArgoCD
kubectl get applications -n argocd
# 모든 Application Synced/Healthy 인지
```

### 2.2 주간 (15분)

- **etcd 백업** 수행 (수동 또는 CronJob 확인)
- **Harbor GC**: Administration → Garbage Collection → Run Now
- **Ceph rebalance** 검사: `ceph osd df` (변동 큰지)
- **Jenkins job 정리**: 실패 빌드 cleanup, 오래된 build 자동삭제 정책 확인
- **이미지 취약점 스캔 결과**: Harbor → Vulnerabilities
- **PVC 사용량**: `kubectl get pvc -A` (80% 이상은 확장 검토)

### 2.3 월간 (1시간)

- **CA cert 만료일 확인**: `openssl x509 -in ~/pki/ca.crt -noout -enddate`
- **Wildcard cert 만료일** (1년 주기)
- **K8s 버전 확인**: 새 patch release 있나 → upgrade 계획
- **Helm chart upgrade 검토**: cert-manager, monitoring 등 minor 버전
- **백업 복원 훈련**: VM 1개를 백업에서 복원해보기 (실제로 동작?)
- **장애 대응 시뮬레이션**: K8s 워커 1대를 일부러 shutdown → 자동 복구 확인

---

## 3. 백업 전략

### 3.1 무엇을 백업하나

| 대상                         | 백업 도구                   | 보존               |
| ---------------------------- | --------------------------- | ------------------ |
| etcd snapshot                | etcdctl snapshot save       | 일 1회, 7일        |
| Ceph (인프라 자체)           | 클러스터 자체 redundancy    | (snapshot은 별도)  |
| Ceph RBD PV                  | rbd snapshot 또는 Velero    | 주 1회, 4주        |
| Harbor 메타데이터 (Postgres) | Postgres dump               | 일 1회, 7일        |
| Harbor 이미지 blob           | Ceph RGW redundancy         | (snapshot 별도)    |
| ArgoCD app spec              | git repo 자체가 백업        | 영구 (git history) |
| Jenkins config               | JCasC + plugin list git     | 영구               |
| pfSense config               | XML export                  | 주 1회             |
| 자체 CA key                  | bastion 외 별도 (USB, 금고) | 영구               |
| Proxmox VM                   | vzdump                      | 일 1회, 7일        |

### 3.2 etcd snapshot (가장 중요)

```bash
# 각 CP 노드에서 (또는 bastion에서 cron)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%F).db \
  --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert  /etc/kubernetes/pki/etcd/server.crt \
  --key   /etc/kubernetes/pki/etcd/server.key

# Ceph RBD에 dump하는 CronJob
```

### 3.3 etcd 복원 (재앙 시)

```bash
# 모든 etcd 멤버 정지
sudo systemctl stop kubelet
sudo mv /var/lib/etcd /var/lib/etcd-old

# 복원
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-2026-05-15.db \
  --data-dir /var/lib/etcd \
  --initial-cluster cp1=https://172.16.23.10:2380,... \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls https://172.16.23.10:2380 \
  --name cp1

sudo systemctl start kubelet
```

(모든 CP 동일 절차)

### 3.4 Velero (옵션)

K8s 리소스 + PV 통합 백업. 미설정 상태. 향후 추가 권장.

### 3.5 자체 CA key 백업

가장 중요. 분실 시 모든 cert 무효화 + 재발급:

- bastion `~/pki/ca.key`
- 별도 USB
- 팀 리더 PC (암호화 컨테이너)
- 보안 cloud storage

---

## 4. 노드 교체/확장

### 4.1 Proxmox 노드 추가

1. 새 하드웨어 → Proxmox 설치
2. `pvecm add 192.168.21.2` (기존 클러스터 가입)
3. 네트워크 설정 (vmbr0, vmbr1)
4. 기존 노드들과 동일 cloud-init 템플릿 사용 가능

### 4.2 K8s 워커 추가

1. cloud-init으로 VM 생성 (예: k8s-w5)
2. Ansible playbook `01-baseline.yml` 적용
3. 첫 CP에서 join 명령 생성:
   ```bash
   kubeadm token create --print-join-command
   ```
4. 새 워커에서 그 명령 실행
5. `kubectl get nodes` 확인 + 라벨 부여:
   ```bash
   kubectl label node k8s-w5 workload-type=production
   ```

### 4.3 K8s 워커 제거

1. drain:
   ```bash
   kubectl drain k8s-w5 --ignore-daemonsets --delete-emptydir-data
   ```
2. K8s에서 제거:
   ```bash
   kubectl delete node k8s-w5
   ```
3. VM에서 kubeadm reset (재사용 시):
   ```bash
   sudo kubeadm reset
   ```
4. VM 자체 삭제 (Proxmox)

### 4.4 K8s CP 교체

위험. 백업 + 천천히:

1. 새 CP 노드 준비 (예: k8s-cp4)
2. 기존 CP에서 새 join token 생성 (`--upload-certs` 옵션)
3. 새 CP join
4. etcd 멤버 확인:
   ```bash
   etcdctl member list
   # 4개 보임 (cp1, cp2, cp3, cp4)
   ```
5. 옛 CP drain → kubectl delete node → kubeadm reset
6. etcd 멤버 제거:
   ```bash
   etcdctl member remove <id>
   ```

> ⚠️ **항상 etcd 홀수 유지**: 4 CP가 일시적으로 있어도 즉시 5로 가거나 옛 1개 제거.

### 4.5 Ceph OSD 디스크 교체

1. 옛 OSD out + down:
   ```bash
   ceph osd out osd.5
   # 데이터 마이그레이션 대기 (HEALTH_OK 되면)
   ceph osd down osd.5
   ceph osd purge osd.5 --yes-i-really-mean-it
   ```
2. 물리 디스크 교체
3. 새 OSD 추가:
   ```bash
   ceph orch daemon add osd ceph5:/dev/sdb
   ```

---

## 5. K8s 업그레이드

### 5.1 원칙

- **patch 버전** (1.30.0 → 1.30.4): 자유롭게 수시
- **minor 버전** (1.30 → 1.31): 한 단계씩만, 6개월~1년 주기
- 항상 **CP 먼저 → 그 후 워커**
- 항상 **백업 + 한 노드씩**

### 5.2 절차 (예: 1.30 → 1.31)

**1단계: 첫 CP**

```bash
# apt repo 업데이트
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt update
sudo apt install -y kubeadm=1.31.0-*

# upgrade plan
sudo kubeadm upgrade plan

# upgrade
sudo kubeadm upgrade apply v1.31.0

# kubelet/kubectl
sudo apt install -y kubelet=1.31.0-* kubectl=1.31.0-*
sudo apt-mark hold kubeadm kubelet kubectl
sudo systemctl restart kubelet
```

**2단계: 나머지 CP**

```bash
sudo kubeadm upgrade node    # apply 대신 node
# kubelet 동일
```

**3단계: 워커들 (한 번에 한 대씩)**

```bash
kubectl drain k8s-w1 --ignore-daemonsets --delete-emptydir-data
ssh k8s-w1
  sudo apt install -y kubeadm=1.31.0-*
  sudo kubeadm upgrade node
  sudo apt install -y kubelet=1.31.0-* kubectl=1.31.0-*
  sudo systemctl restart kubelet
exit
kubectl uncordon k8s-w1
# 다음 워커
```

---

## 6. 인증서 갱신 캘린더

| 대상                                 | 만료        | 갱신                              |
| ------------------------------------ | ----------- | --------------------------------- |
| 자체 CA (`~/pki/ca.crt`)             | 10년        | 거의 X (만료 1년 전 알람)         |
| Wildcard cert (`wildcard.pem`)       | 1년         | 수동, 11개월차                    |
| cert-manager 발급 cert (per-service) | 90일        | 자동 (60일 후)                    |
| K8s 시스템 cert (apiserver 등)       | 1년         | `kubeadm certs renew` (자동/수동) |
| etcd cert                            | 1년         | 위와 동일                         |
| Harbor admin password                | (정책 없음) | 권장 분기 1회                     |
| Jenkins admin password               | (정책 없음) | 권장 분기 1회                     |

### 6.1 K8s 시스템 cert 자동 갱신

kubeadm v1.15+는 `kubeadm upgrade`마다 cert 자동 갱신. 그래서 1년에 한 번 patch upgrade가 자연스러운
갱신 기회.

수동:

```bash
# 만료일 확인
sudo kubeadm certs check-expiration

# 모두 갱신
sudo kubeadm certs renew all

# kubelet 재시작 필요 (정적 Pod들 자동 재시작)
sudo systemctl restart kubelet
```

### 6.2 ToDo 설정

- Google Calendar에 wildcard cert 갱신 11개월 후 알람
- CA cert 9년 6개월 후 알람

---

## 7. SPoF 매트릭스

현재 시스템의 SPoF (Single Point of Failure) 정리.

| SPoF                              | 영향                                              | 완화 옵션                       |
| --------------------------------- | ------------------------------------------------- | ------------------------------- |
| **RGW (ceph1 1대)**               | Harbor push/pull 불가 (이미 running Pod는 영향 X) | RGW 2개 이상 + LB               |
| **k8s-sys1 노드**                 | ArgoCD/Harbor/Jenkins/모니터링 정지               | sys2 추가 + HA 컴포넌트 replica |
| **bastion (kosa3에 위치)**        | kubectl 접근 채널 1개                             | 다른 노트북에 kubeconfig 보유   |
| **MetalLB active 노드**           | Ingress LB 1개 노드 의존                          | L2 페일오버는 자동 (수 초)      |
| **pfSense MASTER 노드의 Proxmox** | failover 가능하지만 부팅 의존                     | OOB 경로 + autostart            |
| **자체 CA private key**           | 분실 시 재앙                                      | 다중 백업                       |
| **GitHub (외부)**                 | git push/pull 불가 → CI 정지                      | 사내 GitLab 또는 git mirroring  |
| **NAT Gateway (AWS, 향후)**       | private subnet outbound 정지                      | AZ별 NAT (비용 ↑)               |

---

## 8. 통합 트러블슈팅 인덱스

각 챕터의 트러블슈팅을 카테고리별로 cross-reference.

### 8.1 네트워크

- VLAN tag 안 먹음 → [02 §10.1](02-physical-network.md#101-vlan-tag-안-먹음)
- CARP split-brain → [02 §10.2](02-physical-network.md#102-carp-split-brain)
- XMLRPC 동기화 실패 → [02 §10.3](02-physical-network.md#103-xmlrpc-동기화-실패)
- 노트북에서 NXDOMAIN → [02 §10.4](02-physical-network.md#104-노트북에서-kosateam2-nxdomain)
- K8s 워커 NXDOMAIN → [02 §10.5](02-physical-network.md#105-k8s-워커에서-kosateam2-nxdomain)
- K8s Pod NXDOMAIN → [02 §10.6](02-physical-network.md#106-k8s-pod에서만-nxdomain)
- 10G 느림 → [02 §10.7](02-physical-network.md#107-ceph-10g에서-느린-처리량)

### 8.2 가상화 (Proxmox)

- VM 메모리 100%+ → [03 §10.1](03-proxmox.md#101-vm-메모리가-100-빨강)
- 클러스터 quorum 깨짐 → [03 §10.2](03-proxmox.md#102-클러스터-quorum-깨짐)
- 마이그레이션 실패 → [03 §10.3](03-proxmox.md#103-cpu-type-host로-마이그레이션-실패)
- ballooning/NUMA → [03 §10.4](03-proxmox.md#104-numa--메모리-ballooning-이슈)
- cloud-init 재실행 → [03 §10.5](03-proxmox.md#105-cloud-init-한-번-더-돌리고-싶음)
- 디스크 IO 병목 → [03 §10.6](03-proxmox.md#106-디스크-io-병목-nvme-100)
- vmbr VLAN tag → [03 §10.7](03-proxmox.md#107-vmbr이-vlan-tag-적용-안-함)

### 8.3 Ceph

- OSD down → [04 §12.1](04-ceph.md#121-health_warn-osd-down)
- slow ops → [04 §12.2](04-ceph.md#122-health_warn-slow-ops)
- mons clock skew → [04 §12.3](04-ceph.md#123-health_warn-mons-clock-skew)
- PG stuck → [04 §12.4](04-ceph.md#124-pg-stuck-undersized--degraded)
- RBD stale watcher → [04 §12.5](04-ceph.md#125-rbd-watcher가-stale-k8s)
- Full ratio → [04 §12.6](04-ceph.md#126-full-ratio-위험)
- RGW NoSuchBucket → [04 §12.7](04-ceph.md#127-rgw-nosuchbucket)
- RGW connection refused → [04 §12.8](04-ceph.md#128-rgw-connection-refused)

### 8.4 Kubernetes

- 노드 NotReady → [05 §12.1](05-kubernetes.md#121-노드-notready)
- kubectl timeout → [05 §12.2](05-kubernetes.md#122-kubectl-통신-안-됨-timeout)
- PVC Multi-Attach → [05 §12.3](05-kubernetes.md#123-pvc-pending--multi-attach)
- CSI 마운트 실패 → [05 §12.4](05-kubernetes.md#124-csi-마운트-실패-rbdcsicephcom-not-found)
- Pod Pending → [05 §12.5](05-kubernetes.md#125-pod-pending-insufficient-resources)
- Ingress 404 → [05 §12.6](05-kubernetes.md#126-ingress-404)
- CoreDNS NXDOMAIN → [05 §12.7](05-kubernetes.md#127-coredns-nxdomain)
- etcd 위험 신호 → [05 §12.8](05-kubernetes.md#128-etcd-위험-신호)

### 8.5 보안 / TLS

- x509 unknown authority →
  [06 §9.1](06-security-tls.md#91-x509-certificate-signed-by-unknown-authority)
- SAN mismatch → [06 §9.2](06-security-tls.md#92-x509-certificate-is-valid-for-x-not-y-san-mismatch)
- cert-manager 발급 안 함 → [06 §9.3](06-security-tls.md#93-cert-manager가-cert-발급-안-함)
- Ingress cert 못 찾음 → [06 §9.4](06-security-tls.md#94-ingress가-cert-못-찾음)
- 자체 CA 만료 임박 → [06 §9.5](06-security-tls.md#95-자체-ca-cert-만료-임박)
- wildcard 만료 → [06 §9.6](06-security-tls.md#96-wildcard-cert-만료)
- webhook 에러 → [06 §9.7](06-security-tls.md#97-cert-manager-admission-webhook-에러)

### 8.6 GitOps (ArgoCD)

- OutOfSync but Healthy → [07 §10.1](07-gitops-argocd.md#101-outofsync인데-healthy) + CLAUDE FAQ Q5
- Sync 실패 → [07 §10.2](07-gitops-argocd.md#102-sync-실패-rpc-error-code--unknown-)
- ImagePullBackOff → [07 §10.3](07-gitops-argocd.md#103-imagepullbackoff)
- helm 버전 불일치 → [07 §10.4](07-gitops-argocd.md#104-helm-chart-버전-불일치)
- webhook fail로 sync fail → [07 §10.5](07-gitops-argocd.md#105-webhook-호출-실패로-sync-실패)
- root-app 동작 X → [07 §10.6](07-gitops-argocd.md#106-root-app이-다른-application-안-만듦)

### 8.7 Harbor

- x509 (push) →
  [08 §10.1](08-harbor-registry.md#101-push-x509-certificate-signed-by-unknown-authority)
- access denied →
  [08 §10.2](08-harbor-registry.md#102-push-denied-requested-access-to-the-resource-is-denied)
- NoSuchBucket → [08 §10.3](08-harbor-registry.md#103-push-s3aws-nosuchbucket)
- connection refused → [08 §10.4](08-harbor-registry.md#104-push-s3aws-connection-refused)
- 503 stuck → [08 §10.5](08-harbor-registry.md#105-push-503--11h-stuck)
- manifest unknown → [08 §10.6](08-harbor-registry.md#106-pull-manifest-unknown)
- Web UI 접속 안 됨 → [08 §10.7](08-harbor-registry.md#107-web-ui-접속-안-됨)
- 디스크 폭증 → [08 §10.10](08-harbor-registry.md#1010-디스크-사용량-폭증)

### 8.8 Jenkins / CI/CD

- Login Failed → [09 §9.1](09-jenkins-ci.md#91-login-failed-반복)
- plugin 호환성 → [09 §9.2](09-jenkins-ci.md#92-plugin-호환성-깨짐-2492x)
- Agent Pod 안 뜸 → [09 §9.3](09-jenkins-ci.md#93-build-agent-pod-안-뜸)
- sshagent not found → [09 §9.4](09-jenkins-ci.md#94-sshagent-not-found)
- GitHub Host Key fail → [09 §9.5](09-jenkins-ci.md#95-github-host-key-verification-failed)
- Kaniko x509 → [09 §9.6](09-jenkins-ci.md#96-kaniko-push-x509)
- Pipeline 자체 안 시작 → [10 §9.1](10-cicd-pipeline.md#91-pipeline-자체가-시작-안-됨)
- git clone fail → [10 §9.2](10-cicd-pipeline.md#92-git-clone-실패-permission-denied--host-key)
- Kaniko build push fail →
  [10 §9.3](10-cicd-pipeline.md#93-kaniko-build-실패-error-checking-push-permissions)
- sed 미반영 → [10 §9.5](10-cicd-pipeline.md#95-sed-결과가-안-바뀜)
- git push rejected → [10 §9.6](10-cicd-pipeline.md#96-git-push-rejected)

### 8.9 관측 (Prometheus)

- Target down → [11 §9.1](11-observability.md#91-target-down)
- ServiceMonitor 인식 X → [11 §9.2](11-observability.md#92-servicemonitor-인식-안-됨)
- Grafana 로그인 실패 → [11 §9.3](11-observability.md#93-grafana-로그인-실패)
- TSDB 풀 → [11 §9.5](11-observability.md#95-prometheus-tsdb-디스크-풀)

---

## 9. 추천 다음 단계

온프레 부분은 일단 안정화 완료. 다음 작업 후보:

### 9.1 운영 강화 (작은 단위 작업)

- [ ] etcd snapshot CronJob 자동화 (Ceph RBD PVC 백업)
- [ ] Velero 도입 (K8s 전체 백업)
- [ ] Alertmanager → Slack 연동
- [ ] Harbor 사용자/프로젝트 RBAC 본격 정리
- [ ] Jenkins GitHub Webhook (자동 트리거)
- [ ] PXC + ProxySQL 도입 (데모 앱 DB)
- [ ] 부하 테스트 환경 (k6 / JMeter VM)

### 9.2 AWS 하이브리드 (대형 작업)

- [ ] Site-to-Site VPN (terraform)
- [ ] DB Subnet tier
- [ ] VPC Endpoints (S3 Gateway, ECR Interface)
- [ ] EKS + Karpenter (Burst)
- [ ] RDS Read Replica (Percona binlog 복제 대상)
- [ ] CloudWatch + Lambda 자동 burst trigger
- [ ] ArgoCD multi-cluster 등록 (온프레 → EKS)
- [ ] AWS WAF
- [ ] Route 53 + ACM (실제 도메인 시)

### 9.3 차세대 (장기)

- [ ] Service Mesh (Istio / Linkerd) — mTLS 통합
- [ ] Loki + Tempo (로그/트레이스)
- [ ] Ceph RGW HA (2~3 노드)
- [ ] Cluster-API / Crossplane (인프라 자체를 GitOps)
- [ ] Policy as Code (OPA / Kyverno)

---

## 부록: 운영자 핵심 명령 요약

```bash
# K8s 상태 한눈
kubectl get nodes,pods -A | grep -v Running

# 노드 자원
ssh kosa1 "free -h && uptime"

# Ceph 상태
ssh ceph1 "ceph -s"

# ArgoCD 상태
kubectl get applications -n argocd

# Jenkins 빌드 큐
kubectl logs -n jenkins jenkins-0 --tail=50 | grep -i queue

# Harbor pod
kubectl get pods -n harbor

# Edge HAProxy 상태
ssh ubuntu@172.16.22.10 "sudo systemctl status haproxy keepalived"

# pfSense CARP
# (pfSense Web UI → Status → CARP)

# 인증서 만료
openssl x509 -in ~/pki/ca.crt -noout -enddate
openssl x509 -in ~/pki/wildcard.crt -noout -enddate
sudo kubeadm certs check-expiration
```

---

## 마무리

이 문서 시리즈가 우리 팀의 1년 후, 3년 후의 자신과 다음 합류자에게 도움이 되길.

기록은 시간이 지나면 무너진다. 변경이 있을 때마다 작은 메모라도 해당 챕터에 추가하는 습관이 가장
중요하다.

**문서가 살아 있어야 시스템도 살아 있다.**
