# 챕터 06 — MetalLB + cert-manager

> KOSA 인프라 프로젝트 학습 시리즈
> 분량: 8~10 페이지
> 선수 챕터: 05 Calico CNI

---

## 학습 후 알 수 있는 것

- **베어메탈 K8s에는 왜 LoadBalancer가 그냥 안 되는지**, 그리고 MetalLB가 그 빈자리를 어떻게 채우는지 설명할 수 있어요.
- MetalLB의 **L2 모드 vs BGP 모드** 차이와, 우리가 왜 L2를 골랐는지 근거를 댈 수 있어요.
- **cert-manager**가 K8s에서 TLS 인증서를 어떻게 자동 발급/갱신하는지, Let's Encrypt와 self-signed CA를 언제 골라 쓰는지 알아요.
- "MetalLB 풀이 VLAN 20인데 클러스터는 VLAN 30이라 External-IP가 도달 불가능했던" 우리 실제 함정의 메커니즘과 해결을 재현할 수 있어요.
- 우리 환경의 IP 풀 `172.16.23.100-150`과 cert-manager 1.14.0의 핵심 설정값을 외울 정도가 됩니다.

---

## 1. 기술 개요 — MetalLB

### 1.1 정의 (한 문장)

**MetalLB는 베어메탈/온프레미스 K8s 환경에서 LoadBalancer 타입 Service에 진짜 IP를 자동 할당해주는 오픈소스 네트워크 컴포넌트입니다.**

### 1.2 등장 배경

K8s에서 외부 노출 방법은 세 가지예요.

| 방법 | 동작 | 외부 IP |
|---|---|---|
| NodePort | 모든 노드의 특정 포트 열기 | 노드 IP + 30000~32767 |
| LoadBalancer | 외부 LB가 IP 자동 부여 | **클라우드 제공자에 의존** |
| Ingress | L7 라우팅 (HTTP/HTTPS) | LB/NodePort 위에 얹힘 |

LoadBalancer가 가장 깔끔하지만, **클라우드가 아니면 안 됨**. AWS는 ELB, GCP는 GLB가 자동으로 만들어지지만 우리처럼 베어메탈에선 K8s가 외부 LB를 만들 수단이 없어요. 그래서 베어메탈에선 LoadBalancer 타입 Service가 영원히 **Pending** 상태로 멈춰버려요.

이 문제를 푸는 게 MetalLB. **K8s 클러스터 안에 LoadBalancer 컨트롤러를 직접 구현**해서, IP 풀에서 빈 IP를 골라 Service에 할당해줍니다.

### 1.3 핵심 개념 + 용어 풀이

| 용어 | 한 줄 풀이 |
|---|---|
| **IPAddressPool** | MetalLB가 사용할 IP 대역. 우리는 `172.16.23.100-150`. |
| **L2Advertisement** | 풀에서 할당된 IP를 **ARP 응답**으로 광고하는 모드 설정. |
| **BGPAdvertisement** | ARP 대신 **BGP 경로 광고**로 알리는 모드 설정. |
| **Speaker** | 각 노드의 DaemonSet. ARP/BGP를 실제로 발화. |
| **Controller** | Deployment 1개. Service에 IP 부여하는 두뇌. |
| **Leader Election** | L2 모드에서 어느 노드가 ARP 응답할지 결정 (한 IP당 1개 노드). |

### 1.4 동작 원리 (내부 메커니즘) — L2 모드

```
[사용자] curl http://172.16.23.103  (티켓 앱 External-IP)
       │
       ▼
[VLAN 30 스위치] "172.16.23.103 가진 놈 손!" (ARP request)
       │
       │ Broadcast to all hosts in 172.16.23.0/24
       ▼
[k8s-w2의 MetalLB Speaker]
   "Leader인 나야!" → ARP Reply: MAC=w2의 MAC
       │
       ▼
[스위치] 사용자에게 응답 — w2의 MAC으로 보내라
       │
       ▼
[사용자] → w2의 NIC로 패킷 보냄
       │
       ▼
[w2의 kube-proxy/IPVS]
   목적지 IP 172.16.23.103 → Service ClusterIP
   → 백엔드 Pod 중 하나에 분산
```

