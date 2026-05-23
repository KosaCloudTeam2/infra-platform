# 06. 파이프라인 E2E 흐름

> ⭐ **한 줄 요약**: **git push → Jenkins polling 감지 → Kaniko build → Harbor push → kosa-gitops image tag 갱신 → ArgoCD sync → Pod rolling update**. 평균 5~10분에 코드가 production에 반영된다. 각 컴포넌트가 명확한 역할을 가지고 chain으로 동작한다. **2026-05-23 admin-app도 동일 패턴으로 통합** — Jenkins job config.xml 복사 + sed 치환으로 5분 만에 새 pipeline 생성.

---

## 🎯 전체 흐름 (kosa-tickets 예시)

CI/CD의 진짜 가치는 개별 도구가 아니라 **이들이 어떻게 자동으로 chain되는지**에 있다. 우리 파이프라인은 11단계로 흐른다.

```
[1] 개발자: git push to kosa-tickets repo (main)
        │
        │ (1~2분 polling 지연)
        ▼
[2] Jenkins: SCM polling 감지 → "Changes found"
        │
        ▼
[3] Jenkins K8s plugin: dynamic agent Pod 생성 (Kaniko + git container)
        │
        ▼
[4] git container: source checkout
        │
        ▼
[5] Kaniko container: docker build (Dockerfile) → Harbor push
        │ image: harbor.kosa.team2/library/kosa-tickets:<BUILD_NUMBER>
        ▼
[6] git container: kosa-gitops repo clone → sed로 image tag 갱신 → commit + push
        │
        ▼
[7] ArgoCD: kosa-gitops repo polling (3분 주기) → 변경 감지
        │
        ▼
[8] ArgoCD: ticket-app Application sync
        │ K8s Deployment manifest 업데이트
        ▼
[9] K8s: rolling update (default strategy)
        │ 새 Pod 생성 (Harbor에서 새 image pull)
        │ old Pod 종료 (graceful)
        ▼
[10] HAProxy Ingress: 새 Pod 트래픽 라우팅
        │
        ▼
[11] 사용자: 새 버전 응답
```

이 11단계가 자동으로 흐르는 게 GitOps의 핵심이다. 개발자는 git push만 하면 나머지는 모두 자동이다.

---

## 🧩 admin-app — 같은 패턴 재사용 ⭐ (2026-05-23 추가)

ticket-app의 CI/CD 패턴이 잘 동작하니, **admin-app도 동일 패턴**으로 통합. 새 pipeline을 처음부터 작성할 필요 없이 config.xml 복사 + sed 치환으로 5분 만에 생성.

```bash
# 1. 기존 ticket-app job config 다운로드
curl -s -k -u admin:kosa1004 \
  https://jenkins.kosa.team2/job/kosa-tickets-ci/config.xml > /tmp/job.xml

# 2. sed로 4가지 치환
sed -e 's|kosa-tickets-ci|kosa-tickets-admin-ci|g' \
    -e 's|kosa-tickets.git|kosa-tickets-admin.git|g' \
    -e 's|library/kosa-tickets|library/admin-app|g' \
    -e 's|apps/ticket-app/deployment.yaml|apps/admin-app/20-deployment.yaml|g' \
    /tmp/job.xml > /tmp/admin-job.xml

# 3. Crumb 받고 새 job 생성
COOKIE=$(mktemp)
CRUMB=$(curl -s -k -c $COOKIE -u admin:kosa1004 \
  "https://jenkins.kosa.team2/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")
curl -s -k -b $COOKIE -u admin:kosa1004 -H "$CRUMB" \
  -H "Content-Type: application/xml" --data-binary @/tmp/admin-job.xml \
  "https://jenkins.kosa.team2/createItem?name=kosa-tickets-admin-ci"
```

새 source repo (`kosa-tickets-admin`)에 push하면 Jenkins SCM polling 감지 → Kaniko build → Harbor push → GitOps `apps/admin-app/20-deployment.yaml`의 image tag 자동 갱신 → ArgoCD sync → admin-app pod rollout. **검증된 패턴의 재사용으로 새 service 통합 시간 ↓**.

---

## ⏱️ 단계별 소요 시간

각 단계가 얼마나 걸리는지 보면 어디가 병목인지 알 수 있다.

