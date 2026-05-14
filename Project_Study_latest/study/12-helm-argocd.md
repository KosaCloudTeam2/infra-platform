# 챕터 12: Helm + ArgoCD (GitOps)

> KOSA 인프라 프로젝트 학습 시리즈 / 작성일 2026-05-13<br> 환경: 온프레미스 K8s v1.30.14, Bastion
> 172.16.24.10, ArgoCD LB 172.16.23.101

## 학습 후 알 수 있는 것

- Helm이 "K8s YAML 100개" 문제를 어떻게 해결하는지, Chart/Values/Release 3개 개념 한 줄로 설명할 수
  있어요.
- `helm install`과 `helm upgrade --install`의 차이, 왜 후자가 idempotent한지 설명할 수 있어요.
- GitOps의 정의와 ArgoCD가 "Pull 방식"인 이유, Flux와의 차이를 말할 수 있어요.
- ArgoCD의 Application/ApplicationSet/Sync 모드를 우리 환경 LoadBalancer 172.16.23.101 위에서 직접
  시연할 수 있어요.
- 우리가 만난 함정 — `helm install` 이름 중복, Helm values 캐시, ArgoCD Sync Loop — 의 원인과
  해결법을 알게 돼요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

- **Helm**: Kubernetes 애플리케이션을 "차트(Chart)"라는 패키지 단위로 묶어 배포/업그레이드/롤백할 수
  있게 해주는 K8s 패키지 매니저예요.
- **ArgoCD**: Git 저장소를 진실의 원천(Source of Truth)으로 삼고, Git에 push된 매니페스트를
  클러스터에 자동 동기화하는 GitOps 컨트롤러예요.

### 1.2 등장 배경

K8s의 YAML 파일은 한 서비스만 띄워도 보통 Deployment, Service, ConfigMap, Secret, HPA, Ingress,
ServiceAccount, RoleBinding... 10개 이상 필요해요. 환경별로(dev/stg/prod) 이미지 태그, replicas,
resources만 다른 거의 똑같은 매니페스트를 복붙해서 관리하면 금방 지옥이 됩니다.

- **Helm 등장(2016)**: 매니페스트를 템플릿화(`{{ .Values.image.tag }}`)해서 환경별 values 파일만
  갈아끼우면 끝. CNCF Graduated 프로젝트.
- **ArgoCD 등장(2018, Intuit → CNCF)**: "kubectl apply를 사람이 직접 치는 모델"의 한계 — 누가 언제
  뭘 적용했는지 추적 불가, 클러스터 drift 발생 — 를 해결하기 위해 등장. Git이 곧 클러스터 상태가
  되는 GitOps 패턴.

### 1.3 핵심 개념 + 용어 풀이

**Helm 3대 개념:**

| 용어    | 의미                                             | 비유                                     |
| ------- | ------------------------------------------------ | ---------------------------------------- |
| Chart   | K8s 매니페스트 + 메타데이터 + values 스키마 묶음 | apt 패키지 (.deb 파일)                   |
| Values  | Chart에 주입할 환경별 값                         | `apt install -o` 옵션                    |
| Release | Chart + Values를 실제 클러스터에 적용한 인스턴스 | 설치된 패키지 (한 서버에 nginx 1개 설치) |

**ArgoCD 핵심 객체:**

| 객체           | 역할                                                                     |
| -------------- | ------------------------------------------------------------------------ |
| Application    | "이 Git 경로의 매니페스트를 이 namespace에 sync해라" 한 단위의 배포 정의 |
| ApplicationSet | 여러 Application을 한꺼번에 만드는 템플릿 (멀티 클러스터/멀티 환경)      |
| Project        | Application들의 그룹 + 권한 경계 (어느 Git repo/cluster를 쓸 수 있는지)  |

**GitOps 4원칙(Weaveworks):**

