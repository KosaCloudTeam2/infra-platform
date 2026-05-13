# 왜 Bastion에서 Ansible을 돌리는가

> KOSA Infra Project — kosa-tickets 우리 환경 기준으로 풀어 쓴 설명

---

## 결론부터

**우리 환경에선 "기술적으론 필수 아님, 운영적으로 강력 추천"이야.**

노트북에서 직접 ansible-playbook 돌리는 것도 가능해. 그런데 그렇게 안 하고 Bastion 경유로 가는
이유를 아래에 우리 환경 그대로 풀어 썼어.

---

## 0. 우리 환경 그림으로 먼저 잡기

```
                        ┌─ 인터넷 ─┐
                        │           │
                  ┌─────▼───────────▼─────┐
                  │   TP-Link 라우터       │ 192.168.21.1
                  └──────────┬─────────────┘
                             │
                  ┌──────────▼──────────────┐
                  │   관리 스위치           │
                  └──────────┬──────────────┘
            ┌────────┬───────┼───────┬──────┬──────────┐
            │        │       │       │      │          │
       [노트북 4대]                                  [Proxmox 4대]
       192.168.21.x                              192.168.21.2~5
                                                  └─ pfSense VM 2대
                                                     (CARP VIP 192.168.21.10)
                                                  └─ VLAN 30/40/etc

  ┌─────────────── pfSense가 라우팅 ──────────────┐
  │                                                │
  │   VLAN 30 (Internal)        VLAN 40 (Mgmt)    │
  │   172.16.23.0/24            172.16.24.0/24    │
  │   ┌───────────┐             ┌───────────┐     │
  │   │ k8s-cp1   │ .10         │ bastion   │ .10 │
  │   │ k8s-cp2   │ .11         └───────────┘     │
  │   │ k8s-cp3   │ .12                            │
  │   │ k8s-w1    │ .20                            │
  │   │ k8s-w2    │ .21                            │
  │   │ k8s-w3    │ .22                            │
  │   └───────────┘                                │
  └────────────────────────────────────────────────┘
```

핵심 포인트:

- **노트북**은 `192.168.21.x` 대역에 있어
- **K8s VM들**은 `172.16.23.x` 대역에 있어 (전혀 다른 대역)
- 노트북 → K8s VM 으로 가려면 반드시 **pfSense**를 통과해야 함
- **Bastion**은 `172.16.24.x` 대역(VLAN 40) — VM 끼리 같은 네트워크 안에 있음

---

## 1. "노트북에서 직접" vs "Bastion 경유" — 시나리오로 비교

### 시나리오: 6대 K8s VM에 containerd 설치하기 (ansible playbook 10번)

#### A안 — 노트북에서 직접 실행

```bash
# 노트북에서
cd ~/kosa_infra_project/ansible
ansible-playbook playbooks/10-containerd.yml
```

Ansible은 내부적으로 이런 일을 함:

```
[노트북 192.168.21.x] ──SSH──→ [k8s-cp1 172.16.23.10] 명령 1번 실행
[노트북 192.168.21.x] ──SSH──→ [k8s-cp2 172.16.23.11] 명령 2번 실행
[노트북 192.168.21.x] ──SSH──→ [k8s-cp3 172.16.23.12] 명령 3번 실행
[노트북 192.168.21.x] ──SSH──→ [k8s-w1  172.16.23.20] 명령 4번 실행
[노트북 192.168.21.x] ──SSH──→ [k8s-w2  172.16.23.21] 명령 5번 실행
[노트북 192.168.21.x] ──SSH──→ [k8s-w3  172.16.23.22] 명령 6번 실행
```

각 SSH가 **pfSense를 통과** 해야 함. 그러려면 pfSense에 룰 6개 (또는 대역으로 1개) 추가 필요:

```
Rule: Allow from 192.168.21.0/24 to 172.16.23.0/24 port 22
```

#### B안 — Bastion 경유

```bash
# 1) 노트북 → bastion 으로 코드 전송 (한 번만)
scp -r ~/kosa_infra_project/ansible bastion:~/

# 2) 노트북 → bastion 으로 ssh
ssh bastion

# 3) bastion 안에서 ansible 실행
cd ~/ansible
ansible-playbook playbooks/10-containerd.yml
```

Ansible은 이제:

```
[bastion 172.16.24.10] ──SSH──→ [k8s-cp1 172.16.23.10]  ← VM간 통신
[bastion 172.16.24.10] ──SSH──→ [k8s-cp2 172.16.23.11]
...
```

pfSense에서 필요한 룰은 **딱 2개**:

1. `Allow from 192.168.21.0/24 to 172.16.24.10 port 22` (노트북→bastion)
2. `Allow from 172.16.24.0/24 to 172.16.23.0/24 port 22` (bastion→K8s)

→ **외부(노트북)에서 K8s VM으로 직접 접근하는 길은 막혀 있음.**

---

