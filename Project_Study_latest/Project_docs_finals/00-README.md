# KOSA Team2 온프레미스 인프라 문서

> **이 문서 시리즈의 목적**
> 우리가 구축한 온프레미스 인프라를 **"왜 이렇게 만들었는가"** 중심으로 풀어쓴 학습용 문서.
> 명령어/IP/credential 같은 lookup 정보는 루트의 `../../CLAUDE.md`에 있고,
> 이 폴더는 **개념·설계 사고·트레이드오프**를 다룬다.

---

## 누구를 위한 문서인가

| 독자 | 이렇게 읽어 |
|---|---|
| **신규 합류자/팀원** | 01부터 순서대로. 모르는 용어는 `../../CLAUDE.md`의 "핵심 용어 사전" 검색. |
| **발표/평가 준비** | 01(전체 그림) → 흥미 영역만 발췌. 각 챕터의 "왜" 박스가 핵심 talking point. |
| **운영 중 문제 해결** | 해당 컴포넌트 챕터로 직행 → "트러블슈팅" 섹션. 그래도 안 풀리면 본문 거슬러 올라가서 컨텍스트 확인. |
| **포트폴리오 면접 준비** | 01 + 본인이 자신 있게 말할 수 있는 챕터 2~3개를 깊게. "왜" 박스의 트레이드오프를 본인 말로 다시 설명 연습. |

---

## 목차 (각 챕터 1줄 요약)

| # | 챕터 | 핵심 질문 |
|---|---|---|
| 01 | [프로젝트 개요 & 아키텍처](01-overview.md) | 왜 이런 시스템을 만들었나? 무엇을 결정했나? |
| 02 | [물리 인프라 & 네트워크](02-physical-network.md) | 어떤 장비로, 어떻게 VLAN을 나눴고, pfSense는 왜 HA로? |
| 03 | [Proxmox 가상화](03-proxmox.md) | 왜 KVM? cloud-init은 어떻게 동작? VM 배치 전략은? |
| 04 | [Ceph 분산 스토리지](04-ceph.md) | Ceph 내부 구조와 RBD/RGW 사용처, BlueStore가 무엇? |
| 05 | [Kubernetes 클러스터](05-kubernetes.md) | HA 컨트롤플레인 설계, Calico/MetalLB/HAProxy Ingress 선택 이유 |
| 06 | [보안 & TLS](06-security-tls.md) | 자체 CA를 쓴 이유, 이중 TLS 구조의 트레이드오프 |
| 07 | [GitOps & ArgoCD](07-gitops-argocd.md) | GitOps가 무엇이고, App-of-Apps 패턴을 왜? |
| 08 | [Harbor 레지스트리](08-harbor-registry.md) | 사설 레지스트리가 필요한 이유, Ceph RGW S3 백엔드 선택 근거 |
| 09 | [Jenkins CI](09-jenkins-ci.md) | "왜 GitHub Actions 대신 Jenkins?" 솔직한 답 + K8s 동적 agent |
| 10 | [CI/CD 파이프라인](10-cicd-pipeline.md) | 소스 repo와 GitOps repo 분리, Kaniko가 무엇? |
| 11 | [관측성](11-observability.md) | Prometheus 풀 모델, kubeadm 메트릭 포트 트릭 |
| 12 | [운영 & 백업](12-operations.md) | 일상 운영 체크리스트, 노드 교체, 인증서 캘린더 |

> 💡 각 챕터의 트러블슈팅은 해당 챕터 마지막 섹션에, 통합 인덱스는 12장에 정리되어 있다.

---

## 추천 학습 경로

### 🌱 입문자 (이 분야 처음 또는 인프라 경험이 적음)
01 → 02 → 03 → 04 → 05의 5개 챕터를 **본문 + "왜" 박스만** 먼저 훑기.
중간의 yaml/코드는 처음엔 건너뛰고 그림과 narrative만 따라가도 큰 그림은 잡힘.
한 챕터 끝낼 때마다 `../../CLAUDE.md`의 해당 섹션 한 번 더 보면 detail이 채워짐.

### 🔧 중급자 (K8s/Linux는 알지만 본격 인프라 구축은 처음)
01 → 05(K8s) → 07(GitOps) 우선. 그 후 06(TLS), 04(Ceph), 02(네트워크).
**"왜" 박스의 트레이드오프 부분 + 대안 비교 표**를 본인 환경과 비교하면서 읽기.

### 🚒 운영자 (장애 대응 중)
1. `../../CLAUDE.md`의 "운영 노하우" + "FAQ" 먼저
2. 해결 안 되면 해당 컴포넌트 챕터의 "트러블슈팅" 섹션
3. 그래도 안 풀리면 챕터 본문에서 컨텍스트 파악

