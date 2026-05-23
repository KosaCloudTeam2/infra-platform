# 03. Build Tool — Kaniko vs Docker vs Buildah

> ⭐ **한 줄 요약**: **Kaniko를 골랐다.** K8s Pod 안에서 rootless로 컨테이너 이미지 빌드가 가능해 **privileged 권한이 필요한 Docker-in-Docker (dind)를 회피**했다. Dockerfile 100% 호환이고 Google이 운영하는 검증된 도구다.

---

## 🎯 우리가 한 선택

Kaniko를 Jenkins K8s dynamic agent의 컨테이너로 띄워 빌드를 실행한다. 빌드 결과는 Harbor로 push되고, agent Pod은 빌드 종료 시 자동 삭제된다. Pod은 일반 ServiceAccount + 일반 securityContext로 실행돼 호스트에 어떤 권한도 요구하지 않는다.

| 항목 | 값 |
|---|---|
| Build tool | **Kaniko** (`gcr.io/kaniko-project/executor:v1.23.2-debug`) |
| 실행 환경 | K8s Pod (Jenkins dynamic agent) |
| 권한 | Non-root, no privileged |
| Dockerfile 호환 | ✅ 100% |
| Output | OCI 표준 image → Harbor push |
| Auth | `--skip-tls-verify` (자체 CA) 또는 `/kaniko/.docker/config.json` |

---

## 🔍 3가지 옵션 비교

컨테이너 빌드 도구는 여러 옵션이 있는데 우리가 비교한 3개는 다음과 같다.

| 차원 | Kaniko (선택) | Docker-in-Docker (dind) | Buildah |
|---|---|---|---|
| 권한 | rootless ✅ | privileged (--privileged) ❌ | rootless ✅ |
| Dockerfile 호환 | 100% | 100% | 99% |
| 속도 | 보통 (layer cache 약) | 빠름 (host docker daemon 활용 가능) | 빠름 |
| K8s Pod 안 | ✅ 표준 | ⚠️ Pod에 privileged + socket mount | ✅ |
| 학습 곡선 | ★★ | ★ | ★★ |
| 만든 곳 | Google | Docker Inc | Red Hat |
| 이미지 | gcr.io/kaniko-project | docker.io/docker:dind | quay.io/buildah/stable |
| CI 환경 표준 | ★★★★ | ★★★ (보안 위험) | ★★★ |

### 세 도구의 본질적 차이

**Docker-in-Docker (dind)** 는 가장 오래된 패턴이다. CI agent Pod 안에 docker daemon 자체를 띄우고, build 명령이 그 daemon으로 간다. 빠르고 host docker daemon (cache)을 활용할 수도 있는데, **K8s에서는 privileged 권한이 필요**하다. 컨테이너 탈출 (CVE) 같은 사고 시 호스트 침해 위험이 커서 modern CI는 이걸 피한다.

**Kaniko** 는 Google이 만든 rootless 컨테이너 빌더다. Dockerfile을 user-space에서 layer별로 처리하고 OCI 표준 이미지를 생성한다. **privileged 권한 0**으로 동작하고 Dockerfile 100% 호환이다. 단점은 layer cache가 약해 빌드가 약간 느릴 수 있는데, S3 cache로 보완 가능하다.

**Buildah** 는 Red Hat이 만든 또 다른 rootless 빌더다. Kaniko와 기능적으로 비슷하지만 OpenShift 환경에서 자주 쓰인다. Kaniko와 큰 차이가 없어 우리는 더 보편적인 Kaniko를 선택했다.

---

## 💡 왜 Kaniko? — 네 가지 이유

### 1. Rootless = 보안 ★★★★

> 🔥 K8s Pod 안에서 docker daemon을 띄우면 privileged 권한이 필요 → 호스트 침해 risk.

privileged 컨테이너는 호스트 root 권한을 받는다. 컨테이너 탈출 CVE가 매년 발견되는데, 그런 사고 발생 시 Worker 노드 전체가 침해된다. **Kaniko는 일반 user로 동작**해서 Pod SecurityContext가 일반 워크로드와 동일하다.

### 2. K8s Native 패턴

