# Part 3. CI/CD — 발표자 C

- 슬라이드: 17~22 (총 6장)
- 발표 시간: 약 5분 (슬라이드당 약 50초)
- 톤: 다크 메인 + 라이트 포인트 1장 (20번 End-to-End 검증)
- 역할: Actions vs Jenkins 비교 + GitOps 파이프라인 + 2 job 운영

## 파트 전체 흐름

```
Actions vs Jenkins → 파이프라인 흐름 → Jenkins+Kaniko+ArgoCD
  → End-to-end 검증 (라이트) → 2 Job 운영 → Burst 연결
```

## 핵심 메시지 1줄

"코드 push → 4분 후 운영 배포, 같은 GitOps로 온프레와 EKS 동시 배포 가능"

## 발표 진입 멘트

"CI/CD 담당 ○○입니다. 우리 파이프라인은 GitHub → Jenkins → Kaniko → Harbor → GitOps → ArgoCD → K8s 7단계로, 코드 push 후 4분 안에 운영 환경에 배포됩니다."

---

## 17. GitHub Actions vs Jenkins — WHY JENKINS [다크] ⭐신규

### 한 메시지
자체 인프라 + private workload → Jenkins on K8s가 자연 선택

### 들어갈 내용

**비교 표 (간단히)**:
| 항목 | GitHub Actions | **Jenkins** ⭐ |
|---|---|---|
| 호스팅 | SaaS (외부) | 자체 (K8s 위) |
| Runner | GitHub runner / self-hosted | K8s 동적 agent |
| 비용 | 무료 한도 후 유료 | 자체 자원 |
| 네트워크 | 외부 → private 접근 추가 작업 | private 자연 |
| 설정 관리 | YAML 워크플로 | JCasC (git 관리) |

### 선택 근거 3가지
1. **자체 K8s 인프라 운영 중** → 빌드 환경도 자체 호스팅이 일관성
2. **Private 네트워크 접근** → Harbor, GitOps repo, K8s API 자연
3. **K8s + Kaniko = 빌드마다 Pod 생성/삭제** → 자원 효율, 보안

### Trade-off (솔직하게)
- GitHub Actions가 학습 곡선 낮고 modern
- Jenkins는 플러그인 관리 부담 (LTS 고정 등 운영 노하우 필요)
- "GitHub Actions self-hosted runner + Kaniko"도 가능한 대안이었음

### 발표 멘트
"왜 Jenkins를 골랐는지부터 짚고 가겠습니다. GitHub Actions는 SaaS 호스팅이고 modern하지만, 우리 환경은 자체 K8s 인프라가 이미 있고 private 네트워크 안에서 Harbor와 GitOps repo에 접근해야 합니다. 이런 조건에서는 Jenkins를 K8s 위에 올리고 Kaniko로 빌드마다 Pod를 만들었다 지우는 방식이 자원 효율도 좋고 일관성도 있습니다. Actions self-hosted runner도 가능한 옵션이었지만 운영 부담 차이가 크지 않다고 판단했습니다."

---

## 18. 파이프라인 전체 흐름 [다크]

### 한 메시지
GitHub → Jenkins → Kaniko → Harbor → GitOps → ArgoCD → K8s · 4분 컷

### 들어갈 내용
- 7단계 가로 플로우 (큰 박스 + 화살표)
- 각 박스: 단계 번호 (01~07) + 이름 + 1줄 액션
- 색: NAVY 박스 + BLUE 액센트

**7단계**:
1. **GitHub** — git push
2. **Jenkins** — Pipeline 트리거 (SCM polling H/2 * * * *)
3. **Kaniko** — rootless 컨테이너 이미지 빌드
4. **Harbor** — 이미지 push (build_number 태그)
5. **GitOps repo** — deployment.yaml image 태그 sed 갱신
6. **ArgoCD** — auto-sync (3분 polling)
7. **K8s** — Deployment rollout

### 각 단계 "왜 이 도구"
- Kaniko: rootless · K8s 안에서 안전
- Harbor: 자체 호스팅 + RGW S3 백엔드 수평 확장
- ArgoCD: 선언적 GitOps · drift 자동 복구