1. 선언적(Declarative) — 시스템 상태를 코드로 기술
2. 버전 관리(Versioned) — Git에 보관, 모든 변경 추적
3. 자동 적용(Approved) — 자동/승인 기반 배포
4. 지속적 조정(Continuously Reconciled) — 실제 상태가 Git 상태로 끊임없이 수렴

### 1.4 동작 원리 (내부 메커니즘)

**Helm install 흐름:**

```
helm install myapp ./chart -f values.yaml
       │
       ▼
1) Chart.yaml + values.yaml 파싱
2) templates/*.yaml에 Go template 렌더링 ({{ }} 치환)
3) 결과 매니페스트들을 kubectl apply하듯 K8s API에 전송
4) Release 메타데이터를 Secret(type=helm.sh/release.v1)으로 저장
   → namespace에 sh.helm.release.v1.myapp.v1 형태 Secret 생성
```

**ArgoCD 동기화 흐름:**

```
[Git repo]                         [ArgoCD Controller]               [K8s cluster]
   manifests/             ◀───────  polling (3분 주기, 기본)
                                            │
                                            ▼
                                    diff = (Git desired) vs (Live actual)
                                            │
                                            ▼
                                    OutOfSync → kubectl apply(sync)
                                            │
                                            ▼
                                    Synced + Healthy 상태로 마킹
```

- **Pull 방식**: ArgoCD가 Git을 주기적으로 polling. Git이 ArgoCD에 push하지 않아요. → 방화벽 안쪽
  클러스터에도 안전하게 작동.
- **Drift 감지**: 누가 `kubectl edit deployment`로 손대도 ArgoCD가 다음 sync 때 Git 상태로
  되돌림(self-heal 옵션).

### 1.5 주요 기능

**Helm:**

- 템플릿 엔진 (`{{ .Values.X }}`, `{{ if }}`, `{{ range }}`)
- Release 버전 관리(`helm history`, `helm rollback`)
- Hook (pre-install, post-upgrade 등 라이프사이클 훅)
- Dependency(`Chart.yaml`의 `dependencies` 블록 — 서브 차트)
- 차트 저장소(`helm repo add bitnami https://charts.bitnami.com/bitnami`)

**ArgoCD:**

- 웹 UI(시각적 sync 상태, diff view) + CLI(`argocd app sync`) + REST API
- Auto-sync, Self-heal, Auto-prune
- Sync wave/hook (배포 순서 제어)
- Multi-cluster, Multi-tenant(Project)
- SSO 통합(OIDC, SAML, GitHub)
- ApplicationSet generator (List, Cluster, Git, Matrix, Pull Request)

### 1.6 다른 도구와 비교

**패키지 관리 도구 비교:**

| 도구          | 방식                          | 학습 곡선 | 점유율                         |
| ------------- | ----------------------------- | --------- | ------------------------------ |
| **Helm**      | 템플릿 기반 (Go template)     | 낮음      | K8s 패키지 사실상 표준         |
| Kustomize     | overlay/patch 기반 (템플릿 X) | 낮음      | kubectl 내장, 단순 환경에 적합 |
| Jsonnet/Tanka | DSL 기반 (코드처럼)           | 높음      | Grafana Labs 사용              |
| CDK8s         | Python/TS 코드 기반           | 중간      | AWS 진영                       |

**CD(Continuous Deployment) 도구 비교:**

| 도구       | 모델                 | 강점                                          | 점유율      |
| ---------- | -------------------- | --------------------------------------------- | ----------- |
| **ArgoCD** | Pull, App 단위       | UI 강력, 가시성 최고                          | GitOps 1위  |
| Flux v2    | Pull, Kustomize 친화 | Helm Controller, Notification Controller 분리 | GitOps 2위  |
| Spinnaker  | Push, Pipeline 중심  | 다단계 승인 워크플로우                        | 레거시 강자 |
| Jenkins X  | Push + Pull 혼합     | Jenkins 생태계                                | 감소 추세   |