Kaniko는 그저 K8s Pod 컨테이너 하나일 뿐이다. 우리 Jenkins K8s plugin이 Pod template에 Kaniko 컨테이너를 추가하면 끝이다. **호스트 docker daemon이 필요 없다.** K8s 환경 어디서나 동작하니 portable하다.

### 3. Dockerfile 100% 호환

Docker로 만든 Dockerfile을 그대로 사용 가능하다. `FROM`, `RUN`, `COPY`, `CMD`, `ENV`, multi-stage 등 모든 표준 instruction 지원. 학습 곡선이 낮고 마이그레이션도 쉽다.

### 4. Google 운영 + 활발한 release

gcr.io에서 호스팅되고 Google이 자체 cloud build에서 사용한다. v1.23.2 같이 활발하게 release되고 production 검증이 충분하다.

---

## 💰 비용 분석

Build tool 자체는 무료다. 비용 차이는 운영 관점에서 발생한다.

| 항목 | Kaniko | Docker-in-Docker |
|---|---|---|
| K8s privileged 필요 | ❌ | ✅ (PSP/admission 통과 어려움) |
| 보안 사고 risk | 낮음 | 높음 (privileged) |
| layer cache | 약함 (S3에 cache 가능) | 호스트 docker 활용 가능 |
| 빌드 속도 | 보통 | 약간 빠름 |
| 컴플라이언스 | ★★★★ | ★★ (privileged 거부 정책 ↑) |

**Kaniko가 빌드 속도가 약간 느리지만, S3 cache (`--cache=true --cache-repo=...`) 활성화하면 base layer를 재사용해 50% 절감 가능**하다. 진짜 운영 환경에선 보안 ↑이 더 중요해서 modern CI는 모두 rootless로 이동 중이다.

---

## ⚖️ Trade-off

### Kaniko의 잃은 것

| 잃은 것 | 의미 |
|---|---|
| Layer cache 약함 | 빌드 매번 처음부터 (5~10분), S3 cache로 보완 가능 |
| 일부 Dockerfile 패턴 | `RUN --mount=type=cache` 등 BuildKit 전용 기능 X |
| 디버깅 약간 어려움 | debug image (`:debug`) 있어서 shell 가능 |

### Kaniko의 얻은 것

| 얻은 것 | 의미 |
|---|---|
| Rootless | 보안 ★★★★★ |
| K8s native | 운영 단순 |
| Dockerfile 100% | 학습 X |

가장 큰 trade-off는 **BuildKit-only 기능을 못 쓴다**는 점이다. `RUN --mount=type=cache /var/cache/apt` 같은 cache mount는 BuildKit 전용인데 Kaniko는 지원 안 한다. 기본 Dockerfile만 쓰면 호환 OK다.

---

## ⚠️ 함정 + 회복

| 함정 | 증상 | 해결 |
|---|---|---|
| **Kaniko `x509: certificate signed by unknown authority`** | Harbor cert 신뢰 X | `--skip-tls-verify` 또는 CA mount |
| **dockerconfigjson 잘못** | unauthorized | secret 키 이름/내용 확인 |
| **빌드 메모리 부족** | OOMKilled | Pod resources 늘림 |
| **빌드 시간 길어짐** | 매번 처음부터 | S3 cache (`--cache=true`) |
| **Kaniko 자체 버그** | 빌드 실패 | 버전 down (v1.22) 또는 issue 신고 |

가장 자주 만난 함정은 **자체 CA cert 신뢰** 문제다. Kaniko가 Harbor (자체 CA로 signed)에 push하려 할 때 `x509: certificate signed by unknown authority` 에러가 발생한다. 우리는 `--skip-tls-verify` 플래그로 회피했는데, 진짜 운영급에선 CA cert를 Kaniko Pod에 mount해 정상 검증하는 게 맞다.

---

## 🚀 확장 가능성

### Option A: ⭐ Layer cache (Ceph RGW S3에)

매 빌드 처음부터 base layer를 다시 빌드하는 게 빌드 시간의 큰 비중이다. Kaniko의 `--cache` 플래그로 layer cache를 Ceph RGW에 저장하면 50% 단축 가능. 비용 0이라 ROI가 좋다.

