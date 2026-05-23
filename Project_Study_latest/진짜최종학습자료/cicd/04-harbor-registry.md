# 04. Harbor 컨테이너 레지스트리

> ⭐ **한 줄 요약**: **Harbor v2.12를 자체 호스팅**한다. Image blob은 **Ceph RGW S3 backend**에 저장하고 메타데이터는 Ceph RBD에 저장한다. Trivy 취약점 스캔 통합 + cert-manager TLS + GHCR에서 마이그레이션 완료. CNCF 졸업 프로젝트로 production grade 검증됨.

---

## 🎯 우리가 한 선택

Harbor는 CNCF가 졸업시킨 enterprise-grade 컨테이너 레지스트리다. 우리는 sys1에 helm chart로 배포했고, 이미지 blob은 Ceph RGW S3 backend로, 메타데이터는 Ceph RBD PVC로 분리해 운영한다. 이미지가 커도 (수 GB+) Ceph RGW가 받을 수 있고, 메타데이터 DB는 빠른 RBD로 성능을 확보했다.

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
| **Harbor (선택)** | RBAC, scan, replication, web UI, Helm chart | 무거움 (메모리 ~1.5GB, 컴포넌트 8개) | ★★★★★ |
| Docker Registry (v2) | 가볍고 단순 | UI X, scan X, RBAC 약함 | ★★ |
| GHCR (GitHub Container Registry) | GitHub 통합 | 외부 의존, private repo 사용량 제한 | ★★★ |
| AWS ECR | AWS 통합 | AWS lock-in, 비용, region 분리 | ★★★ |
| Quay.io | Red Hat, scan 강력 | 비용 (private repo) | ★★★ |
| Nexus Repository | 통합 (Maven/Docker/npm) | 무거움 | ★★★ |

### Harbor를 선택한 이유

Docker Registry v2는 가벼움이 매력이지만 UI도 없고 RBAC도 약하다. Harbor는 그 위에 UI + RBAC + scan + replication + signing 같은 enterprise 기능을 덧붙인 종합 패키지다. CNCF 졸업 (2020) + VMware/Pivotal 출신이라 production 검증도 풍부하다.

GHCR이나 AWS ECR 같은 SaaS도 좋은 옵션이지만 **외부 의존 + 비용**이 부담이다. 우리는 학습 환경 + 데이터 주권 우선이라 자체 호스팅을 골랐다. 같은 도구 (Helm chart)로 어디서나 동작하니 portable하고, 한 번 익히면 어디서나 쓸 수 있다.

---

## 💡 왜 Harbor? — 여섯 가지 이유

### 1. CNCF 졸업 = production grade

**2020년 CNCF Graduated**라는 검증을 받았다. VMware/Pivotal 출신이고 활발한 release. 대기업 (eBay, JD.com 등)에서 실제 사용 중이라 안정성과 기능 모두 검증됐다.

### 2. Trivy 취약점 스캔 통합

이미지 push 시 자동 스캔 (옵션 활성)이 가능하다. CVE database를 매일 update해서 새 취약점을 발견한다. 발견 시 severity 기준으로 차단 정책도 가능 (예: Critical은 차단, Medium은 통과).

### 3. RBAC + 다중 프로젝트

project별로 권한을 분리할 수 있다. `library` (public), `production` (private), `dev` (private) 식으로 영역을 나누고 user/group에 다른 권한 부여. LDAP/OIDC SSO 통합으로 enterprise 환경에 자연스럽다.

### 4. Storage backend가 유연하다

Filesystem (PVC), S3 (RGW/MinIO/AWS), GCS, Azure 모두 지원. 우리는 Ceph RGW S3로 갔지만 향후 AWS S3로 옮기는 게 endpoint 변경 한 줄이다.

### 5. Replication 기능

다른 registry (Docker Hub, GHCR 등)와 mirror 가능. DR 용도 (Harbor 백업 → AWS) 또는 cache 용도 (Docker Hub mirror)로 활용한다.

### 6. Web UI + REST API

