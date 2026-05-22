# 06. 파이프라인 E2E 흐름

> ⭐ **한 줄 요약**: **git push → Jenkins polling 감지 → Kaniko build → Harbor push → kosa-gitops image tag 갱신 → ArgoCD sync → Pod rolling update**. 평균 5~10분.

---

## 🎯 전체 흐름 (kosa-tickets 예)

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

---

## ⏱️ 단계별 소요 시간

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

→ **즉시 트리거 (webhook 등) 도입하면 1~2분 단축 가능**

---

## 🛠️ 컴포넌트별 책임

### Jenkins
- SCM polling
- Build orchestration (Pipeline)
- Credential 관리 (harbor-creds, kosa-gitops-ssh)
- Agent Pod 생성/삭제

### Kaniko
- Docker build (rootless)
- Harbor push

### Git Container (alpine/git)
- Source checkout
- GitOps repo clone + 수정 + push

### Harbor
- Image 저장 (Ceph RGW S3)
- Trivy 스캔 (옵션)
- Pull request 처리

### ArgoCD
- GitOps repo polling
- Application sync
- Drift 자동 회복

### K8s
- Rolling update
- Pod scheduling
- Service endpoint 관리

---

## 🔍 Pipeline 코드 (Jenkinsfile)

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

자세한 코드는 CLAUDE.md `## CI/CD 파이프라인` 섹션 참고.

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

---

## 🚀 확장 가능성

### Option A: ⭐ Webhook 트리거 (polling 1~2분 → 즉시)
- 위 02 문서 참고
- 🎯 **추천 시점**: off-prem 환경

### Option B: Staging 환경 추가
- 현재: production 바로 deploy
- 확장: staging namespace 분리, test 후 prod
- 작업: kosa-gitops에 overlays/staging/, overlays/prod/ 추가
- 🎯 **추천 시점**: 운영급 진입

### Option C: Argo Rollouts (canary 배포)
- 위 05 문서 참고
- 🎯 **추천 시점**: 잦은 배포 + 안전성

### Option D: PR check 추가
- 현재: main push 시 자동 build
- 확장: PR open 시 build 후 status check
- 🎯 **추천 시점**: 팀 협업 강화

### Option E: 의존성 캐시 (Maven/npm/pip 등)
- 현재: 매 빌드 처음부터
- 확장: cache PVC 또는 S3
- 🎯 **추천 시점**: build 시간 ↓ 필요

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| build 자주 + 즉시성 | A |
| 운영급 진입 | B + C |
| 빌드 시간 ↑ | E |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔧 자기 모두 | 1~10 단계의 각 컴포넌트 |
| 💾 데이터 | Harbor → Ceph RGW |
| 🏛️ 아키텍처 | sys1에 Jenkins/Harbor/ArgoCD 배치 |
| 🔒 보안 | imagePullSecret, RBAC, credentials |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. push 후 deploy까지 평균 시간?**
A. 5~7분 (polling 1~2분 + build 2~5분 + ArgoCD polling 0~3분 + rolling 1분). 즉시 webhook이면 3~5분 단축.

**Q2. 빌드 fail 시 어떻게?**
A. Jenkins UI에 RED 표시 → 개발자가 console output 확인 + 수정 + 다시 push. (Jenkins email 알림 가능 — 현재 미설정)

**Q3. 같은 image tag 다시 build 가능?**
A. BUILD_NUMBER가 자동 증가라 매번 새 tag. 같은 git commit 다시 build 시도 시 `:N+1` tag. ArgoCD가 새 tag 감지 → re-deploy.

**Q4. rollback은?**
A. (1) Git revert + push → 자동 rollback, (2) Harbor의 옛 image tag로 deployment 수정 + commit, (3) ArgoCD UI에서 "Rollback" 클릭 (이전 deploy 시점으로).

**Q5. 동시에 여러 개 push되면?**
A. Jenkins가 큐잉. K8s plugin이 max executors 한도 (현재 2)로 동시 실행 제한. 더 많으면 queue 대기.

**Q6. 사용자 입장에서 다운타임?**
A. 거의 0. Rolling update + readiness probe로 새 Pod이 ready된 후 old Pod 종료. graceful shutdown (15초) 보장.