- 🎯 **추천 시점**: 빌드 빈도 ↑

### Option B: BuildKit (containerd buildkit) 전환

BuildKit은 Docker 18.06+의 새 builder다. Kaniko보다 빠르고 cache가 더 강력하고, BuildKit-only Dockerfile 문법도 지원한다. 단점은 K8s 통합이 추가 작업이고 학습 곡선이 있다.

- 🎯 **추천 시점**: 진짜 성능 최적화 + 학습 의지

### Option C: Buildah로 전환

Kaniko와 비슷한 rootless 빌더지만 cache가 좀 더 좋고 Red Hat 지원. Kaniko와 비교해 큰 차이 없어 마이그레이션 비용 대비 ROI가 작다. OpenShift 환경 정렬 같은 특별 이유 있을 때나 검토.

### Option D: dind (Docker-in-Docker) 부활

거의 안 함. modern CI는 rootless가 표준. 보안 정책 (PSP, Pod Security Admission)이 강한 환경에선 dind 자체가 거부된다.

### Option E: 클라우드 build 위탁 (Google Cloud Build, AWS CodeBuild)

빌드를 클라우드 SaaS에 위탁. 운영 부담 0이지만 비용 + 외부 의존. 빌드량 거대한 환경에서 검토.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 빌드 시간 ↓ 필요 | A (cache) ⭐ 가성비 |
| BuildKit-only 기능 필요 | B |
| Red Hat 환경 정렬 | C |
| 빌드 부담 0 | E |

---

## 🔗 다른 파트와의 연결

Kaniko는 Harbor에 image push하는 마지막 단계라 `04-harbor-registry.md`와 직결된다. 데이터 측면에선 Kaniko cache가 Ceph RGW S3에 저장될 수 있어 (`data-storage/04-s3-comparison.md`) 통합 패턴이 가능하다. 보안 측면에선 rootless 결정이 컨테이너 보안 정책과 직결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Docker-in-Docker가 더 빠르다는데 왜 Kaniko?**

A. **보안 ★★★★★ 차이**입니다. dind는 K8s에서 privileged 권한이 필요한데, 컨테이너 탈출 CVE 사고 시 호스트 root 권한이 노출됩니다. Kaniko는 rootless라 일반 워크로드와 동일 권한입니다. 빌드 속도는 S3 cache 활성화 (`--cache=true`)로 보완 가능합니다.

**Q2. Kaniko cache는 어떻게 설정하나요?**

A. **`--cache=true --cache-repo=harbor.kosa.team2/library/cache-repo`** 플래그를 추가합니다. 매 빌드마다 base layer를 Harbor에 저장하고 다음 빌드에서 재사용합니다. 30~50% 빌드 시간 단축 가능합니다. 우리는 아직 적용 안 했지만 빌드량 ↑되면 즉시 추가할 옵션입니다.

**Q3. Dockerfile 호환 100%인가요?**

A. **99% OK**입니다. 표준 Dockerfile instruction (`FROM`, `RUN`, `COPY`, multi-stage 등) 모두 지원합니다. **단 `RUN --mount=type=cache` 같은 BuildKit-only 문법은 X**입니다. 우리 ticket-app Dockerfile은 표준이라 호환됩니다.

**Q4. `--skip-tls-verify` 사용이 보안 위험 아닌가요?**

A. 학습 환경 단순화 차원입니다. **Harbor cert가 자체 CA로 signed돼서 Kaniko가 검증 못해서 우회**한 거고요. 진짜 운영급이면 (1) CA cert를 Kaniko Pod에 mount + `--registry-mirror` 설정, 또는 (2) Let's Encrypt cert로 Harbor 운영이 정석입니다. Phase 6에서 개선 가능합니다.

**Q5. K8s Pod 빌드라 매번 cold start인데 느리지 않나요?**

A. **container image pull은 빠릅니다** (Harbor 같은 LAN, 5초 이내). 진짜 느린 건 build 자체 (Python pip install 등 dependency 해결)인데, 이건 어느 빌드 도구든 동일한 비용입니다. **Layer cache로 base image를 재사용**하면 효과적으로 단축할 수 있습니다.