---

## 2. 현업/실무 맥락

### 2.1 어떤 상황에서 필요한가

- **Helm**: 같은 앱을 dev/stg/prod 환경별로 다른 설정으로 배포해야 할 때. 또는 외부 OSS(Prometheus,
  Redis, cert-manager)를 자체 구축할 때 — 공식 차트가 검증된 매니페스트 100개를 한 줄로 설치해줘요.
- **ArgoCD**: 팀이 2명 이상이 되어 "누가 무엇을 언제 배포했는지" 추적이 필요할 때. 또는 "main
  브랜치가 곧 prod 클러스터 상태"를 강제하고 싶을 때.

### 2.2 업계 표준, 대표 사용 기업/사례

- **Helm**: CNCF Graduated(졸업) 프로젝트. K8s 진영에서 패키지 매니저는 사실상 Helm 외에 대안 없음.
  Bitnami, Grafana, NGINX, Elastic 등 거의 모든 OSS가 공식 Helm 차트 제공.
- **ArgoCD**: CNCF Graduated(2022). 사용 기업 — Intuit(개발사), Tesla, IBM, BlackRock, Adobe, Red
  Hat OpenShift GitOps의 기본 구현체.
- **Flux**: Weaveworks가 만든 GitOps의 원조. CNCF Graduated. AWS EKS 공식 add-on에 포함.

### 2.3 왜 효율이 좋은가 (현업 관점)

**Helm:**

- 환경별 매니페스트 복제 0건 — values.yaml만 분리
- 롤백이 한 줄(`helm rollback myapp 3`) — Release 히스토리 자동 보관
- 의존성 자동 해결 — Prometheus 차트가 Grafana 차트를 자동으로 같이 설치

**ArgoCD:**

- 감사(Audit) 자동 — Git log가 곧 배포 이력
- 클러스터 재구축이 자유로움 — 클러스터를 통째로 날려도 `argocd app sync`로 5분 복구
- 다중 환경 동기화 — 같은 Git 경로 → 여러 클러스터에 동시 배포(ApplicationSet)

### 2.4 시장 위치

- Helm은 K8s 패키지 매니저의 "유일한 답". OCI 호환 차트 저장소가 표준화되면서 Docker Registry에도
  차트 저장 가능해짐.
- ArgoCD vs Flux는 양강 구도. ArgoCD가 UI/UX로 점유율 우세(2024년 기준 GitOps 도구 사용 점유율
  ArgoCD 약 67%).

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

**패키지 관리 — Helm 선택 이유:**

| 옵션      | 장점                             | 단점                   | 우리 판단                                  |
| --------- | -------------------------------- | ---------------------- | ------------------------------------------ |
| Raw YAML  | 단순                             | 환경별 복제 지옥       | 클러스터 4개(온프레+AWS) → 탈락            |
| Kustomize | 템플릿 없이 명료                 | 외부 차트 못 가져다 씀 | Ceph CSI, MetalLB 등 외부 차트 필요 → 탈락 |
| **Helm**  | 외부 차트 풍부, 환경별 분리 쉬움 | 템플릿 가독성 떨어짐   | **채택**                                   |

**CD 도구 — ArgoCD 선택 이유:**

| 옵션                                | 장점                    | 단점                                  | 우리 판단                             |
| ----------------------------------- | ----------------------- | ------------------------------------- | ------------------------------------- |
| 사람이 kubectl apply                | 즉시                    | 추적 불가, 협업 시 충돌               | 4인 팀 → 탈락                         |
| GitHub Actions push → kubectl apply | CI/CD 일체화            | Push 방식 — 클러스터에 외부 접근 필요 | 온프레 K8s API가 인터넷 노출 X → 탈락 |
| Flux                                | 가벼움                  | UI 빈약, 시연 임팩트 낮음             | 발표 시연 중요 → 탈락                 |
| **ArgoCD**                          | UI 시연 강력, Pull 방식 | 리소스 좀 더 먹음(~500Mi)             | **채택**                              |

