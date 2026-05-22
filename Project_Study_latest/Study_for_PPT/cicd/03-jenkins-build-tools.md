# 03. Build Tool — Kaniko vs Docker vs Buildah

> ⭐ **한 줄 요약**: **Kaniko 선택** — rootless container build (K8s Pod 안에서 안전), Dockerfile 호환, Google 만든 검증된 도구. Docker-in-Docker는 privileged 필요해서 보안 X.

---

## 🎯 우리가 한 선택

| 항목 | 값 |
|---|---|
| Build tool | **Kaniko** (`gcr.io/kaniko-project/executor:v1.23.2-debug`) |
| 실행 환경 | K8s Pod (Jenkins dynamic agent) |
| 권한 | Non-root, no privileged |
| Dockerfile 호환 | ✅ 100% |
| Output | OCI 표준 image → Harbor push |
| Auth | `--skip-tls-verify` (자체 CA) 또는 `/kaniko/.docker/config.json` |

---

## 🔍 3 가지 옵션 비교

| 차원 | Kaniko (선택) | Docker-in-Docker (dind) | Buildah |
|---|---|---|---|
| 권한 | rootless ✅ | privileged (--privileged) ❌ | rootless ✅ |
| Dockerfile 호환 | 100% | 100% | 99% (대부분) |
| 속도 | 보통 (layer cache 약) | 빠름 (host docker daemon 활용 가능) | 빠름 |
| K8s Pod 안 | ✅ 표준 | ⚠️ Pod에 privileged + socket mount | ✅ |
| 학습 곡선 | ★★ | ★ | ★★ |
| Google support | ✅ | docker | Red Hat |
| 이미지 출처 | gcr.io/kaniko-project | docker.io/docker:dind | quay.io/buildah/stable |
| CI 환경 표준 | ★★★★ | ★★★ (보안 위험) | ★★★ |

---

## 💡 왜 Kaniko? (4가지)

### 1. 🔒 **Rootless = 보안 ★★★★**
> 🔥 **핵심**: K8s Pod 안에서 docker daemon 띄우면 privileged 권한 필요 → 호스트 침해 risk.

- Docker-in-Docker는 `--privileged=true` 필요 → 호스트 root 권한
- 컨테이너 탈출 (CVE) 시 Worker 노드 침해
- Kaniko는 표준 user → Pod SecurityContext 일반

### 2. 🌐 **K8s native**
- Jenkins dynamic agent에 Kaniko 컨테이너 추가만
- 호스트 docker daemon 불필요
- 그냥 K8s Pod = 어디서나 동작 (K8s 표준)

### 3. ⚡ **Dockerfile 100% 호환**
- Docker로 만든 Dockerfile 그대로 사용
- `FROM`, `RUN`, `COPY`, `CMD` 등 모두 동작
- 학습 곡선 ↓

### 4. 🎯 **Google 운영 + 활발**
- gcr.io 호스팅, Google Cloud Build 기반
- production 검증 (Google 내부 사용)
- 활발한 release (v1.23.2 등)

---

## 💰 비용 분석

build tool 자체는 무료. 차이는 운영 관점:

| 항목 | Kaniko | Docker-in-Docker |
|---|---|---|
| K8s privileged 필요 | ❌ | ✅ (PSP/admission 통과 어려움) |
| 보안 사고 risk | 낮음 | 높음 (privileged) |
| layer cache | 약함 (S3에 cache 가능) | 호스트 docker 활용 가능 |
| 빌드 속도 | 보통 | 약간 빠름 (cache 활용 시) |
| 컴플라이언스 | ★★★★ | ★★ (privileged 거부 정책 ↑) |

---

## ⚖️ Trade-off

### Kaniko의 잃은 것
| 잃은 것 | 의미 |
|---|---|
| Layer cache 약함 | 빌드 매번 처음부터 (5~10분), S3 cache 활용으로 보완 가능 |
| 일부 Dockerfile 패턴 | `RUN --mount=type=cache` 등 BuildKit 전용 기능 X (기본 Dockerfile은 OK) |
| 디버깅 약간 어려움 | debug image (`:debug`) 있어서 shell 가능 |

