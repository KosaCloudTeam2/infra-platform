# 04. Harbor 컨테이너 레지스트리

> ⭐ **한 줄 요약**: **Harbor v2.12** 자체 호스팅 + **Ceph RGW S3 백엔드**. Trivy 취약점 스캔 + cert-manager TLS + GHCR 마이그레이션 완료.

---

## 🎯 우리가 한 선택

| 항목 | 값 |
|---|---|
| 도구 | **Harbor** (CNCF 졸업 프로젝트) |
| 버전 | v2.12 (Helm chart harbor/harbor 1.16.0) |
| 배치 | sys1, namespace `harbor` |
| Image blob 백엔드 | **Ceph RGW S3** (`harbor-registry` bucket) |
| 메타데이터 백엔드 | Ceph RBD (PostgreSQL DB, Redis cache) |
| 도메인 | https://harbor.kosa.team2 |
| TLS | cert-manager (자체 CA) |
| 인증 | admin / kosa1004 (학습 환경) |
| 취약점 스캔 | Trivy (Harbor 내장) |
| 프로젝트 | `library` (public/private) |

---

## 🔍 고려한 대안들

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Harbor (선택)** | RBAC, scan, replication, web UI, Helm chart support | 무거움 (메모리 ~1.5GB, 컴포넌트 8개) | ★★★★★ |
| Docker Registry (v2) | 가볍고 단순 | UI X, scan X, RBAC 약함 | ★★ |
| GHCR (GitHub Container Registry) | GitHub 통합 | 외부 의존, private repo 사용량 제한 | ★★★ |
| AWS ECR | AWS 통합 | AWS lock-in, 비용, region 분리 | ★★★ |
| Quay.io | Red Hat, scan 강력 | 비용 (private repo) | ★★★ |
| Nexus Repository | 통합 (Maven/Docker/npm) | 무거움 | ★★★ |

---

## 💡 왜 Harbor?

### 1. 🔧 **CNCF 졸업 = production grade**
- 2020 CNCF Graduated
- VMware/Pivotal 출신, 대기업 사용
- 활발한 release

### 2. 🛡️ **Trivy 취약점 스캔 통합**
- 이미지 push 시 자동 스캔 (옵션)
- CVE database 매일 update
- 발견 시 차단 (severity 기준)

### 3. 🔒 **RBAC + 다중 프로젝트**
- project별 권한 분리
- LDAP/OIDC SSO 통합 가능

### 4. 💾 **Storage backend 유연**
- Filesystem, S3, GCS, Azure 등
- 우리는 Ceph RGW S3 (자체 호스팅)

### 5. 🔄 **Replication 기능**
- 다른 registry (Docker Hub, GHCR 등)와 mirror 가능
- DR 또는 cache 용도

### 6. 📊 **Web UI + REST API**
- 사람도 쓰고 자동화도 쓰고
- 이미지 비교, layer 분석

---

## 💰 비용 분석

### 자체 호스팅 (Harbor)
| 항목 | 비용 |
|---|---|
| Harbor 8 컴포넌트 (sys1) | ~1.5GB RAM |
| Ceph RGW storage (이미지) | ₩44/GB/월 (TCO) |
| Ceph RBD (메타데이터 DB) | ₩44/GB/월 |
| 총 storage (현재 ~10GB + DB 5GB) | ~₩700/월 |

### AWS ECR 비교
| 항목 | 비용 |
|---|---|
| Storage | $0.10/GB/월 |
| Data transfer OUT | $0.09/GB |
| Trivy 같은 스캐닝 (Inspector) | 별도 |

→ 10GB 이미지 + 자주 pull 시:
- AWS ECR: $1 + $20 (pull 데이터비) = $21/월
- 자체 Harbor: ~₩1,000 (~$0.75)