### 발표 멘트
"전체 흐름은 7단계입니다. 코드를 GitHub에 푸시하면 Jenkins가 폴링으로 감지해서 Pipeline을 시작합니다. Kaniko Pod이 떠서 컨테이너 이미지를 빌드하는데, rootless 방식이라 K8s 안에서 안전합니다. 빌드된 이미지는 Harbor에 build number를 태그로 push됩니다. 그 다음 Jenkins가 GitOps repo의 deployment.yaml에서 image 태그를 sed로 갱신하고 git push합니다. ArgoCD가 polling으로 변경을 감지하면 자동 sync, K8s Deployment가 rolling update로 새 Pod를 띄웁니다."

---

## 19. Jenkins + Kaniko + ArgoCD [다크]

### 한 메시지
K8s 안에서 rootless 빌드 + ArgoCD가 git 변경을 자동 sync

### 들어갈 내용 (좌·우 2분할)

**좌 — Jenkins + Kaniko**:
```
Jenkins Master (k8s-sys1)
   ↓ Kubernetes plugin
빌드 시작 → Build Agent Pod 동적 생성
   ├── kaniko container (gcr.io/kaniko-project/executor)
   │     └── --skip-tls-verify (자체 CA)
   │     └── Harbor push
   └── git container (alpine/git)
         └── GitOps repo sed + push
   ↓
빌드 끝 → Pod 삭제 (자원 효율)
```

**우 — ArgoCD App-of-Apps**:
```
root-app
  ↓ watch apps/_applications/
   ├── cert-manager
   ├── monitoring (kube-prometheus-stack)
   ├── redis (bitnami)
   ├── harbor
   ├── jenkins
   ├── ticket-app
   ├── admin-app ⭐신규
   └── ... (8개)

설정: auto-sync + selfHeal
drift 자동 복구 · ignoreDifferences로 false-positive 제거
```

### 핵심 ignoreDifferences (3종)
- `StatefulSet volumeClaimTemplates` — immutable
- `Secret data` — bitnami 차트가 random password 생성
- `MutatingWebhookConfiguration webhooks` — cert-manager가 caBundle 갱신

### 발표 멘트
"Jenkins는 K8s 위에 올라가 있고, Kubernetes 플러그인으로 빌드마다 동적 Pod를 만듭니다. 그 Pod 안에 Kaniko 컨테이너와 git 컨테이너가 같이 떠서 빌드와 GitOps 업데이트를 한 곳에서 처리합니다. ArgoCD는 App-of-Apps 패턴 — root-app 하나가 다른 8개 Application을 자동 생성합니다. ticket-app, admin-app, monitoring, harbor 등 모두 여기 등록돼 있습니다. selfHeal이 켜져 있어서 누군가 kubectl로 직접 수정해도 git 상태로 되돌립니다. 무한 OutOfSync 방지를 위해 ignoreDifferences 3종을 설정했습니다 — StatefulSet의 volumeClaimTemplates, Secret data, cert-manager가 갱신하는 webhook caBundle."

---

## 20. End-to-End 검증 — Build #4 [라이트 ⭐]

### 한 메시지
코드 1줄 변경 → 4분 후 운영 환경 Pod rollout 완료

### 들어갈 내용 (라이트 톤)

**타임라인 (가로축 0:00 ~ 4:00)**:
| 시간 | 단계 |
|---|---|
| 0:00 | GitHub push |
| 0:30 | Jenkins Build #4 시작 |
| 2:30 | Kaniko 빌드 완료 |
| 3:00 | Harbor push 완료 (`library/kosa-tickets:4`) |
| 3:10 | GitOps `deployment.yaml` sed 갱신 + git push |
| 3:30 | ArgoCD OutOfSync → Synced |
| 4:00 | K8s Deployment rollout 완료 |

**캡처 4개**:
1. Jenkins Build #4 SUCCESS
2. Harbor library/kosa-tickets:4 이미지 등록
3. GitOps repo commit 메시지 "CI: kosa-tickets 4"
4. ArgoCD ticket-app Synced + Healthy

### 발표 멘트
"실제 검증 결과입니다. 코드를 GitHub에 푸시하면 30초 후 Jenkins 빌드가 시작, 2분에 Kaniko 빌드 완료, 3분에 Harbor push, 3분 10초에 GitOps commit, 3분 30초에 ArgoCD sync, 4분에 K8s Pod rollout이 완료됩니다. 캡처에서 보시는 것처럼 각 단계가 모두 성공적으로 진행됐고, ticket-app은 Synced + Healthy 상태입니다."