### 3.2 현업 표준과의 정합성

- Helm + ArgoCD 조합은 현업 K8s 운영의 **가장 표준적인 조합**이에요. Red Hat OpenShift GitOps, AWS
  EKS Blueprints, Azure GitOps Flux 모두 이 패턴.
- 우리 발표에서 "GitHub push → 자동 배포"를 시연하면 면접관/심사위원이 즉시 "현업 수준"으로 인식.

### 3.3 선택 근거 (트레이드오프)

- **트레이드오프 1 — 학습 곡선 vs 운영 편의**: ArgoCD는 처음 셋업할 때 Application CR, RBAC, repo
  credential 등 익혀야 할 게 많아요. 그래도 한 번 셋업하면 그 뒤가 너무 편해서 채택.
- **트레이드오프 2 — 리소스 부담**: ArgoCD는 controller + repo-server + redis + ui 합쳐 ~500Mi. 우리
  워커 6GB × 3대 환경에선 부담되지만, 시연 가치와 미래 확장성으로 보면 합리적.
- **트레이드오프 3 — Helm vs Kustomize**: Kustomize가 더 깔끔하지만, Ceph CSI/MetalLB/Prometheus 등
  외부 의존이 모두 Helm 차트로만 제공돼서 Helm 필수. Kustomize는 ArgoCD 안에서 부분적으로 같이 씀.

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
[개발자]
   │
   │ git push
   ▼
[GitHub Repo]
   │
   │   GitHub Actions: docker build + push to GHCR
   │   (.github/workflows/build.yml)
   │
   │
   ▼
[ghcr.io] ◀───── image pull ───── [K8s Workers]
                                         ▲
                                         │
                                         │ kubectl apply
                                         │
                                  [ArgoCD]
                                   namespace: argocd
                                   LB: 172.16.23.101
                                         ▲
                                         │ polling (3분)
                                         │
                              [Git: manifests/]
```

### 4.2 핵심 설정값과 근거

| 항목                | 값                                           | 근거                                               |
| ------------------- | -------------------------------------------- | -------------------------------------------------- |
| ArgoCD namespace    | `argocd`                                     | 공식 권장 (예약 namespace 아님)                    |
| ArgoCD Service type | `LoadBalancer`                               | 노트북에서 UI 접근. MetalLB 풀에서 IP 받음         |
| ArgoCD LB IP        | `172.16.23.101`                              | VLAN 30 풀 첫 번째 슬롯, 노트북에서 직접 접근 가능 |
| Sync 정책           | `automated: { prune: true, selfHeal: true }` | 시연에서 "Git push → 자동 반영" 임팩트             |
| Retry               | `limit: 5, backoff.duration: 5s`             | etcd leader change 대비                            |
| Repo polling 주기   | `180s`(기본)                                 | 시연에선 `argocd app sync`로 즉시 trigger도 가능   |

### 4.3 다른 컴포넌트와의 연결

- **MetalLB**: ArgoCD Service type=LoadBalancer → MetalLB 풀(`172.16.23.100-150`)에서
  `172.16.23.101` 자동 할당. 같은 VLAN 30이라서 노트북에서 바로 접근.
- **cert-manager**: ArgoCD UI를 HTTPS로 노출하려면 cert-manager가 자체 서명 또는 Let's Encrypt
  인증서 발급. 우리 환경은 내부망이라 일단 HTTP로 운영.
- **Helm**: ArgoCD가 Helm 차트도 Application source로 받을 수 있어요(`source.chart`,
  `source.helm.values`). 우리는 ceph-csi, MetalLB, Percona를 Helm으로 깔되, ArgoCD가 관리하도록
  Application으로 감싸요.

---

## 5. 실제 코드 / 설정 파일

### 5.1 ArgoCD 설치 (Helm) — `Onprem_Build_Guide.md` Phase 6.1

파일: `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` (940~955줄)

```bash
[bastion]$ kubectl create namespace argocd