→ **자체 호스팅 ★★★★ 절감**

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 데이터 주권 | 운영 부담 (8 컴포넌트) |
| Trivy 스캔 통합 | scan db 무거움 (~3GB) |
| 다중 프로젝트 + RBAC | 학습 곡선 |
| Ceph RGW 백엔드 | RGW SPoF (현재 1 daemon) |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Harbor core 죽음** | UI/API down | Pod 재시작 |
| **Harbor DB (postgres) 죽음** | 메타데이터 없음 → 전체 down | DB Pod 재시작 (PVC 데이터 보존) |
| **Ceph RGW 죽음** | image push/pull 실패 (메타데이터는 살아있음) | RGW Pod 재시작 |
| **registry stale connection (API VIP 회복 후 발생 사례)** | `s3aws: connection refused` | `kubectl delete pod -l component=registry` 강제 재시작 |
| **bucket 없음 (init)** | `s3aws: NoSuchBucket` | `aws s3 mb s3://harbor-registry` 수동 생성 |

---

## 🚀 확장 가능성

### Option A: ⭐ Harbor HA (다중 replica)
- ✅ **장점**: SPoF 해소
- ❌ **단점**: 메모리 ★★★, sys2 필요
- 🎯 **추천 시점**: Phase 6 (sys2 추가 후)

### Option B: Ceph RGW 2개로 (백엔드 HA)
- ✅ **장점**: blob storage SPoF 해소
- 💰 **비용**: 0 (다른 Ceph 노드)
- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option C: Replication (다른 registry로 mirror)
- ✅ **장점**: DR + cache
- 🎯 **추천 시점**: 다른 사이트/cloud 도입

### Option D: Notary (이미지 서명)
- ✅ **장점**: 무결성 보장 (supply chain attack 방어)
- ❌ **단점**: 운영 복잡
- 🎯 **추천 시점**: 컴플라이언스 필요

### Option E: Robot account (CI용)
- 현재: admin password 직접 사용
- 확장: project별 robot account (만료 + scope 제한)
- 🎯 **추천 시점**: 즉시 (보안 polish)

### Option F: Cosign (이미지 서명, Notary 후속)
- ✅ **장점**: 더 modern + sigstore 생태계
- 🎯 **추천 시점**: 진짜 supply chain 보안

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| Harbor 단일 노드 위험 인지 | A (HA) |
| Harbor push 자주 실패 | B (RGW HA) |
| Compliance 강화 | D/F (이미지 서명) |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔧 자기 (`03-build-tools.md`) | Kaniko가 Harbor로 push |
| 🔧 자기 (`05-argocd-gitops.md`) | imagePullSecret으로 Harbor에서 pull |
| 💾 데이터 (`04-s3-comparison.md`) | Ceph RGW S3 백엔드 |
| 🔒 보안 | Trivy 스캔, robot account, cert |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. GHCR 무료고 GitHub 통합인데 왜 자체?**
A. (1) 데이터 주권, (2) 비용 (private repo 사용량 제한), (3) Trivy 스캔 통합, (4) replication 기능, (5) 학습 가치. 단, public OSS 프로젝트면 GHCR 무료 + 편함.

**Q2. Harbor 컴포넌트 많아서 운영 부담?**
A. 사실 (8개 Pod). 하지만 (1) Helm chart로 자동 설치, (2) 각 컴포넌트 stateless or PVC-based → K8s가 자동 회복, (3) 메모리 1.5GB로 sys1에서 부담 X.

**Q3. RGW backend `disableredirect: true` 왜?**
A. RGW 기본은 client에 "이 URL로 다시 받으세요" redirect 보냄. URL이 내부 IP라 외부 client 도달 불가 → 반드시 true로. Harbor helm chart의 `imageChartStorage.s3.disableredirect` 설정.

**Q4. Trivy 스캔 false positive 어떻게 처리?**
A. (1) Vulnerability allowlist (특정 CVE 무시), (2) Severity 기준 (Critical만 차단, Medium 통과), (3) Trivy DB update 주기 조정.

**Q5. imagePullSecret 매 namespace 마다 만들어야 하나?**
A. 네. 각 ns에 `harbor-pull-secret` 생성 + Pod spec `imagePullSecrets` 참조. 자동화: `kubernetes-replicator` 같은 tool로 ns 간 secret 복제.

**Q6. private project 만들면?**
A. Harbor UI에서 project 생성 시 "Project Access Level: Private" 선택. 그 project의 이미지는 robot account나 admin만 pull 가능. ticket-app은 현재 `library/kosa-tickets` (public이지만 imagePullSecret 사용).