사람도 쓰고 자동화도 쓸 수 있다. 이미지 layer 분석, vulnerability report, replication 상태 등을 UI에서 볼 수 있고, API로 자동화도 가능하다.

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

10GB 이미지 + 자주 pull 시:
- **AWS ECR**: $1 + $20 (pull 데이터비) = $21/월
- **자체 Harbor**: ~₩1,000 (~$0.75)

→ **자체 호스팅이 ★★★★ 절감**. 다만 운영 부담 (8 컴포넌트 관리)이 추가됨.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 데이터 주권 | 운영 부담 (8 컴포넌트) |
| Trivy 스캔 통합 | scan db 무거움 (~3GB) |
| 다중 프로젝트 + RBAC | 학습 곡선 |
| Ceph RGW 백엔드 통합 | RGW SPoF (현재 1 daemon) |

가장 큰 trade-off는 **Harbor 자체의 무게**다. 8개 Pod (core, db, registry, redis, jobservice, trivy, portal, exporter)이 떠야 한다. 우리는 sys1에 모두 배치했는데 메모리 ~1.5GB 차지. 데이터베이스 백업도 따로 챙겨야 하고, GHCR이나 ECR 같은 SaaS 대비 운영 부담이 명백히 크다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Harbor core 죽음** | UI/API down | Pod 재시작 |
| **Harbor DB (postgres) 죽음** | 메타데이터 없음 → 전체 down | DB Pod 재시작 (PVC 데이터 보존) |
| **Ceph RGW 죽음** | image push/pull 실패 (메타데이터 살아있음) | RGW Pod 재시작 |
| **registry stale connection (API VIP 회복 후 발생)** | `s3aws: connection refused` | `kubectl delete pod -l component=registry` 강제 재시작 |
| **bucket 없음 (init)** | `s3aws: NoSuchBucket` | `aws s3 mb s3://harbor-registry` 수동 생성 |

**우리가 만난 가장 까다로운 함정**은 registry component의 stale connection이다. API VIP가 일시 죽었다가 회복된 후, registry Pod이 옛 S3 connection을 caching 중이라 `connection refused`가 발생한다. Pod 강제 재시작 (delete pod)으로 connection 재설립이 필요하다.

또 bucket 자동 생성이 안 돼서 처음 깔 때 수동으로 `aws s3 mb`로 만들어야 한다. Harbor가 자동 생성을 안 한다는 게 의외라 함정에 빠지기 쉽다.

---

## 🚀 확장 가능성

### Option A: ⭐ Harbor HA (다중 replica)

sys1 단일 의존성 해소. core/portal/registry 같이 stateless component를 replicas 2+로 늘리고, DB는 그대로 (RWO PVC) 유지. **sys2 추가가 선행 조건**이라 Phase 6 작업 후 검토.

### Option B: ⭐ Ceph RGW 2개로 (backend HA)

가장 시급한 RGW SPoF 해소. ceph2에 추가 RGW daemon 띄우고 Harbor regionendpoint를 HAProxy 통해 round-robin. 2~4시간 작업. Phase 6 우선 작업.

### Option C: Replication (다른 registry로 mirror)

DR + cache 용도. 다른 사이트나 cloud (AWS ECR) 도입 시 검토.

### Option D: Notary (이미지 서명)

무결성 보장 + supply chain attack 방어. 운영 복잡도 ↑이지만 컴플라이언스 요구 시 필수.

### Option E: Robot account (CI용)

현재 admin password를 직접 사용 중인데, 진짜 운영급은 **project별 robot account** (만료 + scope 제한)로 분리. 보안 polish 차원에서 즉시 가능.

### Option F: Cosign (이미지 서명, Notary 후속)

Cosign은 sigstore 생태계의 modern 이미지 서명 도구다. Notary 후속으로 더 가볍고 통합도 좋다.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| Harbor push 실패 잦음 | B (RGW HA) ⭐ |
| sys1 단일 노드 위험 인지 | A (HA) |
| Compliance 강화 | D 또는 F (이미지 서명) |
| Robot account 분리 | E |

---

## 🔗 다른 파트와의 연결