### 🎤 발표/포트폴리오 준비자
01의 "아키텍처 결정" 섹션 + 본인 담당 영역 챕터 1~2개 + 12장 "운영" 섹션.
각 "왜" 박스는 면접관/평가자가 가장 자주 묻는 질문이라고 생각하고 본인 말로 재서술 연습.

---

## 사전 지식 체크리스트

다음 중 모르는 게 있으면 해당 챕터 진입 전 1시간 정도 외부 자료로 채우길 권장:

| 영역 | 알아야 하는 최소 수준 | 모르면 보면 좋은 자료 |
|---|---|---|
| **Linux** | systemd, journalctl, netplan, /etc/hosts, SSH 키 인증 | "The Linux Command Line" (William Shotts, 무료) |
| **TCP/IP** | OSI 7 layer 대략, CIDR 표기, TCP 3-way handshake, NAT 개념 | Cloudflare Learning Center |
| **Docker** | 이미지 vs 컨테이너, Dockerfile, registry 개념 | Docker 공식 Get Started |
| **Kubernetes** | Pod / Deployment / Service / Ingress / Namespace 개념 | Kubernetes 공식 Concepts |
| **Git** | clone/commit/push/pull, branch, merge vs rebase | "Pro Git" 책 1~3장 |
| **YAML** | indent 규칙, list vs map | YAML 공식 1.2 spec 또는 yamllint |

K8s가 가장 큰 진입장벽이라 그쪽이 약하면 05장 진입 전에 minikube로 며칠 실습해보길 추천.

---

## 도큐먼트 규약

### 코드 블록 prefix
실행 위치를 명시:

```bash
# bastion에서 실행
kubectl get nodes
```

```bash
# k8s-w1 (워커 노드)에서 실행
sudo systemctl restart containerd
```

```bash
# pfSense Shell (옵션 8)
pfctl -s nat
```

prefix가 없으면 "어디서 실행하든 무관" 또는 "맥락상 자명".

### Callout 박스
**📌 핵심**: 해당 챕터의 핵심 메시지. 시간 없으면 이것만이라도 읽어.

**💡 왜?**: 설계 의도/배경. "이렇게 한 이유는 뭐야?"의 답.

**⚠️ 함정**: 우리가 실제로 빠졌거나 빠질 뻔한 함정. 미리 알면 피할 수 있음.

**🔧 실습**: 직접 따라해보면 좋은 부분.

**📚 더 깊이**: 외부 자료 링크. 이 문서 범위를 넘는 깊이.

### 다이어그램
- **PNG 아키텍처 다이어그램**: `assets/` 폴더. Python `diagrams` 라이브러리(Graphviz)로 생성.
  - 라벨은 영어 (CJK 폰트 의존성 회피). 한글 해설은 본문 캡션에서.
  - 재생성: `cd assets && python3 generate_diagrams.py`
- **ASCII 박스 다이어그램**: 토폴로지/배치도. 인쇄에도 깨지지 않음.
- **Mermaid 다이어그램**: 시퀀스/플로우/상태. GitHub/VSCode에서 자동 렌더링.

### YAML/코드 주석 컨벤션
중요한 라인은 한국어로 `# ← 왜:` 형태로 주석:

```yaml
spec:
  nodeSelector:
    workload-type: system    # ← 왜: PVC RWO 충돌 회피 + 운영 노드 격리
```

---

## CLAUDE.md와의 관계

| 보고 싶은 것 | 어디로? |
|---|---|
| "이 명령어 뭐였더라" | `../../CLAUDE.md` (lookup용) |
| "왜 이렇게 설계했지?" | 이 폴더의 챕터 본문 |
| "장애 났는데 뭐부터?" | `../../CLAUDE.md`의 "운영 노하우" + "FAQ" 먼저 → 안 되면 챕터 트러블슈팅 |
| "용어 모르겠다" | `../../CLAUDE.md`의 "핵심 용어 사전" |
| "전체 학습 순서" | 이 README의 "추천 학습 경로" |

**규칙**: 새 정보를 추가할 때 — 운영용 lookup이면 CLAUDE.md, narrative/이유 설명이면 docs/onprem/.

---

## 이 문서를 어떻게 발전시키나

- 챕터 본문에 오류·오타·이해 안 되는 부분 발견 → GitHub Issue 또는 직접 PR
- 새로 추가하면 좋을 챕터 (예: AWS 하이브리드 챕터) → 13번 이후로 추가
- "왜" 박스에 본인 경험/추가 근거 보강 환영
- 트러블슈팅 사례 → 해당 챕터 마지막 섹션에 한 줄이라도 추가하면 다음 사람이 시간 아낌

---

## 다음 단계

[01. 프로젝트 개요 & 아키텍처](01-overview.md)부터 시작하기.