| 단계 | 시간 | 비고 |
|---|---|---|
| 1. git push | 즉시 | |
| 2. Jenkins polling | 0~120초 | `H/2 * * * *` (2분) |
| 3. Agent Pod 생성 | 30초 | image pull cache 시 |
| 4. Source checkout | 5초 | git clone |
| 5. Kaniko build + push | 2~5분 | 의존성 양에 따라 |
| 6. GitOps update | 10초 | sed + commit + push |
| 7. ArgoCD polling | 0~180초 | 3분 default |
| 8. ArgoCD sync | 10초 | manifest apply |
| 9. Pod rolling | 30~60초 | readiness probe |
| 10. Traffic 전환 | 즉시 | Service endpoint 갱신 |
| **합계** | **5~12분** | 평균 ~7분 |

가장 큰 비중은 **Kaniko build (2~5분)**과 **두 polling 지연 (Jenkins polling + ArgoCD polling, 합 최대 5분)**이다. **Webhook으로 polling을 즉시화하면 1~2분 단축** 가능하다 (즉시 트리거 시 3~5분 가능).

---

## 🛠️ 컴포넌트별 책임

각 도구가 명확한 역할을 가지고 협업한다.

### Jenkins
- **SCM polling**으로 변경 감지
- **Pipeline orchestration** (Jenkinsfile 실행)
- **Credential 관리** (harbor-creds, kosa-gitops-ssh 등)
- **Agent Pod 생성/삭제** (K8s plugin)

### Kaniko
- **Docker build** (rootless, Pod 안에서)
- **Harbor push** (--skip-tls-verify로 자체 CA 우회)

### Git Container (alpine/git)
- **Source checkout** (kosa-tickets repo)
- **GitOps repo clone + 수정 + push** (kosa-gitops repo의 deployment.yaml 갱신)

### Harbor
- **Image 저장** (Ceph RGW S3 backend)
- **Trivy 스캔** (옵션)
- **Pull request 처리** (K8s 노드에서 image pull)

### ArgoCD
- **GitOps repo polling** (3분 주기)
- **Application sync** (manifest apply)
- **Drift 자동 회복** (selfHeal)

### K8s
- **Rolling update** (Pod 점진 교체)
- **Pod scheduling** (nodeSelector + anti-affinity)
- **Service endpoint 관리** (새 Pod 등록, old Pod 제외)

---

## 🔍 Pipeline 코드 (Jenkinsfile)

실제 우리 Jenkinsfile 구조다.

```groovy
pipeline {
  agent {
    kubernetes {
      yaml '''
        spec:
          containers:
          - name: kaniko
            image: gcr.io/kaniko-project/executor:v1.23.2-debug
            command: ["sleep"]
            args: ["infinity"]
          - name: git
            image: alpine/git:latest
            command: ["sleep"]
            args: ["infinity"]
      '''
    }
  }
  environment {
    IMAGE  = "harbor.kosa.team2/library/kosa-tickets"
    TAG    = "${env.BUILD_NUMBER}"
  }
  stages {
    stage('Checkout Source') { ... }
    stage('Build & Push to Harbor') { ... }
    stage('Update GitOps') { ... }
  }
}
```

agent 정의가 K8s Pod template인 점이 중요하다. **Kaniko + git 두 컨테이너가 같은 Pod 안에 있어 file system을 공유**한다. 각 stage가 어느 container에서 실행될지 `container('kaniko') { ... }` 같은 블록으로 지정한다.

자세한 코드는 `CLAUDE.md`의 "## CI/CD 파이프라인" 섹션에 있다.

---

## ⚠️ 함정 + 회복

| 함정 | 증상 | 해결 |
|---|---|---|
| **Kaniko `x509: certificate signed by unknown authority`** | Harbor cert 신뢰 X | `--skip-tls-verify` 또는 CA mount |
| **git push fails** | GitHub SSH key 인증 X | Jenkins credential 확인, `ssh-keyscan github.com` |
| **GitOps repo conflict** | 동시 push 충돌 | Jenkins retry 또는 `git pull --rebase` |
| **ArgoCD sync fail** | OutOfSync 영원히 | `argocd app sync` 수동, helm.values 형식 확인 |
| **Pod 새 image pull 실패** | imagePullSecret 누락 | namespace에 `harbor-pull-secret` 생성 |
| **Rolling update stuck** | new Pod이 Ready 안 됨 | Pod 로그 확인 (앱 startup 실패) |

가장 자주 만난 함정은 **Kaniko cert** 문제다. 자체 CA로 signed된 Harbor cert를 Kaniko가 신뢰 못해서 `x509: certificate signed by unknown authority` 발생. 우리는 `--skip-tls-verify`로 우회했지만, 운영급에선 CA cert를 Pod에 mount해 정상 검증이 정석이다.

GitOps repo conflict도 가끔 발생한다. 여러 build가 동시에 같은 deployment.yaml을 sed로 수정하면 push 충돌. Jenkins가 retry해주지만 가끔 stuck. 해결은 sed → commit → push를 한 atomic 단계로 만들고, conflict 시 `git pull --rebase` 후 다시 push.