### Kaniko의 얻은 것
| 얻은 것 | 의미 |
|---|---|
| Rootless | 보안 ★★★★★ |
| K8s native | 운영 단순 |
| Dockerfile 100% | 학습 X |

---

## ⚠️ SPoF + 함정

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Harbor cert 신뢰 X** | push 실패 (x509 error) | `--skip-tls-verify` 또는 CA cert mount |
| **dockerconfigjson 잘못** | unauthorized | secret 키 이름/내용 확인 |
| **빌드 메모리 부족** | OOMKilled | Pod resources 늘림 |
| **빌드 시간 길어짐** | 매번 처음부터 | S3 cache (`--cache=true --cache-repo=...`) |
| **Kaniko 자체 버그** | 빌드 실패 | 버전 down (v1.22) 또는 issue 신고 |

---

## 🚀 확장 가능성

### Option A: ⭐ Layer cache (Ceph RGW S3에)
- ✅ **장점**: 빌드 시간 50% 단축
- 💰 **비용**: 0 (Ceph RGW 무료)
- ⏱️ **작업**: 1시간 (Kaniko flag 추가 + bucket 생성)
- 🎯 **추천 시점**: 빌드 빈도 ↑

### Option B: BuildKit (containerd buildkit) 전환
- ✅ **장점**: 더 빠름, cache 강력, BuildKit-only Dockerfile 문법
- ❌ **단점**: 학습, K8s 통합 추가
- 🎯 **추천 시점**: 진짜 성능 최적화 + 학습 의지

### Option C: Buildah로 전환
- ✅ **장점**: Kaniko와 비슷한 rootless + cache 좋음 + Red Hat 지원
- ❌ **단점**: Kaniko와 비교해 동일 + 마이그레이션 비용
- 🎯 **추천 시점**: Red Hat 환경 정렬

### Option D: dind (Docker-in-Docker) 부활
- ❌ **단점**: 보안 위험
- 🎯 **추천 시점**: 거의 안 함 (모든 modern CI 우회)

### Option E: 클라우드 build 위탁 (Google Cloud Build, AWS CodeBuild)
- ✅ **장점**: 운영 부담 0
- ❌ **단점**: 비용 + 외부 의존
- 🎯 **추천 시점**: 빌드량 거대 + 운영 부담 ↓

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 빌드 시간 ↓ 필요 | A (cache) |
| BuildKit-only 기능 필요 | B |
| Red Hat 환경 | C |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔧 자기 (`04-harbor-registry.md`) | Kaniko가 Harbor로 push |
| 💾 데이터 | Kaniko cache → Ceph RGW (옵션 A) |
| 🔒 보안 | rootless 결정, image scan (Trivy) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Docker-in-Docker가 더 빠르다며?**
A. (1) host docker daemon 활용 시 cache 잘 쓰지만 privileged 필요 → 보안 위험. (2) Kaniko가 좀 느리지만 S3 cache로 보완 가능. modern CI 표준은 rootless build tool (Kaniko/Buildah/img).

**Q2. Kaniko cache 어떻게 설정?**
A. `--cache=true --cache-repo=harbor.kosa.team2/library/cache-repo`. 매 빌드마다 base layer를 Harbor에 저장 → 다음 빌드에서 재사용. 30~50% 빌드 시간 단축 가능.

**Q3. Dockerfile 다 호환?**
A. 99% OK. `RUN --mount=type=cache` 같은 BuildKit-only 문법은 X. 우리 ticket-app Dockerfile은 표준 RUN/COPY → 호환.

**Q4. `--skip-tls-verify` 보안 위험?**
A. Harbor cert가 자체 CA라 Kaniko가 검증 못함 → 우회. 진짜 운영이면 (1) CA cert를 Kaniko Pod에 mount + `--registry-mirror`, 또는 (2) Let's Encrypt cert로 Harbor 운영. 학습 환경엔 skip-verify OK.

**Q5. 빌드 환경이 K8s Pod라 매번 cold start? 느려?**
A. 컨테이너 image pull은 빠름 (Harbor 같은 LAN). 진짜 느린 건 build 자체 (Python pip install 등). Layer cache로 base image 재사용하면 효과적.
