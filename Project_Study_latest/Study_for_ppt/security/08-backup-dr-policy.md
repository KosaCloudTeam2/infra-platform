# 08. Backup + DR 정책 (시나리오 기반)

> ⭐ **한 줄 요약**: 우리 시나리오 기준 백업 대상 = **etcd + PXC + Ceph RBD + Harbor metadata DB + Jenkins config**. RTO 1시간 / RPO 24시간 목표. 현재 자동화 없음, Phase 6 구축 권장.

---

## 🎯 우리 시나리오에서 백업이 필요한 것들

### 절대 필요 (없으면 복구 불가)
| # | 대상 | 이유 | 백업 주기 | 보관 |
|---|---|---|---|---|
| 1 | **etcd** | K8s 전체 상태 (모든 manifest) | 4시간 | 7일 |
| 2 | **PXC 데이터** | 비즈니스 데이터 (PII) | 매일 | 30일 + 월별 1년 |
| 3 | **Harbor DB (PostgreSQL)** | 이미지 메타데이터 (이미지 자체는 Ceph RGW에 있어서 재생성 가능) | 매일 | 30일 |
| 4 | **자체 CA key (`~/pki/ca.key`)** | CA 자체. 잃으면 모든 cert 무효 | 1회 + 변경 시 | 영구 |
| 5 | **kosa-gitops repo** | 모든 K8s manifest. GitHub에 있어서 외부 백업도 권장 | 매 commit | 영구 |

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

### 재생성 가능 (백업 불필요)
- Container images (Harbor에서 다시 build)
- PXC binlog (replication용, 7일만 retain)
- AWS RDS (replica니까 PXC 복구 후 자동 catch-up)

---

## 📊 RTO / RPO 목표 (시나리오별)

### RTO = Recovery Time Objective (얼마나 빨리 복구해야 하나)
### RPO = Recovery Point Objective (얼마나 데이터 손실 허용)

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

---

## 🛠️ 현재 상태 vs 목표

| 백업 대상 | 현재 | 목표 (Phase 6) | 도구 |
|---|---|---|---|
| etcd | ❌ 없음 | 4시간마다 + Ceph RBD PVC에 저장 | CronJob + etcdctl snapshot |
| PXC | ❌ 없음 | 매일 + Ceph RGW S3 | Percona xtrabackup CronJob |
| Harbor DB | ❌ 없음 | 매일 | pg_dump CronJob |
| 자체 CA | ✅ bastion `~/pki/` (manual) | + 외부 저장 (AWS S3 + 암호화) | manual + KMS |
| kosa-gitops | ✅ GitHub | + 매일 bastion local | git clone CronJob |
| Grafana dashboard | ❌ | + Git commit | grafana-as-code (옵션) |
| Jenkins config | ❌ | + Git commit | configuration-as-code 플러그인 |

---

## 🚀 Phase 6 Backup 자동화 계획

### Step 1: etcd backup (1일 작업)
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
              find /backup -name "etcd-*.db" -mtime +7 -delete  # 7일 보관
            volumeMounts:
            - name: backup
              mountPath: /backup
            - name: etcd-certs
              mountPath: /etc/kubernetes/pki/etcd
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: etcd-backup-pvc
          - name: etcd-certs
            hostPath:
              path: /etc/kubernetes/pki/etcd
          nodeSelector:
            node-role.kubernetes.io/control-plane: ""
          restartPolicy: OnFailure
```

### Step 2: PXC backup (1일 작업)
```yaml
# Percona Operator backup CR
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterBackup
metadata:
  name: kosa-pxc-daily-backup
  namespace: pii-protected
spec:
  pxcCluster: kosa-pxc
  storageName: ceph-rgw-s3   # Ceph RGW endpoint
schedule:
  - name: "daily-backup"
    schedule: "0 2 * * *"   # 매일 02:00
    keep: 30
    storageName: ceph-rgw-s3
```

### Step 3: Harbor DB backup
```bash
# Harbor pg_dump CronJob
0 3 * * * kubectl exec -n harbor harbor-database-0 -- \
  pg_dump -U postgres registry | gzip > /backup/harbor-$(date +%Y%m%d).sql.gz
```

### Step 4: 자체 CA 외부 backup
```bash
# CA key를 AWS KMS로 암호화 후 S3 저장
aws kms encrypt --key-id alias/kosa-ca-backup \
  --plaintext fileb://~/pki/ca.key \
  --output text --query CiphertextBlob | \
  base64 -d > ca.key.encrypted