---

## 21. ticket-app + admin-app 2 Job 운영 [다크] ⭐최신

### 한 메시지
동일 Pipeline 패턴으로 두 앱 동시 운영 — OLTP/OLAP 분리에 매핑

### 들어갈 내용

**비교 표**:
| 항목 | kosa-tickets-ci | kosa-tickets-admin-ci |
|---|---|---|
| 소스 repo | kosacloudteam2/kosa-tickets | kosacloudteam2/kosa-tickets-admin |
| 이미지 | library/kosa-tickets:N | library/admin-app:N |
| GitOps path | apps/ticket-app/deployment.yaml | apps/admin-app/20-deployment.yaml |
| 워크로드 종류 | OLTP (사용자 트래픽) | OLAP (관리자·분석) |
| DB 연결 | PXC via ProxySQL | RDS Read Replica (admin_ro) |
| K8s namespace | kosa-tickets | admin |

### 핵심 메시지
- **같은 Jenkins job 템플릿** → 새 앱 추가 시 config.xml 복사 + sed로 image/repo/path 치환
- **다른 DB 백엔드** → 데이터 layer 분리 패턴과 1:1 매핑
- **다른 namespace** → 권한·NetworkPolicy 격리 가능

### 발표 멘트
"파이프라인 자체는 두 개 잡으로 운영합니다 — ticket-app과 admin-app입니다. 둘 다 같은 Jenkins Pipeline 템플릿을 쓰고, config.xml을 복사해서 image 이름과 GitOps path만 sed로 치환해 만들었습니다. 차이점은 워크로드 종류 — ticket-app은 사용자 트래픽 받는 OLTP이고 PXC에 연결, admin-app은 관리자 대시보드 OLAP이고 RDS Read Replica에 연결합니다. namespace도 분리해서 권한과 NetworkPolicy로 격리 가능합니다. 데이터 분리 패턴과 정확히 1:1 매핑되는 구조입니다."

---

## 22. Burst 시나리오 연결 (Phase 4) [다크]

### 한 메시지
multi-cluster ArgoCD → 온프레와 EKS에 동일 GitOps repo로 동시 배포

### 들어갈 내용
- 메인 다이어그램 (현재 vs 미래):

**현재 (Phase 3)**:
```
GitHub → Jenkins → Kaniko → Harbor → GitOps
                                      ↓
                              ArgoCD (단일 cluster)
                                      ↓
                              온프레 K8s
```

**미래 (Phase 4)**:
```
GitHub → Jenkins → Kaniko → Harbor → GitOps
                                      ↓
                              ArgoCD (multi-cluster)
                                  ↓        ↓
                            온프레 K8s    EKS (burst)
                                              ↑
                                       Karpenter 자동 노드 생성
                                       T-30분 트리거
```

### 핵심 메시지
- 현재: 단일 ArgoCD가 온프레에만 배포
- Phase 4: ArgoCD에 EKS 클러스터 등록 → 같은 manifest로 양쪽 동시 배포
- Karpenter가 T-30분에 EC2 띄움 → EKS join → ArgoCD가 Pod 자동 배치
- Harbor 이미지는 VPN 통해 EKS도 pull 가능 (또는 ECR 미러)

### 미구현 솔직 공개
"현재 ArgoCD는 단일 클러스터만 관리합니다. Phase 4가 multi-cluster ArgoCD + Karpenter + CloudWatch 트리거인데 아직 미구현입니다."

### 발표 멘트
"마지막으로 burst 시나리오와의 연결입니다. 현재 ArgoCD는 온프레 K8s만 관리하는데, Phase 4에서는 EKS 클러스터도 같은 ArgoCD에 등록할 계획입니다. 그렇게 되면 GitOps repo에 코드를 push하면 온프레와 EKS 양쪽에 동시 배포됩니다. T-30분에 Karpenter가 EC2를 띄우면 EKS에 join되고, ArgoCD가 자동으로 Pod를 배치합니다. Harbor 이미지는 VPN으로 EKS 노드도 pull 가능합니다. 이 부분은 아직 미구현이고 다음 단계 과제입니다."

### 다음 발표자에게 패스
"여기까지 CI/CD였습니다. 마지막으로 이 모든 걸 안전하게 막는 보안 계층을 ○○님이 다루겠습니다."