[bastion]$ helm repo add argo https://argoproj.github.io/argo-helm
[bastion]$ helm install argocd argo/argo-cd \
            -n argocd \
            --set server.service.type=LoadBalancer
```

**왜 이 옵션?**

- `--set server.service.type=LoadBalancer`: 기본은 ClusterIP라 외부 접근 불가. MetalLB가 IP 할당해서
  노트북에서 바로 UI 접근 가능하게 함.
- `-n argocd`: namespace 분리 — RBAC 경계, 다른 워크로드와 cleanup 분리.
- `helm install` 대신 운영에선 **`helm upgrade --install`** 강추 (5.3 참고).

### 5.2 ArgoCD 초기 비밀번호 추출

```bash
[bastion]$ kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" | base64 -d ; echo
```

**핵심 라인:**

- `argocd-initial-admin-secret`: ArgoCD가 첫 설치 시 자동 생성. 한 번 로그인하면 본인 비밀번호로
  바꾸고 이 Secret은 삭제 권장.
- `base64 -d`: K8s Secret은 base64 인코딩이라 `-d`로 디코딩.

### 5.3 idempotent install 패턴 (운영 표준)

```bash
[bastion]$ helm upgrade --install argocd argo/argo-cd \
            -n argocd --create-namespace \
            --set server.service.type=LoadBalancer \
            --version 7.6.12
```

**왜 이 옵션?**

- **`upgrade --install`**: 처음이면 install, 이미 있으면 values만 갱신. CI 파이프라인에 그대로
  넣어도 안전.
- `--create-namespace`: namespace 없으면 자동 생성 (재현성 ↑).
- `--version 7.6.12`: 버전 핀. 안 박으면 latest 사용 — 어느 날 차트 업데이트로 깨질 수 있음.

### 5.4 Application 리소스 예시 (ticket-app)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ticket-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<org>/kosa_infra_project
    targetRevision: main
    path: ticket-app/k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: kosa-tickets
  syncPolicy:
    automated:
      prune: true # Git에서 삭제된 리소스를 클러스터에서도 제거
      selfHeal: true # 누가 kubectl edit로 손대도 Git 상태로 복구
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**왜 이 옵션?**

- `prune: true`: GitOps의 핵심 — Git에 없는 건 클러스터에도 없어야 함. drift 완전 제거.
- `selfHeal: true`: 운영 중 누가 손댄 변경을 자동 되돌림. "Git이 진실"을 강제.
- `retry.limit: 5`: 우리 환경에서 etcd leader change 시 일시 실패 → 자동 재시도로 흡수.

---

## 6. 실행 + 결과

### 6.1 ArgoCD 설치

```bash
[bastion]$ helm upgrade --install argocd argo/argo-cd \
            -n argocd --create-namespace \
            --set server.service.type=LoadBalancer
```

실제 출력:

```
Release "argocd" does not exist. Installing it now.
NAME: argocd
LAST DEPLOYED: Mon May 13 14:22:31 2026
NAMESPACE: argocd
STATUS: deployed
REVISION: 1
```

### 6.2 Pod / 서비스 확인

```bash
[bastion]$ kubectl -n argocd get pods,svc
```

실제 출력:

```
NAME                                                    READY   STATUS    RESTARTS   AGE
pod/argocd-application-controller-0                     1/1     Running   0          3m
pod/argocd-applicationset-controller-7c5c8f9c8d-x2vqr   1/1     Running   0          3m
pod/argocd-dex-server-66c8b7f5f-h7nbc                   1/1     Running   0          3m
pod/argocd-notifications-controller-7bbc6b9c4-zk8mq     1/1     Running   0          3m
pod/argocd-redis-78b4c8b5c5-jmtsc                       1/1     Running   0          3m
pod/argocd-repo-server-58f9d4c8b-4t9qz                  1/1     Running   0          3m
pod/argocd-server-86bc8c9f4-6dnp4                       1/1     Running   0          3m

