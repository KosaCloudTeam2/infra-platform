# 08. Backup + DR 정책 (시나리오 기반)

> ⭐ **한 줄 요약**: 우리 시나리오 기준 백업 대상은 **etcd + PXC + Ceph RBD + Harbor DB + 자체 CA**다. RTO 1시간 / RPO 24시간 목표. **현재 자동화 없음**이라 Phase 6 우선 작업이다.

---

## 🎯 우리 시나리오에서 백업이 필요한 것들

데모/학습 환경이지만 backup 정책은 진짜 운영 패턴 그대로 잡는 게 학습 가치가 ↑이다. 우리 시나리오에서 백업이 필요한 데이터를 우선순위별로 정리한다.

### 절대 필요 (없으면 복구 불가)

| # | 대상 | 이유 | 백업 주기 | 보관 |
|---|---|---|---|---|
| 1 | **etcd** | K8s 전체 상태 (모든 manifest) | 4시간 | 7일 |
| 2 | **PXC 데이터** | 비즈니스 데이터 (PII) | 매일 | 30일 + 월별 1년 |
| 3 | **Harbor DB (PostgreSQL)** | 이미지 메타데이터 (이미지 자체는 Ceph RGW에 있어서 재생성 가능) | 매일 | 30일 |
| 4 | **자체 CA key (`~/pki/ca.key`)** | CA 자체. 잃으면 모든 cert 무효 | 1회 + 변경 시 | 영구 |
| 5 | **kosa-gitops repo** | 모든 K8s manifest. GitHub에 있어서 외부 백업도 권장 | 매 commit | 영구 |

이 5개가 진짜 critical이다. 어느 하나라도 잃으면 복구 비용이 ★★★★ 또는 ★★★★★다.

### 중요 (없어도 재구축 가능하지만 시간 ↑)

| # | 대상 | 재구축 비용 | 백업 권장? |
|---|---|---|---|
| 6 | **Ceph RBD PV (Prometheus TSDB)** | 손실 OK (메트릭 7일 휘발) | ❌ |
| 7 | **Ceph RBD PV (Grafana)** | 대시보드 손실 → manual 재구성 | ⚠️ 옵션 |
| 8 | **Ceph RBD PV (Loki)** | 로그 손실 OK (7일 휘발) | ❌ |
| 9 | **Ceph RBD PV (Tempo)** | trace 손실 OK | ❌ |
| 10 | **Ceph RBD PV (Jenkins)** | job history 손실 (코드는 Git에 있음) | ⚠️ 옵션 |
| 11 | **Ceph RBD PV (Harbor)** | DB 백업 따로면 OK | ❌ |
| 12 | **Redis 데이터** | 캐시 (휘발 OK), 단 큐 데이터는 위험 | ⚠️ 옵션 |

휘발성이 OK인 데이터 (Prometheus 메트릭, Loki 로그, Tempo trace)는 백업 안 하는 게 합리적이다. 백업 비용 < 손실 가치. 단, **Grafana 대시보드는 사람이 직접 만든 거라 백업 가치가 있다** (custom dashboard 손실 시 다시 만드는 시간이 아까움).

### 재생성 가능 (백업 불필요)

- Container images (Harbor에서 다시 build)
- PXC binlog (replication용, 7일만 retain)
- AWS RDS (replica니까 PXC 복구 후 자동 catch-up)

---

## 📊 RTO / RPO 목표 (시나리오별)

**RTO = Recovery Time Objective** (얼마나 빨리 복구해야 하나)
**RPO = Recovery Point Objective** (얼마나 데이터 손실 허용)

| 시나리오 | RTO 목표 | RPO 목표 | 비고 |
|---|---|---|---|
| **Pod 1개 죽음** | 1분 | 0 | K8s 자동 회복 |
| **노드 1대 죽음** | 5분 | 0 | reschedule |
| **sys1 전체 죽음** | 30분 | 0 (PV 살아있음) | sys2 추가 시 1분 |
| **K8s 전체 죽음** | 4시간 | 4시간 (etcd backup) | etcd restore 후 재배포 |
| **Ceph 클러스터 죽음** | 24시간 | 24시간 | PXC backup에서 복구 |
| **온프레 전체 죽음 (DR)** | 8시간 | 24시간 | RDS replica를 promote + AWS로 |
| **자체 CA key 손실** | 1주 | 0 | 새 CA + 모든 cert 재발급 (★★★★★ 작업) |