aws s3 cp ca.key.encrypted s3://kosa-ca-backup/
```

---

## 🔄 복구 절차 (DR Runbook)

### 시나리오 1: Pod 1개 죽음
- K8s 자동 회복 (Deployment replicas 유지)
- 사람 개입 0

### 시나리오 2: 노드 1대 죽음
- K8s가 5분 후 NotReady 처리 → Pod reschedule
- PVC RWO면 stale VolumeAttachment 강제 삭제 필요할 수 있음

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
1. 새 CA 생성
2. **모든 service cert 재발급** (cert-manager가 자동)
3. **모든 노드 trust store 교체** (자체 CA cert 배포)
4. 외부 client에 새 CA cert 배포
- ★★★★★ 작업 (1주+)

---

## 💰 Backup 비용 분석

### Storage
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

---

## 🔁 Backup 검증 (가장 중요한데 자주 건너뜀)

**"백업 있다"보다 "백업에서 복구 성공" 검증이 더 중요**.

### 분기별 검증 (Phase 7)
1. etcd snapshot으로 staging 클러스터에 restore → 정상 동작 확인
2. PXC backup으로 별도 DB에 restore → SELECT 정상 확인
3. Harbor DB restore → 이미지 메타데이터 정상 확인

→ 검증 없이는 "schrödinger backup" (있는지 없는지 모름)

---

## 🚀 확장 가능성

### Option A: ⭐ AWS Backup (관리형)
- ✅ **장점**: 통합 관리, automatic
- ❌ **단점**: AWS 자원만 (RDS, EBS), 온프레 X
- 🎯 **추천 시점**: RDS HA + 본격 운영

### Option B: Velero (K8s 백업 표준)
- ✅ **장점**: K8s native (manifest + PV), S3 백엔드
- 🎯 **추천 시점**: 진짜 운영급

### Option C: Restic (cross-platform)
- ✅ **장점**: 가볍고 빠름, 암호화 + dedup
- 🎯 **추천 시점**: 다양한 source 통합

### Option D: 다른 사이트로 off-site backup
- ✅ **장점**: 사이트 화재/재난 보호
- ❌ **단점**: 비용 + 운영
- 🎯 **추천 시점**: 진짜 DR 정책

### Option E: GitOps backup as code
- 현재: ArgoCD가 selfHeal로 git에서 재구축 가능
- 즉 K8s manifest는 git이 backup → 별도 backup 불필요 (etcd는 K8s 자체 state니까 따로)
- ✅ **장점**: 자연스러운 backup
- 🎯 **추천**: 이미 적용 중

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 즉시 시작 | Phase 6 step 1~4 |
| 진짜 운영급 | A + B + D |
| 검증 자동화 | Velero (B) + chaos test |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 데이터 | PXC backup, Ceph snapshot |
| 🏛️ 아키텍처 | etcd backup, K8s 재구축 |
| 🔧 CI/CD | Jenkins config, Harbor DB backup |
| 🔒 자기 (`07-security-policy.md`) | 사고 대응 절차 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 백업 자동화 안 했다고?**
A. 솔직히 미구축 (학습 시간 한계). Phase 6 우선 작업. 데모 환경엔 문제 X but 운영 진입 직전 무조건 구축.

**Q2. RTO/RPO 어떻게 정했나?**
A. 데모/학습 기준 (실사용자 없음 가정). 진짜 e-commerce면 RTO 분 단위 + RPO 0 (transactional log replication). 시나리오/비즈니스 가치에 따라 다름.

**Q3. 자체 CA key가 가장 critical이라고?**
A. 네. (1) 잃으면 모든 service cert 무효, (2) 새 CA 발급 + 모든 노드 trust 교체 ★★★★★ 작업, (3) 외부 client에 새 CA 배포 ★★★. 따라서 (1) bastion local, (2) AWS S3 + KMS 암호화, (3) 분기별 검증.

**Q4. K8s manifest는 git에 있는데 etcd backup 또 왜?**
A. (1) git에 없는 K8s 자체 state (예: secret, configmap auto-generated, runtime info), (2) GitOps에서 빠진 manifest (사람이 kubectl 한 것), (3) Pod 현재 상태 (uptime 등). git만으로는 100% 복구 불가.

**Q5. Velero를 왜 안 썼나?**
A. 학습 환경 단순화. Phase 7 도입 검토. 장점은 manifest + PV 통합 backup.

**Q6. RDS replica가 있는데 PXC 백업 굳이 왜?**
A. RDS는 replica = PXC follow. PXC primary가 데이터 손상 (예: 잘못된 UPDATE)되면 그 손상이 RDS에도 즉시 복제됨. **logical 손상은 backup만 보호**. RDS는 hardware 손상 (PXC down)만 대응.

**Q7. 백업을 어떻게 검증?**
A. **"분기별 복구 훈련"** — staging 클러스터에 backup restore → 실제 동작 확인. 검증 없는 백업은 의미 X. 우리 Phase 7에 포함.