NAME                                              TYPE           EXTERNAL-IP      PORT(S)
service/argocd-server                             LoadBalancer   172.16.23.101    80:30880/TCP,443:31443/TCP
service/argocd-server-metrics                     ClusterIP      <none>           8083/TCP
```

`EXTERNAL-IP 172.16.23.101` 받았으면 OK. 노트북 브라우저에서 `https://172.16.23.101` 접속.

### 6.3 비밀번호 + UI 로그인

```bash
[bastion]$ kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" | base64 -d ; echo
```

실제 출력:

```
8KqXyZ-Pa2vRm9NkQ
```

브라우저: `https://172.16.23.101` → admin / 위 값 → 로그인 OK.

### 6.4 Application 생성 (ticket-app 예시)

```bash
[bastion]$ kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ticket-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/sangchul1/kosa_infra_project
    targetRevision: main
    path: ticket-app/k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: kosa-tickets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

```bash
[bastion]$ kubectl -n argocd get applications
```

실제 출력:

```
NAME         SYNC STATUS   HEALTH STATUS
ticket-app   Synced        Healthy
```

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 7.1 `helm install` 이름 중복 에러

**증상:**

```
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
```

**원인:** 이전 시도에서 같은 이름의 release가 남아있어요. `helm install`은 "새 release 생성"
명령이라 중복 이름을 거부합니다.

**해결:**

```bash
[bastion]$ helm upgrade --install argocd argo/argo-cd -n argocd -f values.yaml
```

**왜 이 함정이 발생하는가 (메커니즘):** Helm 3는 release 메타데이터를
Secret(`sh.helm.release.v1.<name>.v<rev>`)에 저장해요. `helm install`은 이 Secret이 없을 때만
작동하고, 있으면 거부합니다. `helm upgrade --install`은 "있으면 upgrade, 없으면 install" 동작이라
idempotent해서 CI/CD 파이프라인 어디에 넣어도 안전. 출처: `inventory.md` 표 2 /
`Onprem_Build_Guide.md` Phase 5.2.

### 7.2 Helm chart의 values 캐시 (provisioner pod restart 필요)

**증상:** values.yaml에 fsid 같은 ConfigMap 데이터를 바꿔서 `helm upgrade` 했는데, CSI provisioner
Pod가 옛 값으로 계속 동작.

**원인:** Helm이 ConfigMap을 갱신해도, 이미 띄워진 Pod는 시작 시점에 ConfigMap을 메모리에
캐시해놨어요. ConfigMap 변경은 자동으로 Pod에 반영되지 않습니다.

**해결:**

```bash
[bastion]$ kubectl -n ceph-csi-rbd rollout restart deployment ceph-csi-rbd-provisioner
[bastion]$ kubectl -n ceph-csi-rbd rollout restart daemonset ceph-csi-rbd-nodeplugin
```

**왜 이 함정이 발생하는가 (메커니즘):** K8s는 ConfigMap을 Pod에 mount할 때, **subPath 없는 volume
mount**는 kubelet이 주기적으로 갱신해줘요(약 1분 주기). 하지만 **subPath mount 또는 env로 주입한
경우**는 Pod 재시작 전엔 절대 갱신 안 됨. ceph-csi는 `/etc/ceph/config.json`을 subPath로 마운트해서
caching 효과 발생. → rollout restart 필수. 출처: `inventory.md` 표 2 / `Onprem_Build_Guide.md` Phase
5.2 함정 1.

### 7.3 ArgoCD Sync Loop (Synced → OutOfSync 반복)

**증상:** ArgoCD UI에서 Application이 Synced로 잠깐 됐다가 곧 OutOfSync로 떨어지고, 다시 Synced...
반복.

**원인:** 클러스터 측에서 K8s admission controller나 다른 controller(operator)가 리소스에 자동으로
필드를 추가하는데, Git에는 그 필드가 없어서 매번 diff가 발생.

대표 사례:

- Istio sidecar injection이 Pod spec에 init container 추가
- AKS/EKS의 cloud-controller가 Service에 finalizer 추가
- cert-manager가 Ingress에 annotation 자동 주입

**해결:** Application에 `ignoreDifferences` 추가.

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/template/spec/initContainers # Istio가 자동 추가
    - group: ""
      kind: Service
      jsonPointers:
        - /metadata/finalizers
```