→ 우리 목표: **평균 RTO 1시간 / RPO 24시간** (데모 환경 기준).

진짜 운영급은 RTO 분 단위 + RPO 0 (transactional log replication)이 일반적이다. 우리는 데모/학습이라 더 관대한 목표를 잡았다. e-commerce 같은 실시간 매출 영향 워크로드면 RTO 5분 + RPO 0이 표준.

---

## 🛠️ 현재 상태 vs 목표

현실을 솔직히 정리하면 다음과 같다.

| 백업 대상 | 현재 | 목표 (Phase 6) | 도구 |
|---|---|---|---|
| etcd | ❌ 없음 | 4시간마다 + Ceph RBD PVC에 저장 | CronJob + etcdctl snapshot |
| PXC | ❌ 없음 | 매일 + Ceph RGW S3 | Percona xtrabackup CronJob |
| Harbor DB | ❌ 없음 | 매일 | pg_dump CronJob |
| 자체 CA | ✅ bastion `~/pki/` (manual) | + 외부 저장 (AWS S3 + 암호화) | manual + KMS |
| kosa-gitops | ✅ GitHub | + 매일 bastion local | git clone CronJob |
| Grafana dashboard | ❌ | + Git commit | grafana-as-code (옵션) |
| Jenkins config | ❌ | + Git commit | configuration-as-code 플러그인 |

**거의 대부분 미구축 상태**다. 학습 환경에선 데이터 손실이 critical 영향이 적어서 우선순위가 ↓이었는데, 운영 진입 직전엔 무조건 해야 할 작업들이다.

---

## 🚀 Phase 6 Backup 자동화 계획

각 백업 대상의 구체적 구현 패턴을 정리한다.

### Step 1: etcd backup (1일 작업)

K8s 전체 상태를 4시간마다 snapshot으로 저장. Ceph RBD PVC에 7일 보관.

```yaml
# CronJob: 4시간마다 etcd snapshot → RBD PVC
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: kube-system
spec:
  schedule: "0 */4 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true
          containers:
          - name: etcdctl
            image: bitnami/etcd:3.5
            command:
            - /bin/sh
            - -c
            - |
              etcdctl --endpoints=https://127.0.0.1:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/server.crt \
                --key=/etc/kubernetes/pki/etcd/server.key \
                snapshot save /backup/etcd-$(date +%Y%m%d-%H%M).db
              find /backup -name "etcd-*.db" -mtime +7 -delete
            volumeMounts:
            - name: backup
              mountPath: /backup
          nodeSelector:
            node-role.kubernetes.io/control-plane: ""
```

CronJob이 4시간마다 etcd snapshot을 떠서 RBD PVC에 저장하고, 7일 지난 건 자동 삭제한다.

### Step 2: PXC backup (1일 작업)

Percona Operator의 backup 기능을 활성화. PerconaXtraDBClusterBackup CR로 schedule.

```yaml
schedule:
  - name: "daily-backup"
    schedule: "0 2 * * *"   # 매일 02:00
    keep: 30
    storageName: ceph-rgw-s3
```

매일 새벽 2시에 xtrabackup으로 PXC를 Ceph RGW에 백업. 30일 보관. PITR (Point-in-Time Recovery)도 가능해진다.

### Step 3: Harbor DB backup

```bash
# Harbor pg_dump CronJob
0 3 * * * kubectl exec -n harbor harbor-database-0 -- \
  pg_dump -U postgres registry | gzip > /backup/harbor-$(date +%Y%m%d).sql.gz
```

매일 새벽 3시에 Harbor PostgreSQL을 dump.

### Step 4: 자체 CA 외부 backup

CA key는 가장 critical하니 AWS KMS로 암호화 후 S3에 저장.

```bash
# CA key를 AWS KMS로 암호화 후 S3 저장
aws kms encrypt --key-id alias/kosa-ca-backup \
  --plaintext fileb://~/pki/ca.key \
  --output text --query CiphertextBlob | \
  base64 -d > ca.key.encrypted
aws s3 cp ca.key.encrypted s3://kosa-ca-backup/
```