핵심은 **하나의 IP를 노드 한 대만 광고**한다는 거예요. 그 노드가 죽으면 다른 노드가 leader가 되어 다시 광고 시작. **이게 페일오버 메커니즘**입니다 (보통 10초 이내 복구).

### 1.5 주요 기능

- LoadBalancer 타입 Service에 IP 자동 할당
- L2(ARP/NDP) 또는 BGP 광고
- IP 풀 여러 개 운영 (네임스페이스별/앱별 분리 가능)
- 특정 IP 고정 할당 (`spec.loadBalancerIP`)
- IPv4 / IPv6 dual-stack

### 1.6 다른 도구와 비교

| 도구 | 모드 | 베어메탈 호환 | 운영 부담 | 우리 평가 |
|---|---|---|---|---|
| **MetalLB** | L2/BGP | ✅ | 낮음 | ✅ 채택 |
| kube-vip | L2/BGP | ✅ | 중 (CP VIP도 같이) | 다음 라운드 |
| PureLB | L2/BGP | ✅ | 중 | 점유율↓ |
| OpenELB | L2/BGP | ✅ | 중 | 점유율↓ |
| HAProxy + keepalived 수동 | 수동 | ✅ | **높음** | 학습 부담↑ |

---

## 2. 현업/실무 맥락 — MetalLB

### 2.1 어떤 상황에서 필요한가

- **온프레미스 K8s** — 100% 필수에 가까움
- **개발/스테이징 K8s** — 클라우드 LB 비용 절약을 위해 도입하는 경우 있음
- **에어갭(폐쇄망) 환경** — 외부 LB 자체가 없는 환경

### 2.2 업계 표준 구성, 대표 사용 기업/사례

- **Equinix Metal, OVH, Hetzner** 같은 베어메탈 클라우드: MetalLB가 사실상 표준 권장
- 국내 통신사/금융권 사내 K8s: MetalLB + Calico + Ceph CSI 조합이 가장 흔함
- **OpenShift Bare Metal**: 자체 MetalLB Operator 번들로 제공

### 2.3 왜 효율이 좋은가 (현업 관점)

- **운영 부담 거의 0** — Helm으로 5분 설치 후 IP 풀만 정의
- **클라우드 LB 대비 비용 0** — ALB/NLB 시간당 비용을 없앰
- **K8s native** — Service만 만들면 끝, 외부 도구 호출 불필요

### 2.4 시장 위치

- CNCF Sandbox → Incubating 단계. 베어메탈 K8s 영역에서 사실상 단일 표준.
- GitHub Star 7k+ (2026 기준), 활발한 메인테이너.

---

## 3. 기술 개요 — cert-manager

### 3.1 정의 (한 문장)

**cert-manager는 K8s 안에서 TLS 인증서를 자동으로 발급·갱신·배포해주는 컨트롤러로, Let's Encrypt·HashiCorp Vault·자체 CA 등 다양한 Issuer를 지원합니다.**

### 3.2 등장 배경

HTTPS는 사실상 의무가 됐어요(브라우저 경고, 검색 엔진 가산점, 컴플라이언스). 그런데 인증서는 다음을 자동으로 해줘야 운영이 됨:

1. **발급**: 도메인 검증(DNS-01/HTTP-01)
2. **갱신**: Let's Encrypt는 90일 만료 → 60일마다 갱신
3. **K8s에 주입**: 발급된 인증서를 Secret으로 만들고, Ingress/Pod에 마운트

사람이 90일마다 손으로 갱신하다 깜빡하면 사이트가 죽어요. **cert-manager가 이 모든 걸 reconciliation loop로 자동화**.

### 3.3 핵심 개념 + 용어 풀이

| 용어 | 한 줄 풀이 |
|---|---|
| **Issuer** | namespace 단위 인증서 발급자 (특정 ns만 발급 가능). |
| **ClusterIssuer** | 클러스터 전역 발급자. 모든 ns가 공유. |
| **Certificate** | 원하는 인증서를 선언하는 CR. cert-manager가 보고 발급. |
| **CertificateRequest** | Certificate가 만든 발급 요청. CA에 실제로 보냄. |
| **Order / Challenge** | Let's Encrypt(ACME) 발급 절차 |
| **Secret (kubernetes.io/tls)** | 발급된 인증서가 최종 저장되는 곳 (Ingress가 참조) |

### 3.4 동작 원리 (내부 메커니즘)