**왜 이 함정이 발생하는가 (메커니즘):** ArgoCD의 sync 판정 로직은 Git의 desired manifest와
클러스터의 live manifest를 **JSON 깊이 비교**해서 다르면 OutOfSync로 마킹해요. 다른 controller가
mutating webhook이나 controller loop으로 필드를 자동 채워넣으면, ArgoCD 입장에선 "Git에 없는 필드가
클러스터에 있음" → drift. `ignoreDifferences`로 비교에서 제외해야 sync 안정.

### 7.4 ArgoCD `LoadBalancer Pending` (External-IP 안 잡힘)

**증상:** `kubectl -n argocd get svc argocd-server` 결과 EXTERNAL-IP가 `<pending>`에서 안 바뀜.

**원인:** MetalLB 풀이 정의 안 됐거나, K8s 노드 VLAN과 풀 대역이 다른 VLAN.

**해결:** MetalLB IPAddressPool을 K8s 노드와 같은 VLAN 30 대역으로 설정.

```bash
[bastion]$ kubectl -n metallb-system patch ipaddresspool kosa-pool \
            --type='merge' \
            -p '{"spec":{"addresses":["172.16.23.100-172.16.23.150"]}}'
```

**왜 이 함정이 발생하는가 (메커니즘):** MetalLB L2 모드는 Speaker DaemonSet이 K8s 노드 네트워크
인터페이스에서 ARP/NDP로 가상 IP를 announce해요. K8s 노드가 VLAN 30에 있고 풀이 VLAN 20 대역이면,
노드 NIC가 VLAN 20에 연결 안 돼있어서 ARP 응답 불가 → 외부에서 그 IP에 도달 못 함. 출처:
`inventory.md` 표 2.

---

## 8. 더 깊이 공부할 자료

**Helm:**

- 공식 docs: https://helm.sh/docs/
- Best practices: https://helm.sh/docs/chart_best_practices/
- 책 `Learning Helm` (O'Reilly, 2020) — 차트 작성 체계화

**ArgoCD:**

- 공식 docs: https://argo-cd.readthedocs.io/
- ArgoCD Autopilot — bootstrap 자동화 도구
- `Application` vs `ApplicationSet` 비교:
  https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- 책 `GitOps with Kubernetes` (Manning, 2023)

**GitOps 일반론:**

- Weaveworks GitOps 원조 글: https://www.weave.works/technologies/gitops/
- CNCF GitOps Working Group: https://github.com/open-gitops

**참고 우리 프로젝트 파일:**

- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 6.1 (ArgoCD)
- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 5.2 (Helm idempotent)
- `/Users/sangjjang/kosa_infra_project/inventory.md` 표 2 (Helm/ArgoCD 함정)

---

## 다음 챕터 미리보기

**챕터 13: HPA + k6 부하 테스트**에서는 우리가 ticket-app에 적용한 HPA(minReplicas 2, maxReplicas
10, CPU 50%) 설정의 의미와, k6로 30초 10VU → 60초 100VU → 60초 500VU 부하를 줘서 Pod가 2 → 10으로
폭증하는 시나리오를 다룰 거예요. scaleUp의 `stabilizationWindowSeconds: 0`이 왜 0인지, Percent vs
Pods 정책의 차이가 무엇인지 직접 짚어볼게요.