KMS 암호화 후 외부 저장이라 사이트 화재 같은 재난에도 보호된다.

---

## 🔄 복구 절차 (DR Runbook)

각 시나리오별 복구 절차를 명문화한다.

### 시나리오 1: Pod 1개 죽음

K8s 자동 회복 (Deployment replicas 유지). 사람 개입 0.

### 시나리오 2: 노드 1대 죽음

K8s가 5분 후 NotReady 처리 → Pod reschedule. PVC RWO면 stale VolumeAttachment 강제 삭제 필요할 수 있음.

### 시나리오 3: K8s 전체 죽음

1. etcd backup 복원 (가장 최근)
2. ArgoCD root-app 다시 부트스트랩
3. 1~2시간 내 전체 service 회복

### 시나리오 4: PXC 데이터 손실

1. 백업 (Percona xtrabackup) restore
2. ProxySQL 통해 새 PXC 노드 가리키게 변경
3. EKS Pod이 RDS replica로 임시 read (PXC 회복 동안)

### 시나리오 5: 온프레 전체 죽음 (DR)

1. RDS replica를 primary로 promote (`CALL mysql.rds_stop_replication; CALL mysql.rds_reset_external_master;`)
2. Route 53 weight 100% AWS로 (또는 Health Check 자동)
3. EKS에 ticket-app deploy (현재 manual, multi-cluster ArgoCD 도입 시 자동)
4. RTO ~ 1시간 (수동 절차)

### 시나리오 6: 자체 CA key 손실

가장 까다로운 시나리오다.

1. 새 CA 생성
2. **모든 service cert 재발급** (cert-manager가 자동)
3. **모든 노드 trust store 교체** (자체 CA cert 배포)
4. 외부 client에 새 CA cert 배포
- ★★★★★ 작업 (1주+)

---

## 💰 Backup 비용 분석

### Storage 사용량

| 백업 | 용량/일 | 보관 | 총 용량 | 위치 |
|---|---|---|---|---|
| etcd snapshot (4h) | ~50 MB × 6 = 300 MB | 7일 | ~2 GB | Ceph RBD |
| PXC backup | ~5 GB | 30일 | 150 GB | Ceph RGW S3 |
| Harbor DB | ~100 MB | 30일 | 3 GB | Ceph RGW S3 |
| 자체 CA | < 1 MB | 영구 | 1 MB | AWS S3 + KMS |
| **합계** | | | **~155 GB** | |

### 비용

- Ceph 저장 (155 GB): ₩44/GB × 155 = **₩6,820/월** (Ceph TCO 기준)
- AWS S3 (CA key, 1MB): 무시 가능
- AWS KMS (회당 호출): $0.03/10k = 무시
- **합계: 월 ₩7,000 미만**

backup 비용은 사실 매우 작다. **운영 부담 (CronJob 관리 + 검증)**이 더 큰 비용이다.

---

## 🔁 Backup 검증 (가장 중요한데 자주 건너뜀)

**"백업 있다"보다 "백업에서 복구 성공"이 더 중요**하다. backup 자체는 의미가 없고, 실제 복구가 되는지 검증이 진짜 가치다.

### 분기별 검증 (Phase 7)

1. etcd snapshot으로 staging 클러스터에 restore → 정상 동작 확인
2. PXC backup으로 별도 DB에 restore → SELECT 정상 확인
3. Harbor DB restore → 이미지 메타데이터 정상 확인

→ **검증 없는 backup은 "schrödinger backup"** (있는지 없는지 모름)이다. 실제 복구 시점에 "안 되네?"라는 사고가 자주 발생한다.

---

## 🚀 확장 가능성

### Option A: AWS Backup (관리형)

AWS Backup 서비스로 RDS, EBS 같은 AWS 자원을 통합 관리. 단점은 **AWS 자원만 지원**이라 온프레는 X.

### Option B: ⭐ Velero (K8s 백업 표준)

K8s native backup 도구. manifest + PV를 S3에 백업. namespace 단위 backup/restore 가능. 운영급 진입 시 표준 도구.

- 🎯 **추천 시점**: 진짜 운영급

