# 08. Harbor 컨테이너 레지스트리

> **이 챕터에서 다루는 것**
> 사설 컨테이너 레지스트리가 왜 필요한지, Harbor의 내부 컴포넌트, Ceph RGW S3를 백엔드로 선택한 이유, helm values의 미묘한 옵션들 (disableredirect 등 함정), GHCR에서 Harbor로 이미지 마이그레이션 패턴.

## 목차
1. [컨테이너 레지스트리란](#1-컨테이너-레지스트리란)
2. [왜 사설 레지스트리?](#2-왜-사설-레지스트리)
3. [Harbor vs 다른 옵션](#3-harbor-vs-다른-옵션)
4. [Harbor 내부 컴포넌트](#4-harbor-내부-컴포넌트)
5. [Ceph RGW S3 백엔드 (선택 근거)](#5-ceph-rgw-s3-백엔드-선택-근거)
6. [Helm values 라인별 해설](#6-helm-values-라인별-해설)
7. [구축 절차](#7-구축-절차)
8. [GHCR → Harbor 마이그레이션](#8-ghcr--harbor-마이그레이션)
9. [Harbor 운영](#9-harbor-운영)
10. [트러블슈팅](#10-트러블슈팅)
11. [다음 챕터](#11-다음-챕터)

---

## 1. 컨테이너 레지스트리란

이미지(레이어들)를 저장/배포하는 HTTP 서버.

```
[개발자] docker push myapp:1.0 ──► [Registry]
                                       │
[K8s Pod] image: myapp:1.0      ◄──────┘  containerd pull
```

표준 API: OCI Distribution Spec (옛 Docker Registry HTTP API V2).

이미지는 **manifest + 여러 layer(blob)** 로 구성:
```
manifest (JSON)
  ├── config blob (이미지 메타)
  ├── layer blob 1 (OS 기본 레이어)
  ├── layer blob 2 (apt install)
  └── layer blob 3 (COPY ./app)
```

같은 blob은 여러 이미지가 공유 (content-addressable, SHA256).

---

## 2. 왜 사설 레지스트리?

### 2.1 Public 레지스트리만 쓰면 안 되나?

| 옵션 | 문제 |
|---|---|
| **Docker Hub** | rate limit (100 pull / 6h), 무료 private 제한 |
| **GHCR** | GitHub 의존, 외부 네트워크 의존 |
| **Quay.io** | 비슷 |

### 2.2 사설 레지스트리의 이점

1. **속도**: 사내망에서 빠른 pull (이미지 GB 단위면 큰 차이)
2. **rate limit 없음**: 무제한
3. **보안**: 코드/이미지 외부 노출 없음
4. **외부 인터넷 의존 ↓**: 외부 회선 다운에도 배포 가능
5. **RBAC**: 프로젝트별 권한 분리
6. **취약점 스캔**: Trivy 등 자동 스캔
7. **이미지 서명**: Notary/Cosign

> 💡 **트레이드오프**: 레지스트리 자체를 운영해야 함. Harbor + 백엔드 스토리지 + cert 등.

---

## 3. Harbor vs 다른 옵션

| 옵션 | 특징 | 우리에게 |
|---|---|---|
| **Docker Registry (v2)** | 단순, 기본만 | △ RBAC/UI/스캔 없음 |
| **Sonatype Nexus** | 컨테이너 + Maven + npm 등 다목적 | △ Java 무겁고 컨테이너만 쓰기엔 과함 |
| **JFrog Artifactory** | 강력하지만 유료 (OSS도 있으나 제한) | ❌ 비용 |
| **GitHub Packages** | 무료, GitHub 통합 | △ 외부 의존 |
| **Harbor** | OSS, K8s 친화, RBAC/스캔/replication | ✅ 우리 선택 |

### Harbor 특징

- CNCF Graduated project (검증됨)
- 웹 UI 풍부
- 프로젝트 단위 RBAC
- Trivy 취약점 스캔 내장
- Replication (다른 Harbor 또는 외부 레지스트리와 동기화)
- Helm chart, OCI Artifact 지원 (이미지 외 다른 OCI 아티팩트)
- Notary/Cosign 서명

---

## 4. Harbor 내부 컴포넌트

```
┌──────────────── Harbor Namespace ─────────────────┐
│                                                   │
│  [Ingress] harbor.kosa.team2                      │
│       │                                           │
│       ▼                                           │
│  ┌────────────────┐    ┌─────────────────┐       │
│  │ harbor-core    │    │ harbor-portal   │       │
│  │ (API + 인증)   │    │ (Vue.js Web UI) │       │
│  └────────────────┘    └─────────────────┘       │
│       │                                           │
│       ├──► [harbor-database] (Postgres)           │
│       ├──► [harbor-redis]                         │
│       │                                           │
│       ▼                                           │
│  ┌────────────────┐                               │
│  │ harbor-        │                               │
│  │ registry       │ ◄── Docker pull/push          │
│  │ (Docker        │                               │
│  │  Distribution) │                               │
│  └────────┬───────┘                               │
│           │ (이미지 blob)                          │
│           ▼                                       │
│   [Ceph RGW S3]   ← 우리 백엔드                   │
│                                                   │
│  추가 (선택):                                     │
│  ┌────────────────┐    ┌─────────────────┐       │
│  │ harbor-trivy   │    │ harbor-jobservice│       │
│  │ (스캔)         │    │ (replication 등)│       │
│  └────────────────┘    └─────────────────┘       │
└───────────────────────────────────────────────────┘
```

### 4.1 각 컴포넌트의 책임

| 컴포넌트 | 역할 |
|---|---|
| **harbor-core** | API, RBAC, project 관리 |
| **harbor-portal** | Web UI (정적 자산) |
| **harbor-registry** | Docker Distribution 표준 (실제 push/pull 처리) |
| **harbor-database** | Postgres, 메타데이터 |
| **harbor-redis** | 캐시, job queue |
| **harbor-jobservice** | Replication, scan job 실행 |
| **harbor-trivy** | 취약점 스캔 (옵션) |

---

## 5. Ceph RGW S3 백엔드 (선택 근거)

### 5.1 옵션

| 백엔드 | 장점 | 단점 |
|---|---|---|
| **로컬 디스크 / PVC (RBD)** | 단순 | 단일 노드 묶임, 마이그레이션 시 PV move |
| **NFS** | 여러 노드 공유 가능 | NFS 서버 SPoF |
| **S3 호환** | 어디서나 접근, scale-out 쉬움 | S3 서버 필요 |

### 5.2 우리 선택: Ceph RGW S3

이미 Ceph 6노드 클러스터 운영 중. RGW를 띄우면 사내 S3 완성.

장점:
- Harbor registry pod이 어느 노드에 있어도 S3 endpoint로 접근
- Ceph 자체가 분산 저장이라 가용성/scaling 자동
- 외부 AWS 비용 X

### 5.3 RGW 설정 (Ceph 측)

```bash
# RGW 사용자 생성
radosgw-admin user create --uid=harbor --display-name="Harbor Registry"

# 키 재생성 (initial key는 한 번만 보임)
radosgw-admin key create --uid=harbor --gen-access-key

# Quota
radosgw-admin quota set --uid=harbor --max-size=200G --max-objects=10M
radosgw-admin quota enable --uid=harbor --quota-scope=user

# Bucket 수동 생성 (Harbor가 자동 생성 X)
AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> \
  aws --endpoint-url http://10.10.10.11:7480 --region us-east-1 \
  s3 mb s3://harbor-registry
```

### 5.4 K8s Secret로 키 주입

```bash
kubectl create secret generic harbor-s3-secret -n harbor \
  --from-literal=REGISTRY_STORAGE_S3_ACCESSKEY=<key> \
  --from-literal=REGISTRY_STORAGE_S3_SECRETKEY=<secret> \
  --from-literal=accesskey=<key> \
  --from-literal=secretkey=<secret>
```

> ⚠️ **키 이름 4개?** Harbor chart의 일부 컴포넌트는 `REGISTRY_STORAGE_S3_*` 환경 변수, 다른 컴포넌트는 `accesskey/secretkey`를 기대. 양쪽 다 넣는 게 안전.

---

## 6. Helm values 라인별 해설

```yaml
# ─────── 외부 노출 ───────
expose:
  type: ingress
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-ingress-cert   # cert-manager가 채울 Secret
  ingress:
    hosts:
      core: harbor.kosa.team2
    className: haproxy                   # ← 새로운 ingressClassName 필드
    annotations:
      kubernetes.io/ingress.class: haproxy   # ← 옛 HAProxy Ingress 호환 필수
      cert-manager.io/cluster-issuer: kosa-ca-issuer

# ─────── 외부 URL ───────
externalURL: https://harbor.kosa.team2     # ← UI/CLI가 보여줄 URL

# ─────── 영구 저장 ───────
persistence:
  enabled: true
  
  # 메타데이터 (Postgres, Redis 등) — RBD PVC
  persistentVolumeClaim:
    registry:
      storageClass: team2-rbd-block
      size: 50Gi
    jobservice:
      storageClass: team2-rbd-block
      size: 5Gi
    database:
      storageClass: team2-rbd-block
      size: 10Gi
    redis:
      storageClass: team2-rbd-block
      size: 5Gi
    trivy:
      storageClass: team2-rbd-block
      size: 10Gi
  
  # ★ 이미지 blob 저장 — RGW S3
  imageChartStorage:
    type: s3
    disableredirect: true        # ← 반드시 true (아래 6.1 참고)
    s3:
      existingSecret: harbor-s3-secret
      region: default            # ← RGW는 region 개념 없음
      bucket: harbor-registry
      regionendpoint: http://10.10.10.11:7480
      v4auth: true               # ← SigV4 (표준)
      secure: false              # ← 7480은 HTTP

# ─────── 관리자 ───────
harborAdminPassword: kosa1004     # 초기 admin 비번

# ─────── nodeSelector (sys1 격리) ───────
core:        { nodeSelector: { workload-type: system } }
portal:      { nodeSelector: { workload-type: system } }
registry:    { nodeSelector: { workload-type: system } }
database:    { nodeSelector: { workload-type: system } }
redis:       { nodeSelector: { workload-type: system } }
jobservice:  { nodeSelector: { workload-type: system } }
trivy:       { nodeSelector: { workload-type: system } }

# ─────── replica (sys1 단일 노드라 1) ───────
core:        { replicas: 1 }
portal:      { replicas: 1 }
registry:    { replicas: 1 }
jobservice:  { replicas: 1 }
```

### 6.1 disableredirect 함정

RGW는 클라이언트에 "이 URL로 다시 받으세요" 식 302 redirect를 보낸다 (presigned URL).

```
Client → Harbor registry: GET /v2/foo/blobs/sha256:abc
Harbor registry → Client: 302 Location: http://10.10.10.11:7480/harbor-registry/...
Client → 10.10.10.11:7480: ← 도달 불가 (내부 IP)
                            → 외부 client는 못 받음
```

`disableredirect: true`면 Harbor가 RGW에서 직접 받아 클라이언트에 proxy:

```
Client → Harbor: GET ...
Harbor → RGW (직접 GET)
Harbor → Client (stream)
```

내부 트래픽 ↑ (proxy 비용) 이지만 정상 동작.

### 6.2 다른 함정 모음

- **adminUser deprecated**: chart 5.x부터 `controller.admin.username/password` 사용
- **ingressClassName** 옛 HAProxy Ingress controller가 무시 → `kubernetes.io/ingress.class` 어노테이션 필수
- **bucket 자동 생성 X**: 위 §5.3 수동 생성

---

## 7. 구축 절차

### 7.1 사전

1. Ceph RGW 활성화, 사용자/키/bucket 생성 (§5.3)
2. K8s Secret `harbor-s3-secret` (§5.4)
3. cert-manager + ClusterIssuer 동작 중

### 7.2 ArgoCD Application

`~/kosa-gitops/apps/_applications/harbor.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: harbor
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://helm.goharbor.io
    chart: harbor
    targetRevision: 1.16.0
    helm:
      values: |
        # (위 §6 values 통째로)
  destination:
    server: https://kubernetes.default.svc
    namespace: harbor
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
      - CreateNamespace=true
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jsonPointers: [/spec/volumeClaimTemplates]
    - kind: Secret
      jsonPointers: [/data]
```

commit/push → root-app이 감지 → harbor 배포.

### 7.3 검증

```bash
kubectl get pods -n harbor
# 모두 Running

# Web UI
open https://harbor.kosa.team2
# admin / kosa1004
```

### 7.4 첫 push 테스트

bastion에서:
```bash
docker login harbor.kosa.team2 -u admin -p kosa1004
docker pull nginx:latest
docker tag nginx:latest harbor.kosa.team2/library/nginx:latest
docker push harbor.kosa.team2/library/nginx:latest

# Web UI에서 library/nginx 확인
```

---

## 8. GHCR → Harbor 마이그레이션

### 8.1 단순 패턴 (개별 이미지)

```bash
# bastion에서
docker pull ghcr.io/kosacloudteam2/kosa-tickets:latest
docker tag ghcr.io/kosacloudteam2/kosa-tickets:latest \
  harbor.kosa.team2/library/kosa-tickets:latest
docker push harbor.kosa.team2/library/kosa-tickets:latest
```

### 8.2 GitOps repo image URL 변경

```bash
cd ~/kosa-gitops
sed -i 's|ghcr.io/kosacloudteam2|harbor.kosa.team2/library|g' apps/ticket-app/deployment.yaml
git commit -am "migrate ticket-app to Harbor"
git push
```

ArgoCD가 sync → 새 이미지 URL로 Pod 재생성 (단, containerd가 Harbor cert 신뢰 후).

### 8.3 pull secret 추가 (사설 project인 경우)

`library` 프로젝트는 public이라 secret 불필요. 다른 private project는:

```bash
kubectl create secret -n kosa-tickets docker-registry harbor-pull-secret \
  --docker-server=harbor.kosa.team2 \
  --docker-username=admin \
  --docker-password=kosa1004
```

deployment.yaml:
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: harbor-pull-secret     # ← pod spec 레벨, containers 안 X
      containers: [...]
```

### 8.4 워커 노드 containerd CA 신뢰

[06-security-tls.md](06-security-tls.md) §6 참고.

---

## 9. Harbor 운영

### 9.1 프로젝트 / 사용자

Web UI → Projects:
- Public/Private 설정
- 멤버 추가 (admin/dev/guest 역할)
- 취약점 스캔 정책

### 9.2 Replication (다른 Harbor 또는 외부와 동기화)

Web UI → Administration → Replications:
- AWS ECR ↔ Harbor (양방향)
- 백업 Harbor와 동기화

### 9.3 취약점 스캔

```
Trivy 활성화 시 push 자동 스캔.
Web UI → 이미지 → Vulnerabilities 탭
```

심각 vulnerability 있는 이미지 차단도 정책으로 가능.

### 9.4 가비지 컬렉션

만료된 이미지 + orphan blob 정리 (디스크 회수).

```
Administration → Garbage Collection → "Schedule" 또는 "Run Now"
```

권장: 주 1회 자동 GC.

---

## 10. 트러블슈팅

### 10.1 Push: `x509: certificate signed by unknown authority`

CA 신뢰 안 됨. [06-security-tls.md](06-security-tls.md) §6.

### 10.2 Push: `denied: requested access to the resource is denied`

권한 문제. project 권한 확인, 또는 `docker login` 다시.

### 10.3 Push: `s3aws: NoSuchBucket`

Bucket 미생성. §5.3 수동 생성.

### 10.4 Push: `s3aws: connection refused`

Harbor registry pod의 connection state 캐시 문제 (보통 API VIP 회복 직후).

```bash
kubectl delete pod -n harbor -l component=registry
```

### 10.5 Push 503 / 11h stuck

K8s API VIP (172.16.23.5) 다운 → registry pod이 stale state.

회복 후:
```bash
kubectl delete pod -n harbor -l component=registry
```

### 10.6 Pull: `manifest unknown`

이미지 태그 오타 또는 push 실패. Harbor UI에서 실제 존재 확인.

### 10.7 Web UI 접속 안 됨

```bash
kubectl get ingress -n harbor
# Hosts/Address 확인

kubectl describe ingress -n harbor harbor-ingress
# Events
```

Ingress class annotation, DNS, Edge HAProxy ACL 다 확인 ([02-physical-network.md](02-physical-network.md) §10.4).

### 10.8 RGW endpoint 변경 시

RGW endpoint(예: 다른 노드로 옮김) 변경 시:
1. Helm values의 `regionendpoint` 수정 + 커밋
2. ArgoCD sync
3. registry pod 재시작 (위 10.4)

### 10.9 cert 자동 갱신 후에도 brower에 옛 cert

브라우저 캐시. 강제 새로고침 또는 incognito.
원본 Secret 확인:
```bash
kubectl get secret harbor-ingress-cert -n harbor -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -enddate
```

### 10.10 디스크 사용량 폭증

GC 안 돌렸을 가능성. §9.4.

---

## 11. 다음 챕터

→ **[09. Jenkins CI](09-jenkins-ci.md)**

"왜 Jenkins?" 솔직한 답, Kubernetes plugin으로 Pod-as-Agent, JCasC, Kaniko로 rootless 이미지 빌드.