이 Harbor 결정은 여러 파트와 연결된다. Build tool (`03-jenkins-build-tools.md`)에서 Kaniko가 Harbor로 push하고, ArgoCD (`05-argocd-gitops.md`)는 ticket-app deployment의 imagePullSecret으로 Harbor에서 pull한다. 데이터 측면에선 `data-storage/04-s3-comparison.md`가 Ceph RGW backend의 비용/성능을 깊이 다룬다. 보안 측면에선 Trivy 스캔, robot account, cert 관리가 보안 정책과 직결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. GHCR이 무료고 GitHub 통합인데 왜 자체 호스팅?**

A. 다섯 가지 이유입니다. **데이터 주권** (이미지에 코드/설정 포함), **비용** (GHCR private repo 사용량 제한), **Trivy 스캔 통합**, **replication 기능**, **학습 가치**. 단점은 운영 부담인데 Helm chart + GitOps로 자동화했습니다. public OSS 프로젝트면 GHCR 무료 + 편함이지만 우리는 private + 자체 호스팅 가치가 있었습니다.

**Q2. Harbor 8 컴포넌트라 운영 부담이 클 텐데요?**

A. 사실입니다. 하지만 (1) **Helm chart로 자동 설치**, (2) 각 컴포넌트가 **stateless or PVC-based라 K8s가 자동 회복**, (3) 메모리 1.5GB로 sys1에서 부담 X. 자동화가 잘 돼서 setup 후엔 거의 손 안 갑니다.

**Q3. RGW backend `disableredirect: true` 왜 설정했나요?**

A. **RGW 기본은 client에 "이 URL로 다시 받으세요" redirect를 보냅니다**. 그 URL이 RGW의 내부 IP (10.10.10.11)라 외부 client (Harbor에서 외부 push)가 도달 불가입니다. `disableredirect: true`를 명시하면 Harbor가 직접 데이터를 받아서 전달합니다. helm values `imageChartStorage.s3.disableredirect: true`로 설정해야 합니다.

**Q4. Trivy 스캔 false positive를 어떻게 처리하나요?**

A. 세 가지 방법입니다. **Vulnerability allowlist** (특정 CVE 무시 설정), **Severity 기준** (Critical만 차단, Medium 통과), **Trivy DB update 주기 조정**. False positive가 자주 발생하면 allowlist 운영 정책을 수립해야 합니다.

**Q5. imagePullSecret을 namespace마다 만들어야 하나요?**

A. **네, 각 ns에 `harbor-pull-secret` 생성 + Pod spec에 `imagePullSecrets` 참조**가 필요합니다. 자동화하려면 `kubernetes-replicator` 같은 도구로 ns 간 secret 복제 가능합니다. 또는 ServiceAccount의 imagePullSecrets에 추가하면 그 SA를 쓰는 Pod 모두 자동 적용.

**Q6. private project를 만들면 어떻게 동작하나요?**

A. Harbor UI에서 project 생성 시 "Project Access Level: Private"를 선택합니다. 그 project의 이미지는 **robot account나 admin만 pull 가능**합니다. ticket-app은 현재 `library/kosa-tickets`라 public이지만 imagePullSecret을 사용하는 패턴으로 운영 중입니다 (향후 private 변경 시 코드 변경 없음). **admin-app도 동일 패턴** (`library/admin-app:N`, Jenkins build_number tag).

---

## 🗂️ 현재 저장된 이미지

| Repository | 용도 | Tag 패턴 | Jenkins Job |
|---|---|---|---|
| `library/kosa-tickets` | 운영 ticket-app (OLTP) | `:N` (build_number) + `:latest` | `kosa-tickets-ci` |
| `library/admin-app` ⭐ | 관리자 대시보드 (OLAP) | `:N` + `:latest` | `kosa-tickets-admin-ci` |

ticket-app은 ECR로도 자동 mirror됨 (EKS burst Pod이 ECR에서 pull). **admin-app은 온프레만 사용** (sys1 노드 nodeSelector)이라 Harbor만으로 충분.