### Option C: Restic (cross-platform)

가볍고 빠른 backup 도구. 암호화 + dedup 기본. 다양한 source 통합 가능.

### Option D: 다른 사이트로 off-site backup

지리적 DR. 사이트 화재/재난 보호. 비용 + 운영 부담이 있지만 진짜 운영급은 필수.

- 🎯 **추천 시점**: 진짜 DR 정책 필요

### Option E: GitOps backup as code

ArgoCD가 selfHeal로 git에서 재구축 가능하니, K8s manifest는 git이 backup이다. **별도 backup 불필요** (etcd는 K8s 자체 state니까 따로). 이게 GitOps의 숨은 가치다.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 즉시 시작 | Phase 6 step 1~4 |
| 진짜 운영급 | A + B + D |
| 검증 자동화 | Velero (B) + chaos test |

---

## 🔗 다른 파트와의 연결

backup/DR은 모든 파트에 영향을 준다. 데이터 측면에선 PXC backup (`data-storage/05-pxc-redis.md`)과 Ceph snapshot이 핵심. 아키텍처에선 etcd backup + K8s 재구축 (`architecture/06-cost-spof-tradeoffs.md`)이 critical. CI/CD에선 Jenkins config와 Harbor DB backup이 관련. 보안 정책 (`07-security-policy.md`)의 사고 대응 절차와 직결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 백업 자동화 안 했다고요?**

A. **솔직히 미구축**입니다 (학습 시간 한계). **Phase 6 우선 작업**으로 명시했습니다. 데모 환경엔 데이터 손실 critical 영향이 적어서 우선순위가 ↓이었지만, 운영 진입 직전 무조건 구축할 작업입니다. 1주 정도 작업으로 etcd/PXC/Harbor 백업 모두 자동화 가능합니다.

**Q2. RTO/RPO를 어떻게 정했나요?**

A. **데모/학습 기준 (실사용자 없음 가정)**입니다. 진짜 e-commerce면 RTO 분 단위 + RPO 0 (transactional log replication)이 일반적이고, 우리는 RTO 1시간 + RPO 24시간이라는 더 관대한 목표를 잡았습니다. 시나리오/비즈니스 가치에 따라 다릅니다.

**Q3. 자체 CA key가 가장 critical이라고요?**

A. **네**. (1) **잃으면 모든 service cert 무효**, (2) **새 CA 발급 + 모든 노드 trust 교체** ★★★★★ 작업, (3) **외부 client에 새 CA 배포** ★★★. 그래서 (1) bastion local, (2) AWS S3 + KMS 암호화, (3) 분기별 검증의 3중 보호가 필요합니다.

**Q4. K8s manifest는 git에 있는데 etcd backup이 또 왜 필요한가요?**

A. 세 가지 이유입니다. **(1) git에 없는 K8s 자체 state** (secret, configmap auto-generated, runtime info), **(2) GitOps에서 빠진 manifest** (사람이 kubectl로 직접 만든 것), **(3) Pod 현재 상태** (uptime 등). git만으로는 100% 복구가 불가능합니다.

**Q5. Velero를 왜 안 썼나요?**

A. **학습 환경 단순화**입니다. Velero는 운영급 진입 직전 (Phase 7) 도입 검토합니다. 장점은 manifest + PV 통합 백업이라 단일 도구로 다 커버 가능합니다.

**Q6. RDS replica가 있는데 PXC 백업이 굳이 왜 필요한가요?**

A. **RDS는 replica = PXC를 follow**합니다. PXC primary가 데이터 손상 (예: 잘못된 UPDATE)되면 **그 손상이 RDS에도 즉시 복제**됩니다. 즉 **logical 손상은 backup만 보호**할 수 있습니다. RDS는 hardware 손상 (PXC down)만 대응합니다.

**Q7. 백업을 어떻게 검증하나요?**

A. **분기별 복구 훈련**이 정석입니다. staging 클러스터에 backup을 restore해서 실제 동작 확인. 검증 없는 backup은 "schrödinger backup" (있는지 없는지 모름)입니다. 실제 사고 시점에 "안 되네?"라는 비극이 자주 발생합니다. 우리 Phase 7에 검증 자동화도 포함하고 있습니다.