---

## 🚀 확장 가능성

### Option A: ⭐ Webhook 트리거 (polling 1~2분 → 즉시)

위 02 문서에서 다룬 패턴. NAT 풀린 환경 (off-prem 이전)에서 Edge HAProxy에 jenkins 노출 + GitHub Webhook 설정. 1~2분 polling 지연을 즉시로 단축. 평균 빌드 시간이 5~12분 → 3~10분으로 줄어든다.

- 🎯 **추천 시점**: off-prem 환경

### Option B: Staging 환경 추가

현재는 main push → production 바로 deploy다. 운영급에선 staging namespace 분리해서 test 후 prod 승급이 안전하다. 작업: kosa-gitops에 `overlays/staging/`, `overlays/prod/` 추가 후 ArgoCD Application 분리.

- 🎯 **추천 시점**: 운영급 진입

### Option C: Argo Rollouts (canary 배포)

새 버전을 5% → 25% → 100% 점진 배포. Prometheus 메트릭 (에러율, latency)이 자동 평가되고 사고 시 자동 rollback. 잦은 배포 + 안전성 ↑ 시 유용.

### Option D: PR check 추가

현재는 main push 시만 build. 확장으론 PR open 시 build + status check 자동화. 팀 협업이 활발해지면 유용.

### Option E: 의존성 캐시 (Maven/npm/pip 등)

매 빌드마다 dependency를 다운받는 게 build 시간의 큰 비중. cache PVC 또는 S3로 dependency를 재사용하면 단축 가능.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| build 자주 + 즉시성 | A (Webhook) |
| 운영급 진입 | B (Staging) + C (Rollouts) |
| 빌드 시간 ↑ | E (Cache) |

---

## 🔗 다른 파트와의 연결

이 파이프라인 흐름은 CI/CD 파트의 모든 컴포넌트가 chain되는 결과물이다. Jenkins (`01-jenkins-vs-github-actions.md`)가 시작점, Kaniko (`03-jenkins-build-tools.md`)가 build, Harbor (`04-harbor-registry.md`)가 저장소, ArgoCD (`05-argocd-gitops.md`)가 배포 자동화. 데이터 측면에선 Harbor → Ceph RGW (`data-storage/04-s3-comparison.md`)가 연결되고, 아키텍처 측면에선 sys1 배치 (`architecture/02-kubernetes-design.md`)가 모든 도구의 배치를 결정한다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. push 후 deploy까지 평균 시간은 얼마나 걸리나요?**

A. **5~7분**입니다. polling 지연 1~2분 + build 2~5분 + ArgoCD polling 0~3분 + rolling 1분. **즉시 webhook이면 3~5분으로 단축** 가능합니다. 학습 환경엔 polling으로 충분합니다.

**Q2. 빌드 fail 시 어떻게 처리되나요?**

A. **Jenkins UI에 RED 표시** + 개발자가 console output 확인 + 코드 수정 + 다시 push. Jenkins email 알림도 가능 (현재 미설정). 진짜 운영급은 Slack/PagerDuty 통합으로 빌드 실패가 즉시 팀에 통보됩니다.

**Q3. 같은 image tag로 다시 build 가능한가요?**

A. **BUILD_NUMBER가 자동 증가**라 매번 새 tag가 생성됩니다. 같은 git commit을 다시 build하면 `:N+1` tag. ArgoCD가 새 tag를 감지해 re-deploy합니다. 이렇게 하는 이유는 image immutability를 보장하기 위함입니다.

**Q4. Rollback은 어떻게 하나요?**

A. 세 가지 방법입니다. **(1) Git revert + push** — 자동 rollback (가장 GitOps적). **(2) Harbor의 옛 image tag로 deployment 수정 + commit** — 명시적. **(3) ArgoCD UI에서 "Rollback" 클릭** — 이전 deploy 시점으로 즉시. 가장 추천하는 건 (1) Git revert로 git이 진리 유지.

**Q5. 동시에 여러 push가 발생하면?**

A. **Jenkins가 큐잉**합니다. K8s plugin이 max executors 한도 (현재 2)로 동시 실행을 제한하고, 그 이상은 queue 대기. 진짜 운영급은 max executors를 늘리거나 빌드 자원을 더 할당합니다.

**Q6. 사용자 입장에서 다운타임이 있나요?**

A. **거의 0입니다**. Rolling update + readiness probe로 새 Pod이 ready된 후 old Pod이 종료됩니다. graceful shutdown 시간 (default 30초)도 있어 진행 중 request도 마무리됩니다. 사용자는 보통 모릅니다.
