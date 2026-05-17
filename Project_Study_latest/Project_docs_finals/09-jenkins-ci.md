# 09. Jenkins CI

> **이 챕터에서 다루는 것**
> "왜 GitHub Actions 시대에 Jenkins?"에 솔직히 답하고, Kubernetes plugin으로 빌드 Agent를 동적 Pod으로 띄우는 메커니즘, JCasC (코드로 Jenkins 설정), Kaniko로 rootless 이미지 빌드, credential 체계.

## 목차
1. [Jenkins, 사라지지 않은 이유](#1-jenkins-사라지지-않은-이유)
2. [왜 우리는 Jenkins?](#2-왜-우리는-jenkins)
3. [Jenkins on Kubernetes 아키텍처](#3-jenkins-on-kubernetes-아키텍처)
4. [Kubernetes plugin: Pod-as-Agent](#4-kubernetes-plugin-pod-as-agent)
5. [Kaniko: rootless 이미지 빌더](#5-kaniko-rootless-이미지-빌더)
6. [JCasC (Jenkins Configuration as Code)](#6-jcasc-jenkins-configuration-as-code)
7. [Credential 체계](#7-credential-체계)
8. [구축 절차](#8-구축-절차)
9. [트러블슈팅](#9-트러블슈팅)
10. [다음 챕터](#10-다음-챕터)

---

## 1. Jenkins, 사라지지 않은 이유

### 1.1 새 CI 도구들의 등장

| 도구 | 특징 |
|---|---|
| **GitHub Actions** | git/repo와 통합, YAML, 무료 | 
| **GitLab CI** | GitLab repo면 강력 |
| **Tekton** | K8s 네이티브, 클라우드 친화 |
| **Drone CI** | 단순, 컨테이너 기반 |
| **Argo Workflows** | K8s 네이티브 워크플로우 |
| **CircleCI / TravisCI** | SaaS, 빠른 셋업 |

### 1.2 그런데 왜 Jenkins?

| 이유 | 설명 |
|---|---|
| **거대한 plugin 생태계** | 2000+ 플러그인, 거의 모든 외부 시스템 연동 |
| **자기 호스팅** | 데이터 외부 노출 X (보안/규제 환경) |
| **표준 (역사)** | 한국 SI/금융권 등 보수적 환경에 광범위 |
| **legacy 호환** | 옛 Freestyle job, shell script 등 그대로 활용 |
| **groovy DSL** | 강력한 표현력 |
| **무료 OSS** | 라이선스 비용 X |

### 1.3 단점도 솔직히

- 무거움 (JVM)
- plugin 호환성 깨짐 빈번 (LTS 고정 권장)
- UI 구식 (Blue Ocean도 fully native는 아님)
- secret 관리 어색 (별도 plugin 필요)

---

## 2. 왜 우리는 Jenkins?

### 2.1 시나리오 적합성

| 요소 | Jenkins 적합성 |
|---|---|
| **온프레 학습용** | ✅ self-hosted 가능 |
| **K8s 친화** | ✅ Kubernetes plugin 강력 |
| **한국 채용시장 수요** | ✅ 여전히 큼 |
| **GitHub Actions 대비** | △ GHA가 더 modern이지만 의존 |
| **Argo Workflows 대비** | △ Argo가 K8s native지만 옛 도구 호환 ↓ |

### 2.2 결정의 솔직한 이유

> 💡 **솔직히**
> "현업에선 잘 안 쓴다"는 말도 듣지만, 한국 SI/금융권에 여전히 Jenkins. **그리고 학습 가치**: Pipeline DSL, Kubernetes plugin, credential 체계 등이 한 번 배워두면 다른 CI 도구로 확장이 쉽다.
>
> 또 이 프로젝트는 **온프레 자율성**이 중요. GitHub Actions는 GitHub 인프라 의존이라 외부망 다운 시 빌드 중단. Jenkins는 internal-only로 굴릴 수 있다.

---

## 3. Jenkins on Kubernetes 아키텍처

```
┌────────────── jenkins 네임스페이스 ──────────────┐
│                                                 │
│  [Ingress] jenkins.kosa.team2                   │
│       │                                         │
│       ▼                                         │
│  ┌──────────────────────┐                       │
│  │ Jenkins Controller   │  ← 영구 Pod (PVC mount)│
│  │ (StatefulSet)        │                       │
│  │  - Web UI            │                       │
│  │  - Pipeline 정의     │                       │
│  │  - Plugin 관리       │                       │
│  └──────────────────────┘                       │
│         │                                       │
│         │ (Build 시작 시)                       │
│         ▼                                       │
│  ┌──────────────────────┐                       │
│  │ Build Agent Pod      │ ← 빌드마다 새로 생성    │
│  │  (kaniko + git 등    │   (끝나면 자동 제거)    │
│  │   containers)        │                       │
│  └──────────────────────┘                       │
└─────────────────────────────────────────────────┘
```

### 3.1 Controller vs Agent

| 컴포넌트 | 역할 | 수명 |
|---|---|---|
| **Controller** (마스터) | Job 정의, UI, build 트리거, 결과 저장 | 영구 |
| **Agent** (executor) | 실제 빌드 실행 (compile, image build, push) | Job 단위 (임시) |

전통적으로 Agent는 별도 VM/머신. K8s 시대엔 **Pod**.

### 3.2 영구 데이터

Jenkins Controller의 `/var/jenkins_home`:
- Job 정의 (XML)
- 빌드 history
- 설치된 plugin
- 사용자 / credential

→ **PVC 필수** (재시작/이동에도 유지). 우리는 Ceph RBD `team2-rbd-block` 8GB.

---

## 4. Kubernetes plugin: Pod-as-Agent

### 4.1 동작 흐름

```
1. 개발자가 "Build Now" 클릭
2. Jenkins Controller가 Job 정의 읽음
   → agent 설정에 'kubernetes' 사용 명시
3. Controller가 K8s API에 Pod 생성 요청
4. K8s가 Pod schedule (워커 노드에)
5. Pod 안에 컨테이너들이 뜸 (kaniko, git, maven 등)
6. Controller가 SSH/JNLP로 Agent Pod에 연결
7. Pipeline의 stage들을 Pod에서 실행
8. Build 종료 → Controller가 결과 받음 → Pod 삭제
```

### 4.2 장점

- **clean room**: 매 빌드 새 Pod → "내 노트북에서는 됐는데"는 없음
- **scaling**: 빌드가 많아도 자동 Pod 증가
- **자원 효율**: 평소엔 Agent 0개
- **다양한 환경**: 빌드마다 다른 이미지 사용 가능 (Maven vs Node vs Go)

### 4.3 Pod template 예 (Pipeline 안)

```groovy
pipeline {
  agent {
    kubernetes {
      yaml '''
        apiVersion: v1
        kind: Pod
        spec:
          containers:
          - name: kaniko
            image: gcr.io/kaniko-project/executor:v1.23.2-debug
            command: ["sleep"]
            args: ["infinity"]
            volumeMounts:
            - name: docker-config
              mountPath: /kaniko/.docker
          - name: git
            image: alpine/git:latest
            command: ["sleep"]
            args: ["infinity"]
          volumes:
          - name: docker-config
            projected:
              sources:
              - secret:
                  name: harbor-creds-dockerconfigjson
                  items:
                  - key: .dockerconfigjson
                    path: config.json
      '''
    }
  }
  stages {
    stage('foo') {
      steps {
        container('git') { sh 'git clone ...' }
      }
    }
  }
}
```

📌 `container('name')` 블록으로 어느 컨테이너에서 실행할지 선택.

---

## 5. Kaniko: rootless 이미지 빌더

### 5.1 이미지 빌드의 옵션

| 도구 | root 필요? | K8s에서 안전? |
|---|---|---|
| **Docker (DinD)** | ✅ (privileged) | ❌ 컨테이너 탈출 위험 |
| **BuildKit** | △ | △ |
| **Buildah** | ❌ (rootless 가능) | ✅ |
| **Kaniko** | ❌ | ✅ |

### 5.2 Kaniko 동작

```
1. Dockerfile 분석 (각 RUN, COPY 등)
2. base image의 layer를 다운로드
3. 각 명령을 자체 sandbox에서 실행 (privileged 없이)
4. 결과 layer를 추출
5. 새 layer + manifest 생성
6. registry에 push
```

위 모든 게 **컨테이너 안에서**, **root 없이** 가능. 따라서 K8s Pod에 안전하게 띄울 수 있음.

### 5.3 Harbor 인증

Kaniko가 push할 때 docker config 필요:
```json
{
  "auths": {
    "harbor.kosa.team2": {
      "auth": "<base64(user:pass)>"
    }
  }
}
```

K8s Secret으로 주입:
```bash
kubectl create secret -n jenkins docker-registry harbor-creds-dockerconfigjson \
  --docker-server=harbor.kosa.team2 \
  --docker-username=admin \
  --docker-password=kosa1004
```

Pod template에서 `/kaniko/.docker/config.json`으로 mount.

### 5.4 자체 CA 신뢰

Kaniko가 Harbor cert를 신뢰 안 하면 push 실패. 옵션:

a) **`--skip-tls-verify`**: 간단, 운영에는 비추
b) **CA mount + `--registry-certificate=harbor.kosa.team2=/path/ca.crt`**: 권장

우리는 임시로 (a). 향후 (b)로 전환.

---

## 6. JCasC (Jenkins Configuration as Code)

### 6.1 문제

Jenkins 설정 (job, credential, plugin, security)을 UI로 클릭클릭해서 만들면:
- 재현 불가 (DR 시 처음부터)
- 변경 history X
- 환경 간 일관성 X

### 6.2 JCasC 해법

설정을 YAML로:

```yaml
jenkins:
  systemMessage: "KOSA Team2 Jenkins"
  numExecutors: 0
  mode: EXCLUSIVE
  clouds:
    - kubernetes:
        name: kubernetes
        namespace: jenkins
        jenkinsUrl: http://jenkins.jenkins.svc.cluster.local:8080
        connectTimeout: 5
        readTimeout: 15

unclassified:
  location:
    url: https://jenkins.kosa.team2

security:
  apiToken:
    creationOfLegacyTokenEnabled: false
```

Helm chart의 `controller.JCasC.configScripts`로 주입 가능.

---

## 7. Credential 체계

### 7.1 Credential 종류

| Kind | 용도 |
|---|---|
| **Username with password** | DB 접속, registry 로그인 |
| **SSH Username with private key** | git push, SSH 배포 |
| **Secret text** | API 토큰 |
| **Secret file** | kubeconfig 등 파일 |
| **Certificate** | mTLS |

### 7.2 우리 등록 credential

| ID | Kind | 용도 |
|---|---|---|
| `harbor-creds` | Username/Password | Harbor 로그인 (admin/kosa1004) |
| `kosa-gitops-ssh` | SSH Private Key | kosa-gitops repo push |

### 7.3 Pipeline에서 사용

**Username/Password** (`withCredentials`):
```groovy
withCredentials([usernamePassword(
  credentialsId: 'harbor-creds',
  usernameVariable: 'HARBOR_USER',
  passwordVariable: 'HARBOR_PASS'
)]) {
  sh 'docker login harbor.kosa.team2 -u $HARBOR_USER -p $HARBOR_PASS'
}
```

**SSH key**:
```groovy
withCredentials([sshUserPrivateKey(
  credentialsId: 'kosa-gitops-ssh',
  keyFileVariable: 'SSH_KEY'
)]) {
  sh '''
    export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no"
    git clone git@github.com:kosacloudteam2/kosa-gitops.git
  '''
}
```

> ⚠️ **`sshagent` 함정**: `sshagent` step은 별도 plugin 필요. 없으면 `not found` 에러. 우리는 `withCredentials([sshUserPrivateKey(...)])` 사용.

---

## 8. 구축 절차

### 8.1 ArgoCD Application

`~/kosa-gitops/apps/_applications/jenkins.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: jenkins, namespace: argocd }
spec:
  project: default
  source:
    repoURL: https://charts.jenkins.io
    chart: jenkins
    targetRevision: 5.x.x
    helm:
      values: |
        controller:
          admin:
            username: admin
            password: kosa1004        # ← chart 5.x+ 에서는 controller.admin (옛 adminUser X)
          image:
            tag: "lts-jdk17"          # ← LTS 고정 (2.492.x 호환성 문제 회피)
          numExecutors: 2
          nodeSelector:
            workload-type: system     # ← sys1 격리
          installPlugins:
            - kubernetes
            - workflow-aggregator
            - git
            - configuration-as-code
            - blueocean
            - credentials-binding
            - ssh-agent
          ingress:
            enabled: true
            hostName: jenkins.kosa.team2
            ingressClassName: haproxy
            annotations:
              kubernetes.io/ingress.class: haproxy
              cert-manager.io/cluster-issuer: kosa-ca-issuer
        
        persistence:
          enabled: true
          storageClass: team2-rbd-block
          size: 8Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: jenkins
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jsonPointers: [/spec/volumeClaimTemplates]
    - kind: Secret
      jsonPointers: [/data]
```

### 8.2 Kaniko용 Secret

```bash
kubectl create secret -n jenkins docker-registry harbor-creds-dockerconfigjson \
  --docker-server=harbor.kosa.team2 \
  --docker-username=admin \
  --docker-password=kosa1004
```

### 8.3 첫 접속

```bash
# 초기 admin
kubectl exec -n jenkins -it jenkins-0 -- \
  cat /run/secrets/additional/chart-admin-password
# 또는 위 values에 박은 kosa1004
```

https://jenkins.kosa.team2 → admin / kosa1004

### 8.4 Credential 등록

UI → Manage Jenkins → Credentials → System → Global:
- `harbor-creds` (Username/Password)
- `kosa-gitops-ssh` (SSH Private Key)

### 8.5 글로벌 SSH 설정

Manage Jenkins → Security → Git Host Key Verification Strategy → **Accept first connection**

(안 그러면 `git clone github.com:...` 시 host key verification failed)

### 8.6 첫 Pipeline 만들기

New Item → Pipeline → 이름 `kosa-tickets-ci` → Pipeline script:
- (다음 챕터 [10-cicd-pipeline.md](10-cicd-pipeline.md) 에 전문 있음)

Save → Build Now → console output 확인.

---

## 9. 트러블슈팅

### 9.1 Login Failed (반복)

원인 후보:
- chart 5.x+에서 `adminUser` deprecated → `controller.admin.username/password`로 변경
- 이미 install된 인스턴스라 secret이 옛 값 보유

해결:
```bash
# PVC 완전 초기화 (데이터 손실 주의)
kubectl delete pvc -n jenkins --all
kubectl delete pod -n jenkins jenkins-0   # 재생성됨
```

### 9.2 plugin 호환성 깨짐 (2.492.x)

증상: 빈 UI, 일부 plugin disable.

원인: 최신 Jenkins core가 일부 plugin과 호환 X.

해결: `image.tag: "lts-jdk17"` 로 LTS 고정.

### 9.3 Build Agent Pod 안 뜸

```bash
kubectl get pods -n jenkins
# kaniko-xxxx 가 안 보임

# Jenkins log
kubectl logs -n jenkins jenkins-0 --tail=200
```

흔한 원인:
- service account `jenkins`의 RBAC 부족
- Kubernetes plugin 설정 (jenkinsUrl 오타)
- nodeSelector 매칭 노드 없음

### 9.4 sshagent not found

→ `withCredentials([sshUserPrivateKey(...)])` 로 대체.

### 9.5 GitHub Host Key Verification Failed

→ Security 설정 "Accept first connection" 또는 pipeline에서:
```bash
mkdir -p ~/.ssh
ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
```

### 9.6 Kaniko push x509

→ `--skip-tls-verify` (간단) 또는 CA mount (권장).

### 9.7 Build "Waiting for executor"

원인:
- `controller.numExecutors`가 너무 작음
- K8s에 Pod 만들 자원 없음
- K8s plugin이 응답 안 함

확인: `kubectl describe pod -n jenkins`로 schedule 시도 결과.

### 9.8 PVC가 Pending

storageClass 오타 또는 ceph-csi 문제. [04-ceph.md](04-ceph.md) §12 참고.

### 9.9 Jenkins 너무 느림

원인 후보:
- JVM heap 작음 (`-Xmx` 환경변수)
- plugin 너무 많음 (사용 안 하는 거 제거)
- PVC IO 느림 (Ceph slow ops)

---

## 10. 다음 챕터

→ **[10. CI/CD 파이프라인](10-cicd-pipeline.md)**

kosa-tickets 데모 앱의 end-to-end 파이프라인 (GitHub → Jenkins → Kaniko → Harbor → GitOps → ArgoCD → K8s), Jenkinsfile 라인별 해설, Source repo와 GitOps repo 분리 이유.