## 2. 왜 그 작은 차이가 중요한가 (우리 환경 기준)

### (1) pfSense 방화벽 룰을 단순하게 유지

우리 pfSense는 이미 VLAN 라우팅 + CARP HA + 여러 룰로 복잡한 상태야. 거기에 노트북 4대마다 룰을
추가하면 **유지보수 지옥**.

```
[노트북에서 직접의 경우]
- 노트북 1: 룰 추가 — 192.168.21.50 → 172.16.23.0/24
- 노트북 2: 룰 추가 — 192.168.21.51 → 172.16.23.0/24
- 노트북 3: 룰 추가 — 192.168.21.52 → 172.16.23.0/24
- 노트북 4: 룰 추가 — 192.168.21.53 → 172.16.23.0/24
... 노트북 추가/제거 시마다 pfSense 변경 필요

[Bastion 경유의 경우]
- 노트북 전체: 룰 1개 — 192.168.21.0/24 → 172.16.24.10
- Bastion: 룰 1개 — 172.16.24.10 → 172.16.23.0/24
... 노트북이 늘어도 pfSense는 변경 없음
```

### (2) SSH 키 분실 사고 시 피해 범위

우리 키는 `~/.ssh/kosa_iac` 야. 이게 노트북에 있으면:

```
[노트북에서 직접의 경우]
- 팀원 4명 노트북에 kosa_iac 키가 각각 있음
- 한 명이 노트북 분실 → 키 1개 외부 유출 → 모든 K8s VM 접근 가능 상태
- 대응: 6대 VM 전부에 새 키 재배포 → cloud-init 재실행 또는 수동 작업

[Bastion 경유의 경우]
- 팀원 4명: bastion 접속용 키만 보유
- Bastion: K8s VM 접근용 키 보유 (1개)
- 노트북 분실 → bastion 접속 키만 회수하면 끝 (bastion에서 authorized_keys 줄 삭제)
- K8s VM의 키는 그대로 — 6대 재배포 안 해도 됨
```

이건 진짜 운영 사고 났을 때 30분 vs 3시간 차이.

### (3) 팀 4명이 같은 Ansible 환경을 쓸 수 있음

우리 팀원 노트북 OS/버전:

- 본인: macOS, Python 3.11, ansible 2.16
- 팀원 B: Windows + WSL Ubuntu 22, Python 3.10, ansible 2.14
- 팀원 C: macOS, Python 3.12, ansible 2.17
- 팀원 D: Linux Mint, Python 3.9, ansible 2.13

이 상태로 **각자 노트북에서 ansible-playbook 돌리면**:

- 같은 playbook이 누구는 되고 누구는 안 됨
- "내 노트북에선 되는데?" 가 자주 발생
- ansible.cfg, inventory, group_vars 버전이 4명 사이에 불일치

**Bastion에서 돌리면**:

- 4명 모두 같은 Ubuntu 24.04, 같은 Python 3.12, 같은 ansible 버전
- inventory 한 곳에 두고 모두가 동일하게 사용
- "내 노트북에선 안 되는데?" 가 사라짐

### (4) 명령 이력 / 감사 로그 한곳에

데모 리허설하다가 "어? 이거 어제 누가 바꿨지?" 상황:

```bash
# Bastion에서
ssh bastion
sudo journalctl _COMM=sshd | grep "Accepted"
# → 누가 언제 접속했는지

cat ~/.bash_history
# → 어떤 명령 실행했는지

ls -la ~/.ansible/
# → 마지막 실행 시간
```

노트북 4대에 흩어져 있으면 4대 다 뒤져야 함. Bastion 한 곳에 있으면 5분 만에 추적.

### (5) 24시간 가동 = 자동화 가능

우리가 Day 10 이후 자동화할 것들:

- **GitHub Actions self-hosted runner** — 코드 push 되면 자동으로 ansible 돌리기
- **cron으로 백업** — DB 백업, etcd 스냅샷 매일 새벽 3시
- **모니터링 알람** — Slack/Discord webhook

이게 노트북에 있으면? 노트북 꺼지면 멈춤. **24시간 켜져 있는 VM(Bastion)이 자연스러운 위치**.

### (6) AWS 통합 시 (Day 8 이후)

AWS Phase 2부터 VPN 켜면 온프레 ↔ AWS 양방향 통신 시작. AWS EC2 (HAProxy 2대)를 ansible로
관리하려면:

```
[bastion 172.16.24.10] ──VPN──→ [AWS EC2 10.20.1.x]
```

Bastion이 VPN 안쪽에 있어서 AWS 내부 IP로 직접 접근 가능. **노트북에선 AWS 내부 IP로 못 가서 매번
SSM 또는 공인 IP 거쳐야 함**.

---

## 3. 우리 환경에서 "노트북 직접"의 실제 함정들

이론은 알겠는데 정말 노트북에서 ansible 돌리면 뭐가 빠르게 안 좋아지나? 예측:

| 상황                             | 노트북 직접                                   | Bastion                                 |
| -------------------------------- | --------------------------------------------- | --------------------------------------- |
| 팀원 D가 새로 합류, ansible 셋업 | 1시간 (Python, ansible, 키, inventory 동기화) | 5분 (bastion ssh만 알려주면 끝)         |
| 팀원 B 노트북 분실               | 6시간 (모든 키 재발급 + VM 재배포)            | 10분 (bastion authorized_keys 정리)     |
| "어제 누가 PXC 재시작했어?"      | 4명 노트북 다 확인                            | bastion 히스토리 1개 확인               |
| AWS 통합 후 EC2 운영             | 매번 SSM 또는 공인 IP                         | bastion에서 사설 IP로 직통              |
| 데모 발표 (4명이 번갈아 명령)    | 노트북 4대 환경 다 동기화 필요                | 모두가 bastion에 ssh → 동일 환경        |
| 발표 임팩트                      | "각자 노트북에서 작업"                        | "**중앙 운영 거점 Bastion**" (가산점 ↑) |

---

## 4. 우리 프로젝트에서 Bastion이 실제로 하는 일

Day별로 풀어보면:

### Day 1~5: 온프레 구축

```bash
ssh bastion
cd ~/ansible
ansible all -m ping                              # 6대 VM 연결 확인
ansible-playbook playbooks/00-common.yml        # 기본 패키지 설치
ansible-playbook playbooks/10-containerd.yml    # 컨테이너 런타임
ansible-playbook playbooks/20-kubeadm-init.yml  # K8s 컨트롤플레인 초기화
ansible-playbook playbooks/30-join-workers.yml  # 워커 조인
ansible-playbook playbooks/40-k8s-addons.yml    # Calico, MetalLB, HAProxy Ingress, Percona Operator
```

### Day 6~7: 앱/DB 배포

```bash
ssh bastion
kubectl get nodes                                # 클러스터 확인
helm install pxc-operator percona/pxc-operator   # Percona Operator
kubectl apply -f manifests/pxc-cluster.yaml      # PXC 5노드 클러스터
argocd app sync kosa-tickets                     # ArgoCD로 앱 동기화
```

### Day 8~11: AWS 통합

```bash
ssh bastion
# Bastion이 VPN 안쪽이라 AWS 내부 IP로 직접 접근
ssh ec2-haproxy-1.internal.aws
ansible-playbook -i aws_inventory playbooks/aws-setup.yml
```

### Day 12~13: 데모 리허설

```bash
ssh bastion
# JMeter로 10K RPS 부하
jmeter -n -t scenarios/ticket-burst.jmx
# 동시에 다른 터미널에서 모니터링
kubectl top pods -w
```

### Day 14~15: 발표

> **"우리는 운영 거점으로 Bastion 1대를 두어 SSH 키, kubectl 컨텍스트, ArgoCD CLI를 집중 관리합니다.
> 노트북에선 Bastion으로만 SSH가 허용되며, 모든 운영 명령은 Bastion에서 실행되어 감사 로그가
> 일원화됩니다."**

이 한 줄이 발표 점수 +5점이야.

---

## 5. "그래도 노트북에서 하면 안 돼?" — 정직한 답변

**돼.** 학습용으론 충분히 가능해. 단:

1. pfSense에 룰 추가 (192.168.21.0/24 → 172.16.23.0/24 port 22)
2. 팀원 4명 노트북에 ansible/Python/inventory 동기화
3. 키 분실 시 즉각 모두 회수 가능한 절차 합의
4. 명령 이력은 각자 알아서 관리

이걸 다 감수하면 노트북 직접도 됨. **그치만 그걸 감수하느니 Bastion 1대 더 돌리는 게 훨씬 싸.**
Bastion은 어차피 2GB RAM 1 vCPU짜리 작은 VM이라 부담 거의 없음.

---

## 6. 정리

| 질문                    | 답                                                    |
| ----------------------- | ----------------------------------------------------- |
| 기술적으로 필수?        | **아니**                                              |
| 우리 환경에서 권장?     | **응 (강력)**                                         |
| 핵심 이유 1개만 꼽으면? | "**pfSense 룰 단순 + 키 집중 + 팀 일관성**" 한 패키지 |
| 발표에서 어필 가능?     | **응. 보안/운영 표준 항목으로**                       |
| 셋업 비용?              | bastion VM 1대 (이미 있음) + 도구 설치 (5분 스크립트) |

**한 줄로:** Bastion은 우리 4명이 운영 명령을 모아서 실행하는 "공용 사무실" 같은 거야. 각자
집(노트북)에서 일해도 되지만, 공용 사무실 두면 협업·보안·감사 다 한 번에 해결됨.

---

> 더 깊이: SSH 설정은 `SSH_Access_Guide.md`, 실제 setup 스크립트는 `scripts/setup-bastion.sh`,
> Ansible 인벤토리는 `ansible/inventory/hosts.yml` 참고.