```
[개발자] Certificate CR 적용
   spec: { dnsNames: [api.kosa.local], issuerRef: ClusterIssuer/letsencrypt }
       │
       ▼
[cert-manager controller]
   - 같은 spec의 Secret 있는지 확인
   - 없거나 만료 임박(< 30일)이면 CertificateRequest 생성
       │
       ▼
[Issuer가 ACME면]
   - Let's Encrypt에 새 인증서 요청
   - HTTP-01 challenge: /.well-known/acme-challenge/<token> URL 노출 요구
   - cert-manager가 임시 Ingress + Pod 자동 생성
   - Let's Encrypt가 우리 도메인에 GET 시도 → 통과 시 인증서 발급
       │
       ▼
[cert-manager]
   - 발급된 인증서를 Secret(type=kubernetes.io/tls)으로 저장
   - 90일 후 만료 → 다시 위 과정 자동 반복
```

내부 CA(self-signed) 발급자는 더 단순해요. cert-manager가 가진 CA 키로 그냥 sign해서 Secret으로 만들어요.

### 3.5 주요 기능

- ACME(Let's Encrypt, ZeroSSL) 자동 발급
- HashiCorp Vault, Venafi, AWS PCA 같은 엔터프라이즈 Issuer
- Self-signed / CA 발급자
- 인증서 자동 갱신 (만료 30일 전)
- Ingress 어노테이션으로 한 줄 발급 (`cert-manager.io/cluster-issuer: ...`)

### 3.6 다른 도구와 비교

| 도구 | K8s 통합 | 자동 갱신 | 우리 평가 |
|---|---|---|---|
| **cert-manager** | ✅ Native | ✅ | ✅ |
| 수동 발급 + Secret 관리 | △ | ❌ | ✗ (운영 부담↑) |
| acme.sh 스크립트 + cron | △ | △ | ✗ (K8s 밖, 스케일↓) |
| HashiCorp Vault 직접 | ✅ | ✅ | △ (Vault 운영 필요) |

---

## 4. 우리가 왜 이걸 썼나 (Why)

### 4.1 대안 비교 (MetalLB)

| 대안 | 베어메탈 LB | 운영 부담 | 학습 가치 | 최종 판단 |
|---|---|---|---|---|
| **MetalLB (L2)** | ✅ | 낮음 | 표준 학습 | ✅ |
| kube-vip | ✅ + CP VIP까지 | 중 | 통합 학습 | 다음 라운드 |
| 수동 keepalived | ✅ | **높음** | 일반 네트워크 학습 | ✗ |

### 4.2 대안 비교 (cert-manager)

| 대안 | 자동 갱신 | K8s native | 우리 환경 적합 | 최종 판단 |
|---|---|---|---|---|
| **cert-manager** | ✅ | ✅ | Percona Operator가 의존 | ✅ |
| 수동 + Secret apply | ❌ | △ | 의존성 못 풀어줌 | ✗ |

### 4.3 현업 표준과의 정합성

- **MetalLB L2**: 베어메탈 K8s의 사실상 표준. CNCF Incubating 프로젝트.
- **cert-manager**: K8s 인증서 자동화의 사실상 표준. CNCF Graduated 단계.
- 우리 구성(K8s + Calico + MetalLB + cert-manager + Ceph)은 **온프레 K8s 정석 스택**이에요.

### 4.4 선택 근거 (트레이드오프)

| 선택 | 얻는 것 | 잃는 것 |
|---|---|---|
| **MetalLB L2** | 스위치 BGP 설정 불필요 | 한 IP당 노드 1대만 응답 → 노드의 NIC 대역폭이 병목 |
| **MetalLB BGP** (대안) | 모든 노드가 ECMP로 부하 분산 | 스위치/라우터 BGP 설정 필요 |
| **cert-manager + self-signed CA** | 내부망 TLS 자동화, 인터넷 의존 X | 브라우저 신뢰 안 됨 (사내 CA 배포 필요) |
| **cert-manager + Let's Encrypt** | 브라우저가 신뢰 | 공개 DNS + 외부 도달 필요 |

우리는 1차로 self-signed CA + Percona 내부 TLS, ArgoCD UI 등에 사용. 외부 노출 시점에 Let's Encrypt로 전환할 예정.

---

## 5. 우리 환경 구성

### 5.1 토폴로지

```
VLAN 30 (172.16.23.0/24) — K8s 노드 네트워크
   ┌────────────────────────────────────────────────────────┐
   │  Pool: 172.16.23.100 - 172.16.23.150                  │
   │                                                        │
   │  실제 할당된 External-IP들:                            │
   │    .101 ─→ argocd-server     (ArgoCD UI)              │
   │    .102 ─→ kube-prom-grafana (Grafana)                │
   │    .103 ─→ ticket-app        (FastAPI)                │
   │    .104~ ─→ 추후 할당                                  │
   │                                                        │
   │  K8s 노드들: cp1~3 (.10~.12), w1~3 (.20~.22)          │
   └────────────────────────────────────────────────────────┘
                            │
                            ▼
                       [pfSense GW]
                       172.16.23.1
```

**핵심**: External-IP는 **K8s 노드와 같은 VLAN/서브넷**에 있어야 ARP 응답이 의미가 있어요. 다른 VLAN이면 L3 라우팅 필요해서 L2 모드 동작 불가.

### 5.2 핵심 설정값과 근거

| 항목 | 값 | 근거 |
|---|---|---|
| MetalLB 버전 | `v0.13+` | K8s 1.30 호환, CRD 안정화 라인 |
| 모드 | **L2 (ARP)** | 스위치 BGP 미설정, 단순 구성 |
| IP 풀 | `172.16.23.100-172.16.23.150` (51개) | VLAN 30 안, DHCP 풀(100-200)과 일부 겹침 주의 — 풀 끝을 150으로 제한 |
| Namespace | `metallb-system` | 컨벤션 |
| Pod security | `privileged` | speaker가 kernel-level network 조작 |
| cert-manager 버전 | `v1.13+` | Percona Operator와 검증된 조합 |
| Self-signed Issuer | ClusterIssuer | 모든 ns에서 사용 |

### 5.3 다른 컴포넌트와의 연결

```
[Service Type=LoadBalancer 생성]
     │
     ▼
[MetalLB Controller] ─ IP 풀에서 IP 골라 .status.loadBalancer.ingress에 적음
     │
     ▼
[MetalLB Speaker] ─ leader 노드에서 ARP 응답 시작
     │
     ▼
[외부 클라이언트] ─ 그 IP로 접근 → leader 노드 NIC → kube-proxy → Pod

[Certificate CR 생성]
     │
     ▼
[cert-manager Controller] ─ Issuer에 발급 요청
     │
     ▼
[Secret(tls.crt + tls.key) 생성]
     │
     ▼
[Ingress / Pod / Percona Operator] 가 Secret 참조
```

---

## 6. 실제 코드 / 설정 파일

### 6.1 MetalLB 설치 (`40-k8s-addons.yml`)

경로: `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml` (라인 186~244)

```yaml
- name: MetalLB namespace 생성 (privileged label 필요)
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Namespace
      metadata:
        name: metallb-system
        labels:
          pod-security.kubernetes.io/enforce: privileged

- name: MetalLB 설치
  kubernetes.core.helm:
    name: metallb
    chart_ref: metallb/metallb
    release_namespace: metallb-system
    wait: true
    wait_timeout: 5m

- name: MetalLB IPAddressPool 설정
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: metallb.io/v1beta1
      kind: IPAddressPool
      metadata:
        name: kosa-pool
        namespace: metallb-system
      spec:
        addresses:
          - 172.16.22.50-172.16.22.100   # ← 옛 값 (VLAN 20)
                                          # 운영 중 172.16.23.100-150으로 변경됨

- name: MetalLB L2Advertisement 설정
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: metallb.io/v1beta1
      kind: L2Advertisement
      metadata:
        name: kosa-l2adv
        namespace: metallb-system
      spec:
        ipAddressPools:
          - kosa-pool
```

**왜 이 옵션?**

- `pod-security.kubernetes.io/enforce: privileged`: MetalLB speaker는 raw socket + iptables 조작이 필요해서 privileged 권한 필수. baseline/restricted ns에는 못 들어가요.
- L2Advertisement는 IPAddressPool과 **별도 리소스**예요. 풀은 "내가 쓸 수 있는 IP들"이고, Advertisement는 "그 IP를 어떻게 광고할지". L2 / BGP 두 모드 분리.

### 6.2 cert-manager 설치

같은 playbook 라인 338~347:

```yaml
- name: cert-manager 설치 (Percona Operator가 TLS 자동 발급 위해 필요)
  kubernetes.core.k8s:
    state: present
    src: https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

- name: cert-manager 준비 대기 (1분)
  ansible.builtin.command: >
    kubectl wait --for=condition=Available deployment/cert-manager
    -n cert-manager --timeout=180s
  changed_when: false
```

**왜 이 옵션?**

- 단일 manifest (CRD + RBAC + Deployment 모두 포함). Helm 안 써도 됨.
- `v1.14.0`: Percona PXC Operator 1.14.0이 의존하는 버전대.
- `kubectl wait`: Deployment가 Available이 될 때까지 막아두지 않으면 그 다음 Percona Operator 설치 시 webhook 호출 실패할 수 있어요.

### 6.3 Self-signed ClusterIssuer 예시

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
```

이 한 줄짜리 CR만 있으면 어떤 Certificate든 자기 자신을 sign해서 인증서를 만들어줘요. 내부 통신용 TLS에 가장 흔히 쓰는 패턴.

### 6.4 Certificate CR 예시 (애플리케이션 TLS)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ticket-app-tls
  namespace: kosa-tickets
spec:
  secretName: ticket-app-tls-secret   # 이 이름으로 Secret 생성됨
  dnsNames:
    - ticket.kosa.local
    - 172.16.23.103
  issuerRef:
    name: selfsigned-cluster-issuer
    kind: ClusterIssuer
```

cert-manager가 이걸 보고 자동으로 Secret 만들어줘요. Ingress/Pod이 이 Secret을 참조하면 끝.

---

## 7. 실행 + 결과

### 7.1 MetalLB 검증

```bash
kubectl get pods -n metallb-system
```

```
NAME                          READY   STATUS    RESTARTS   AGE
controller-7d4f6b9b5b-abcde   1/1     Running   0          3d
speaker-aaaaa                 1/1     Running   0          3d
speaker-bbbbb                 1/1     Running   0          3d
speaker-ccccc                 1/1     Running   0          3d
speaker-ddddd                 1/1     Running   0          3d
speaker-eeeee                 1/1     Running   0          3d
speaker-fffff                 1/1     Running   0          3d
```

speaker는 DaemonSet이라 6개 (CP+Worker 전부). controller는 1개.

```bash
kubectl get ipaddresspool -A
```

```
NAMESPACE        NAME         AUTO ASSIGN   ADDRESSES
metallb-system   kosa-pool    true          ["172.16.23.100-172.16.23.150"]
```

### 7.2 실제 LoadBalancer 부여 확인

```bash
kubectl get svc -A | grep LoadBalancer
```

우리 환경:

```
argocd        argocd-server               LoadBalancer   10.96.x.x   172.16.23.101   80:30880/TCP,443:30443/TCP
monitoring    kube-prom-grafana           LoadBalancer   10.96.x.x   172.16.23.102   80:30090/TCP
kosa-tickets  ticket-app                  LoadBalancer   10.96.x.x   172.16.23.103   80:30100/TCP
```

External-IP가 Pending이 아니면 성공.

### 7.3 외부 도달 테스트

노트북에서:

```bash
curl -I http://172.16.23.103
```

```
HTTP/1.1 200 OK
```

### 7.4 cert-manager 검증

```bash
kubectl get pods -n cert-manager
```

```
cert-manager-xxx                  1/1     Running
cert-manager-cainjector-xxx       1/1     Running
cert-manager-webhook-xxx          1/1     Running
```

3개가 다 Running이면 OK. webhook이 NotReady면 그 다음 모든 Certificate 생성이 막힙니다.

---

## 8. 함정 + 디버깅

### 함정 1 — External-IP 부여됐는데 ping/curl 안 됨 (★ 실제 발생)

**증상**:

```bash
kubectl get svc ticket-app -n kosa-tickets
# EXTERNAL-IP: 172.16.22.55   ← 부여는 됐는데
curl 172.16.22.55             # timeout
```

**원인 (메커니즘)**: 이게 우리가 직접 만난 함정이에요. 처음 IPAddressPool을 `172.16.22.50-100` (VLAN 20)으로 만들었는데, K8s 노드는 모두 VLAN 30(172.16.23.0/24)에 있었어요.

L2 모드는 다음 흐름으로 동작해요:
1. 사용자가 172.16.22.55에 접근 시도
2. 사용자 측 라우터/스위치가 ARP "172.16.22.55 가진 놈?" 브로드캐스트
3. 그 ARP는 **VLAN 20**에 뿌려짐
4. 그런데 우리 K8s 노드의 NIC는 VLAN 30 → VLAN 20의 ARP를 못 받음
5. 아무도 응답 안 함 → 사용자는 timeout

요점: **MetalLB L2 모드는 풀의 IP가 노드와 같은 L2 도메인에 있어야 동작합니다**. L3로 라우팅된 다른 VLAN에서는 ARP가 안 닿아요.

**해결**:

```bash
kubectl -n metallb-system patch ipaddresspool kosa-pool --type='merge' \
  -p '{"spec":{"addresses":["172.16.23.100-172.16.23.150"]}}'

# 기존 Service의 External-IP 재할당 트리거
kubectl -n kosa-tickets patch svc ticket-app -p '{"spec":{"loadBalancerIP":null}}'
kubectl -n kosa-tickets delete svc ticket-app
kubectl apply -f ticket-app-svc.yaml
```

또는 Service 토글(type을 ClusterIP로 바꿨다가 다시 LoadBalancer로) 해도 재할당돼요.

**왜 이 함정이 발생하는가**: MetalLB의 동작 원리는 단순하지만, **L2 도메인 개념**을 안 가지고 들어가면 빠지기 쉬워요. 클라우드 LB는 L3 라우팅까지 알아서 해주니까 익숙해진 사고방식이 안 통합니다.

### 함정 2 — External-IP가 Pending에서 안 빠짐

**증상**:

```
EXTERNAL-IP: <pending>
```

**원인 후보**:
1. IP 풀이 다 떨어짐 (51개 다 사용)
2. MetalLB controller Pod 죽음
3. IPAddressPool / L2Advertisement 둘 중 하나만 있음

**해결 진단**:

```bash
kubectl logs -n metallb-system deploy/controller
```

```bash
kubectl get ipaddresspool -A
kubectl get l2advertisement -A
```

둘 다 있어야 동작. 풀만 있고 L2Advertisement 없으면 IP는 잡혔는데 광고가 안 돼서 도달 불가.

### 함정 3 — cert-manager webhook 호출 실패

**증상**: Certificate 만들 때:

```
Internal error occurred: failed calling webhook "webhook.cert-manager.io": ...
```

**원인**: webhook Pod이 아직 Ready 아닌 상태에서 호출. 또는 CA bundle 갱신이 아직 안 됐을 수 있어요.

**해결**: 단순히 기다리거나 재적용:

```bash
kubectl wait --for=condition=Available deployment/cert-manager-webhook \
  -n cert-manager --timeout=180s
```

playbook의 `kubectl wait` task가 이걸 해주는 이유예요.

### 함정 4 — Let's Encrypt rate limit

**증상**: 인증서 발급 반복 시도 후:

```
urn:ietf:params:acme:error:rateLimited
```

**원인**: Let's Encrypt는 도메인당 주 50개 인증서 제한. 테스트 시 staging 환경 안 쓰면 금방 도달.

**해결**: 개발/테스트에선 staging 발급자 사용.

```yaml
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
```

또는 self-signed 발급자로 일단 동작 확인 후 prod로 전환.

---

## 9. 더 깊이 공부할 자료

### 공식 문서
- MetalLB: https://metallb.universe.tf/
- cert-manager: https://cert-manager.io/docs/

### 책 / 강의
- *Kubernetes Networking and Service Mesh* (Manning)
- "Bare Metal Kubernetes" — Equinix Metal 발표 시리즈

### 우리 프로젝트 관련 파일
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml` (라인 186~244, 338~347)
- `/Users/sangjjang/kosa_infra_project/inventory.md` (External-IP 할당표)

---

> 다음 챕터 미리보기 — 영구 스토리지가 어떻게 동작할까요? Ceph의 RADOS 위에 RBD/CephFS/RGW가 어떻게 쌓이는지, 우리 클러스터의 6노드 6TB Raw가 어떻게 K8s PVC가 되는지 들어갑니다.
