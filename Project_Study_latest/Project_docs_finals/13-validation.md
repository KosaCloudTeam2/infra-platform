# 13. 전체 검증 (Validation Runbook)

> **이 챕터에서 다루는 것**<br> 인프라가 설계대로 동작하는지 한 번에 훑는 체크리스트 + 명령어.<br>
> 사용법: 위에서 아래로 순차 실행, 각 섹션 끝에 있는 "결과 기록" 표에 체크 후 commit.<br> 매 분기
> 1회 + 큰 변경 후 매번 수행 권장.

---

## 📌 명령 실행 위치 표기 규칙

각 코드 블록 첫 줄 주석에 **`# 📍 <어디서>`** 명시.<br> 헷갈리지 않게 호스트 약어 통일:

| 약어                          | 실제 호스트             | IP                 | 접근 방법                                |
| ----------------------------- | ----------------------- | ------------------ | ---------------------------------------- |
| **bastion**                   | bastion VM              | 172.16.24.10       | (시작점) — SSH 또는 직접 로그인          |
| **cp1, cp2, cp3**             | K8s Control Plane       | 172.16.23.10/11/12 | `ssh ubuntu@<IP>` (bastion에서)          |
| **w1, w2, w3**                | K8s Worker (production) | 172.16.23.20/21/22 | `ssh ubuntu@<IP>`                        |
| **sys1**                      | K8s Worker (system)     | 172.16.23.23       | `ssh ubuntu@<IP>`                        |
| **lb-1, lb-2**                | K8s API LB              | 172.16.23.6/7      | `ssh ubuntu@<IP>`                        |
| **edge-1, edge-2**            | Edge HAProxy            | 172.16.22.10/11    | `ssh ubuntu@<IP>`                        |
| **ceph1~6**                   | Ceph 노드               | 10.10.10.11~16     | `ssh root@<IP>` (cephadm 환경)           |
| **kosa1~4**                   | Proxmox 호스트          | 192.168.21.2~5     | `ssh root@<IP>`                          |
| **pfSense Primary/Secondary** | pfSense VM              | (콘솔 or Web UI)   | Proxmox Console 또는 https://172.16.21.1 |
| **K8s Pod 안**                | (Pod 내부)              | —                  | `kubectl exec -it ...` (bastion에서)     |
| **노트북**                    | 팀원 노트북             | 192.168.21.x       | (검증자 본인 PC)                         |

### 코드 블록 prefix 예시

```bash
# 📍 bastion에서
kubectl get nodes
```

```bash
# 📍 ceph1 (10.10.10.11) 에서
ceph -s
```

```bash
# 📍 cp1 (172.16.23.10) 에서
sudo systemctl restart kubelet
```

```bash
# 📍 K8s Pod 안 (kubectl exec로 진입)
fio --name=test ...
```

```bash
# 📍 노트북 (외부 환경) 에서
ping 192.168.21.109
```

> 💡 SSH 한 번에 풀린 명령은 `ssh user@host "cmd"` 형태로 한 줄 — 어디서 실행하는지가 명백.

---

## 목차

0. [시작 전: kubectl 안 되면 먼저 복구](#0-시작-전-kubectl-안-되면-먼저-복구)
1. [사전 준비 — bastion 환경](#1-사전-준비--bastion-환경)
2. [10G 대역폭 측정 (iperf3)](#2-10g-대역폭-측정-iperf3)
3. [Ceph IOPS 측정](#3-ceph-iops-측정)
4. [Redis 검증](#4-redis-검증)
5. [Harbor 검증](#5-harbor-검증)
6. [Jenkins / CI-CD 검증](#6-jenkins--ci-cd-검증)
7. [ArgoCD 검증](#7-argocd-검증)
8. [HA / Failover 시험](#8-ha--failover-시험)
9. [결과 기록 템플릿](#9-결과-기록-템플릿)
10. [다음 단계](#10-다음-단계)

---

## 0. 시작 전: kubectl 안 되면 먼저 복구

검증의 대부분이 K8s를 거치니, kubectl이 안 되면 여기서부터.

```bash
# 📍 bastion에서
# 증상 예: "Get https://172.16.23.5:6443/api?timeout=32s: EOF"
kubectl get nodes
```

### 0.1 1차 진단 (bastion에서)

```bash
# 📍 bastion에서 (ssh로 각 노드 점검)

# (a) API VIP 어느 LB가 들고 있나
for ip in 172.16.23.6 172.16.23.7; do
  echo "=== lb $ip ==="
  ssh -o ConnectTimeout=3 ubuntu@$ip \
    "ip addr show | grep 172.16.23.5; sudo systemctl is-active keepalived haproxy"
done

# (b) HAProxy backend 상태 (lb-1 내부 명령)
ssh ubuntu@172.16.23.6 \
  "echo 'show servers state' | sudo socat /run/haproxy/admin.sock - 2>/dev/null \
   || sudo cat /var/lib/haproxy/server-state 2>/dev/null"

# (c) CP 노드 API 직접 (LB 우회, bastion에서 curl)
for cp in 172.16.23.10 172.16.23.11 172.16.23.12; do
  echo "=== cp $cp ==="
  curl -k --connect-timeout 3 https://$cp:6443/healthz 2>&1
  echo
done

# (d) CP 노드 OS/데몬 살아있나
for cp in 172.16.23.10 172.16.23.11 172.16.23.12; do
  echo "=== cp $cp ==="
  ssh -o ConnectTimeout=3 ubuntu@$cp \
    "uptime && sudo systemctl is-active kubelet containerd \
     && sudo crictl ps 2>/dev/null | grep -c kube-apiserver"
done
```

### 0.2 해석 매트릭스

| (a) VIP             | (c) CP direct | 진단                     | 조치                              |
| ------------------- | ------------- | ------------------------ | --------------------------------- |
| 두 노드 다 없음     | -             | keepalived 둘 다 죽음    | 양쪽 `systemctl start keepalived` |
| 양쪽 다 있음        | -             | split-brain              | 한쪽 keepalived stop 후 재시작    |
| 한 쪽만 있음 (정상) | 모두 fail     | CP 다 죽음               | 0.3 절차                          |
| 한 쪽만 있음 (정상) | 1~2개 fail    | 일부 CP 죽음             | 죽은 CP 0.3                       |
| 한 쪽만 있음 (정상) | 모두 OK       | HAProxy 백엔드 설정 깨짐 | `sudo systemctl restart haproxy`  |

### 0.3 CP 노드 복구

```bash
# 📍 bastion에서 → 죽은 CP로 ssh 진입
ssh ubuntu@<죽은CP-IP>
```

```bash
# 📍 cp{1,2,3} 중 죽은 노드 안에서

# 데몬 재시작
sudo systemctl restart containerd
sudo systemctl restart kubelet

# static Pod 상태 (kubelet이 띄움)
sudo crictl ps | grep -E "kube-apiserver|etcd|kube-controller|kube-scheduler"

# 로그 (살아있는데 인증/네트워크 문제일 수도)
sudo journalctl -u kubelet -n 100 --no-pager
sudo crictl logs $(sudo crictl ps -a | grep kube-apiserver | head -1 | awk '{print $1}') 2>&1 | tail -50
```

### 0.4 etcd 헬스

```bash
# 📍 cp{1,2,3} 중 살아있는 CP 안에서
sudo ETCDCTL_API=3 etcdctl \
  --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert  /etc/kubernetes/pki/etcd/server.crt \
  --key   /etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster
```

3개 다 `is healthy: true` 나와야.

---

## 1. 사전 준비 — bastion 환경

### 1.1 도구 설치

```bash
# 📍 bastion에서 (모든 명령)
sudo apt update
sudo apt install -y iperf3 fio bc jq curl ncat netcat-openbsd dnsutils redis-tools

# kubectl (있을 것)
kubectl version --client

# argocd CLI — sudo 필수 (/usr/local/bin 쓰기 권한)
sudo curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd

# aws CLI (RGW용)
# Ubuntu 23.04+ / Debian 12+ 는 PEP 668 lock 때문에 pip 직접 설치 막힘.
# 3가지 옵션 중 택1:

# (A) apt — 단순, 버전 좀 옛버전이지만 S3 호환 호출엔 충분
sudo apt install -y awscli

# (B) pipx — 격리, 추천
sudo apt install -y pipx
pipx install awscli
pipx ensurepath && source ~/.bashrc

# (C) AWS 공식 배포 — 최신, Python 의존 X
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
cd ~

# 검증
aws --version
```

> ⚠️ **PEP 668 함정**: `pip install --user`가 "externally-managed-environment" 에러로 거부됨.
> `--break-system-packages` 플래그로 우회 가능하지만 권장 X. 위 (A)/(B)/(C) 중 선택.

### 1.2 SSH 키 + kubeconfig 확인

```bash
# 📍 bastion에서

# 모든 노드 SSH 통과
for h in 172.16.23.{10,11,12,20,21,22,23} 172.16.23.{6,7} \
         172.16.22.{10,11} 172.16.24.10 \
         10.10.10.{11,12,13,14,15,16}; do
  echo -n "$h: "
  ssh -o ConnectTimeout=2 -o BatchMode=yes ubuntu@$h "echo OK" 2>&1 \
    | tail -1
done

# kubectl
kubectl cluster-info
```

**📍 모든 명령은 bastion에서 (별도 명시 없을 시).**

#### 1.2.1 SSH `Permission denied (publickey)` 트러블슈팅

증상:

```
172.16.23.10: ubuntu@172.16.23.10: Permission denied (publickey).
...
10.10.10.15: Host key verification failed.
```

##### 진단 — bastion에서 4가지 먼저

```bash
# 📍 bastion에서
ls -la ~/.ssh/                    # (a) 키 파일 존재?
ssh-add -l 2>&1                   # (b) ssh-agent에 로드?
ls ~/.ssh/*.pub ~/.ssh/*.pem 2>/dev/null   # (c) 다른 이름의 키?
cat ~/.ssh/config 2>/dev/null     # (d) config에 키 지정?
```

##### 시나리오 A — 키는 있는데 이름이 default가 아님

`id_ed25519`, `id_rsa` 외 이름(`kosa-key`, `ansible-key` 등)이면 명시 필요.

```bash
# 📍 bastion에서

# 일회성
ssh -i ~/.ssh/<키이름> ubuntu@172.16.23.10

# 영구 (~/.ssh/config)
cat >> ~/.ssh/config <<EOF
Host 172.16.* 10.10.*
  User ubuntu
  IdentityFile ~/.ssh/<키이름>
  StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config
```

##### 시나리오 B — 키 있는데 ssh-agent에 미로드

```bash
# 📍 bastion에서
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519        # 또는 실제 키 이름
ssh-add -l                       # 확인
```

##### 시나리오 C — bastion `~/.ssh`가 진짜 비어있음

(bastion 재생성/cloud-init 재실행 등으로 키 유실)

새 키 생성 + 12+ 노드에 배포:

```bash
# 📍 bastion에서

# 1) 새 키 생성
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# 2-a) 비번 SSH 가능한 경우 (cloud-init 비번 살아있으면)
for h in 172.16.23.{10,11,12,20,21,22,23,6,7} 172.16.22.{10,11} 172.16.24.10; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@$h
done
```

```
# 📍 비번도 안 되면 — Proxmox Web UI → 각 VM Console로 직접 진입 후
#   (각 VM 안에서)
echo "<bastion 공개키 내용>" >> /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys
```

```bash
# 📍 Proxmox 호스트 (kosa1~4 중 해당 VM 있는 곳) 에서
#    — cloud-init으로 재주입 (대규모면 이게 빠름)
qm set <vmid> --sshkey ~/.ssh/id_ed25519.pub
qm reboot <vmid>
```

##### 시나리오 D — `Host key verification failed`

known_hosts에 옛 키가 남아있음 (VM 재생성 후 자주).

```bash
# 📍 bastion에서
ssh-keygen -R 10.10.10.15
# 또는 일괄
for h in 10.10.10.{11..16} 172.16.23.{10..12,20..23,6,7} 172.16.22.{10,11} 172.16.24.10; do
  ssh-keygen -R $h
done

# 또는 일회성으로 우회 (보안 약화, 주의)
ssh -o StrictHostKeyChecking=accept-new ubuntu@10.10.10.15
```

##### Ceph 노드는 `ubuntu` 계정이 아닐 수 있음

cephadm으로 부트스트랩한 경우 `root` 계정.

```bash
# 📍 bastion에서
ssh root@10.10.10.11
# 또는 cephadm SSH 키 사용
ssh -i /etc/ceph/ceph.pub root@10.10.10.11
```

`ubuntu` 사용 원하면 사용자 추가 + sudo 권한:

```bash
# 📍 ceph1 (root로 로그인 후) 에서
adduser ubuntu
usermod -aG sudo ubuntu
mkdir -p /home/ubuntu/.ssh
cp ~/.ssh/authorized_keys /home/ubuntu/.ssh/
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys
```

##### 검증 (모두 성공 시)

```bash
# 📍 bastion에서
for h in 172.16.23.{10..12,20..23,6,7} 172.16.22.{10,11} 172.16.24.10; do
  echo -n "$h: "
  ssh -o ConnectTimeout=2 -o BatchMode=yes ubuntu@$h "hostname" 2>&1 | tail -1
done

# Ceph는 root
for h in 10.10.10.{11..16}; do
  echo -n "$h: "
  ssh -o ConnectTimeout=2 -o BatchMode=yes root@$h "hostname" 2>&1 | tail -1
done
```

> 💡 **권장**: bastion `~/.ssh/id_ed25519` 키는 절대 분실 X. 새 팀원 합류/bastion 재구축 시 일이 큼.
> 백업: 키 파일을 1Password 등 비밀 관리자에 보관.

### 1.3 검증 로그 디렉토리

```bash
# 📍 bastion에서
export VAL_DIR=~/validation/$(date +%Y%m%d-%H%M)
mkdir -p $VAL_DIR
cd $VAL_DIR
```

이후 모든 검증 결과를 `$VAL_DIR/<section>.log`에 저장하면 추적 편함.

---

## 2. 10G 대역폭 측정 (iperf3)

### 2.1 측정 매트릭스

| 경로                              | 기대      | 의미                    |
| --------------------------------- | --------- | ----------------------- |
| Ceph 노드 ↔ Ceph 노드 (10G)       | ~9.4 Gbps | Ceph replication 헤드룸 |
| Proxmox ↔ Ceph (10G)              | ~9.4 Gbps | VM IO / Ceph 클라이언트 |
| K8s 워커 (10G NIC) ↔ Ceph         | ~9.4 Gbps | RBD IO                  |
| K8s 워커 ↔ K8s 워커 (VLAN 30, 1G) | ~940 Mbps | Pod 간 트래픽           |
| Pod ↔ Pod (Calico IPIP)           | ~860 Mbps | overhead 약 8~10%       |

### 2.2 노드 간 iperf3

> ⚠️ iperf3가 양쪽에 설치되어 있어야. 안 깔려있으면:
>
> ```bash
> # 📍 bastion에서 (Ceph 노드 6대 일괄)
> for ip in 10.10.10.{11..16}; do
>   ssh root@$ip "apt update && apt install -y iperf3" 2>&1 | tail -2
> done
> ```

서버 측 (한 호스트):

```bash
# 📍 bastion에서 → ceph1을 서버로 띄움 (daemonize)
ssh root@10.10.10.11 "iperf3 -s -D"
```

클라이언트 측 (다른 호스트):

```bash
# 📍 bastion에서 → ceph2를 client로
ssh root@10.10.10.12 "iperf3 -c 10.10.10.11 -t 30 -P 4" \
  | tee $VAL_DIR/iperf-ceph1-ceph2.log

# 끝나면 서버 정리
ssh root@10.10.10.11 "pkill iperf3"
```

결과의 `SUM ... receiver` 라인 보기. ~9.4 Gbps이면 OK.

### 2.3 전체 매트릭스 자동 실행

```bash
# 📍 bastion에서 (스크립트가 ssh로 각 노드에 접근)
cat > $VAL_DIR/iperf-matrix.sh <<'EOF'
#!/bin/bash
PAIRS=(
  "ceph1=10.10.10.11 ceph2=10.10.10.12"
  "ceph2=10.10.10.12 ceph3=10.10.10.13"
  "kosa1=10.10.10.35 ceph1=10.10.10.11"
  "kosa2=10.10.10.36 ceph2=10.10.10.12"
  "w1=10.10.10.120  ceph1=10.10.10.11"
  "w2=10.10.10.121  ceph2=10.10.10.12"
  "sys1=10.10.10.123 ceph3=10.10.10.13"
)
for pair in "${PAIRS[@]}"; do
  read -r s c <<< "$pair"
  sname=${s%%=*}; sip=${s##*=}
  cname=${c%%=*}; cip=${c##*=}
  echo "=== $sname -> $cname ==="
  ssh -o ConnectTimeout=3 ubuntu@$sip "pkill iperf3; iperf3 -s -D" 2>/dev/null
  sleep 1
  ssh ubuntu@$cip "iperf3 -c $sip -t 10 -P 4 -J" 2>/dev/null \
    | jq -r '.end.sum_received.bits_per_second / 1e9 | tostring + " Gbps"'
  ssh ubuntu@$sip "pkill iperf3" 2>/dev/null
done
EOF
chmod +x $VAL_DIR/iperf-matrix.sh
$VAL_DIR/iperf-matrix.sh | tee $VAL_DIR/iperf-summary.log
```

### 2.3.1 ⚠️ Pod-Pod가 어느 NIC을 타는지 먼저 확인

워커가 1G + 10G NIC 2개 가지면 Calico가 어느 IP로 tunnel 만드는지 결정적.

```bash
# (a) 노드 InternalIP (kubelet이 등록한 IP)
kubectl get nodes -o wide
# INTERNAL-IP가 172.16.23.x (1G)면 → Pod 트래픽도 1G ❌
# 10.10.10.x (10G)면 → 10G ✅

# (b) Calico tunl0 route (IPIP)
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l k8s-app=calico-node -o name | head -1) \
  -- ip route | grep tunl0

# (c) 실측 (§2.4의 Pod 간 iperf3)
```

**Pod-Pod가 1G인 게 확인됐고 업그레이드 원하면 — 옵션:**

> ⚠️ **제약**: 우리는 노드당 사용 가능한 10G NIC이 `enp1s0f0` 1개뿐. NIC 분리 불가, **Ceph와 K8s
> 트래픽 공유**가 불가피.

| 옵션                        | 명령                                                                                                    | 효과 / 주의                                    |
| --------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| A. Calico만 10G             | `kubectl set env ds/calico-node -n kube-system IP_AUTODETECTION_METHOD=can-reach=10.10.10.11` + rollout | Pod 트래픽 10G. Ceph와 NIC 공유                |
| B. 노드 InternalIP 자체 10G | kubelet `--node-ip=10.10.10.x` 재구성 + 재join                                                          | 모든 K8s 트래픽 10G. 가장 깨끗하지만 운영 부담 |
| D. 현 상태 유지             | (변경 X)                                                                                                | Pod-Pod 1G로 운영                              |

#### Ceph 양보 설정 (옵션 A/B 시 필수)

10G를 Ceph가 다 먹지 못하게 안전장치:

```bash
# Ceph 노드에서
ceph config set osd osd_max_backfills 1
ceph config set osd osd_recovery_max_active 2
ceph config set osd osd_recovery_op_priority 1
ceph config set osd osd_op_queue_cut_off high
```

→ Ceph recovery/rebalance를 의도적으로 천천히, client IO(=Pod 트래픽) 우선.

#### 현실 체크 — 정말 충돌 나나?

| 트래픽                | 평균        | 비상시 (rebalance/recovery) |
| --------------------- | ----------- | --------------------------- |
| Ceph 정상 운영        | 50~200 MB/s | —                           |
| Ceph 1 OSD 교체       | —           | 일시 500MB~1GB/s, 수십 분   |
| Ceph 큰 장애 recovery | —           | 1~5 GB/s, 수시간            |
| K8s Pod-Pod (앱)      | < 100 MB/s  | —                           |
| Redis Sentinel sync   | < 50 MB/s   | —                           |
| Prometheus federation | < 10 MB/s   | —                           |

**평상시 합계 ≪ 10Gbps**. Ceph 비상 상황에만 잠시 영향. 운영시간 외 stage 권장.

> 💡 **추천 진행**: 옵션 A 우선 적용 + Ceph 양보 설정. 한 분기 운영해보고 trouble 없으면 그대로.
> Pod-Pod 10G화 가치 충분 (Redis HA, PXC, Prometheus federation 등).

### 2.4 Pod ↔ Pod (Calico)

```bash
# 📍 bastion에서 (kubectl로 Pod 생성)
# 워커 다른 노드에 Pod 2개
kubectl create namespace netperf 2>/dev/null
kubectl run iperf-srv -n netperf --image=networkstatic/iperf3 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-w1"}}}' \
  -- -s
kubectl run iperf-cli -n netperf --image=networkstatic/iperf3 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-w2"}}}' \
  --rm -it --restart=Never \
  -- -c $(kubectl get pod iperf-srv -n netperf -o jsonpath='{.status.podIP}') -t 10

# 정리
kubectl delete pod iperf-srv -n netperf
kubectl delete namespace netperf
```

### 2.5 함정

- **`No such file or directory`** → iperf3 미설치. `apt install iperf3`
- **`Connection refused`** → 서버 측 미기동. `iperf3 -s -D` 또는 방화벽
- **1Gbps 수준 나옴** → 10G 링크 down. `ethtool enp1s0f0` 로 speed 확인, 케이블/SFP+ 점검
- **MTU 미스매치 (jumbo frame 쓸 때)** → 양쪽 `ip link set dev eth0 mtu 9000` 동일하게

---

## 3. Ceph IOPS 측정

### 3.1 측정 레벨

| 레벨           | 도구                          | 측정 대상                 |
| -------------- | ----------------------------- | ------------------------- |
| RADOS (object) | `rados bench`                 | OSD raw 처리량            |
| RBD (block)    | `rbd bench`                   | RBD 이미지 IO             |
| K8s Pod 안     | `fio`                         | end-to-end (PV mount까지) |
| RGW (S3)       | `s3-benchmark` 또는 `hsbench` | S3 객체 IO                |

### 3.2 RADOS bench (4K random write)

```bash
# 📍 bastion에서 → ceph1로 진입
ssh root@10.10.10.11
```

```bash
# 📍 ceph1 안에서

# 테스트용 pool
ceph osd pool create bench-pool 32 32
ceph osd pool application enable bench-pool benchmark

# Write (10초)
rados bench -p bench-pool 10 write -b 4096 -t 16 --no-cleanup \
  | tee ~/bench-write.log

# Sequential read
rados bench -p bench-pool 10 seq -t 16

# Random read
rados bench -p bench-pool 10 rand -t 16

# 정리
rados -p bench-pool cleanup
ceph osd pool delete bench-pool bench-pool --yes-i-really-really-mean-it
```

주요 출력: `Total time run`, `Total writes made`, `Average IOPS`, `Average Latency(s)`.

**기대값 (HDD 6 OSD, BlueStore, 4K random)**:

- Write: ~200~500 IOPS (HDD seek bound)
- Sequential read: ~5,000~15,000 IOPS (cache hit)
- Random read: ~500~1,500 IOPS

SSD WAL/DB 분리 시 write IOPS 2~3배 증가.

### 3.3 RBD bench

```bash
# 📍 bastion에서 → ceph1로 진입
ssh root@10.10.10.11
```

```bash
# 📍 ceph1 안에서

# 테스트 이미지
rbd create -p team2-rbd-block bench-img --size 2G --image-feature layering

# 4K random write
rbd bench --io-type write --io-size 4K --io-threads 16 \
  --io-total 256M --io-pattern rand -p team2-rbd-block bench-img

# 4K random read
rbd bench --io-type read --io-size 4K --io-threads 16 \
  --io-total 256M --io-pattern rand -p team2-rbd-block bench-img

# 1M sequential write (대역폭)
rbd bench --io-type write --io-size 1M --io-threads 8 \
  --io-total 1G --io-pattern seq -p team2-rbd-block bench-img

# 정리
rbd rm -p team2-rbd-block bench-img
```

### 3.4 fio inside K8s Pod (end-to-end)

```yaml
# 📍 bastion에서 → bench-pod.yaml 작성
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: fio-pvc, namespace: default }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: team2-rbd-block
  resources: { requests: { storage: 10Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: fio-bench, namespace: default }
spec:
  nodeSelector: { workload-type: production }
  restartPolicy: Never
  containers:
    - name: fio
      image: ljishen/fio
      command: ["sleep", "3600"]
      volumeMounts:
        - { name: data, mountPath: /data }
  volumes:
    - name: data
      persistentVolumeClaim: { claimName: fio-pvc }
```

```bash
# 📍 bastion에서 (kubectl로 모든 작업)
kubectl apply -f bench-pod.yaml
kubectl wait pod/fio-bench --for=condition=Ready --timeout=60s

# Random read+write 4K
kubectl exec fio-bench -- fio \
  --name=test --filename=/data/test.bin --size=1G \
  --rw=randrw --rwmixread=70 --bs=4k --iodepth=16 --runtime=30 \
  --time_based --ioengine=libaio --direct=1 --group_reporting \
  | tee $VAL_DIR/fio-randrw-4k.log

# Sequential write 1M
kubectl exec fio-bench -- fio \
  --name=seqw --filename=/data/test.bin --size=1G \
  --rw=write --bs=1M --iodepth=8 --runtime=30 \
  --time_based --ioengine=libaio --direct=1 \
  | tee $VAL_DIR/fio-seqw-1m.log

# 정리
kubectl delete pod fio-bench
kubectl delete pvc fio-pvc
```

fio 출력의 `IOPS=`, `bw=` 기록.

### 3.5 RGW (S3) bench

```bash
# 📍 bastion에서 (모든 명령)
export AWS_ACCESS_KEY_ID=<harbor user의 key>
export AWS_SECRET_ACCESS_KEY=<secret>
ENDPOINT=http://10.10.10.11:7480

# 작은 bucket 생성
aws --endpoint-url $ENDPOINT --region us-east-1 s3 mb s3://bench-bucket

# 1MB 파일 100개 upload time
mkdir -p /tmp/bench && cd /tmp/bench
for i in {1..100}; do dd if=/dev/urandom of=f$i bs=1M count=1 2>/dev/null; done

time aws --endpoint-url $ENDPOINT --region us-east-1 \
  s3 cp /tmp/bench s3://bench-bucket --recursive

# 정리
aws --endpoint-url $ENDPOINT --region us-east-1 s3 rm s3://bench-bucket --recursive
aws --endpoint-url $ENDPOINT --region us-east-1 s3 rb s3://bench-bucket
rm -rf /tmp/bench
```

---

## 4. Redis 검증

> **📍 4장의 모든 명령은 bastion에서 (kubectl exec로 Pod 내부 접근).**

### 4.1 Redis가 실제 사용되고 있나

```bash
# 📍 bastion에서
# Redis Pod 확인
kubectl get pods -n redis -l app.kubernetes.io/name=redis

# Sentinel 모드 확인
kubectl exec -n redis redis-node-0 -c redis -- redis-cli info replication
kubectl exec -n redis redis-node-0 -c sentinel -- redis-cli -p 26379 sentinel masters
```

기대: `role:master` 또는 `role:slave` 정상, sentinel masters에 1개 master 등록.

### 4.2 master/replica 매트릭스

```bash
# 📍 bastion에서
for i in 0 1 2; do
  echo "=== redis-node-$i ==="
  kubectl exec -n redis redis-node-$i -c redis -- redis-cli info replication | grep -E "role|connected_slaves|master_link"
done
```

3 노드 중 1개 master + 2개 slave가 정상.

### 4.3 key 저장/조회

```bash
# 📍 bastion에서

# Sentinel 통해 master 발견
MASTER=$(kubectl exec -n redis redis-node-0 -c sentinel -- \
  redis-cli -p 26379 sentinel get-master-addr-by-name mymaster | head -1)
echo "Master: $MASTER"

# 임시 port-forward (bastion에서 Redis svc로)
kubectl port-forward -n redis svc/redis 6379:6379 &
PF_PID=$!

# write/read (bastion 로컬에서 redis-cli)
redis-cli -h 127.0.0.1 set test:foo "hello $(date)"
redis-cli -h 127.0.0.1 get test:foo

# 정리
kill $PF_PID
kubectl exec -n redis redis-node-0 -c redis -- redis-cli del test:foo
```

### 4.4 Failover 시험 (master 죽이기)

```bash
# 📍 bastion에서

# 현재 master의 Pod 찾기
# (단순히 redis-node-0이 master면 0번 죽이기)
kubectl delete pod -n redis redis-node-0

# 30초 기다리고 새 master 확인
sleep 30
kubectl exec -n redis redis-node-1 -c sentinel -- \
  redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

새 master가 1 또는 2번 노드로 바뀌어야 OK.

### 4.5 어떤 앱이 Redis 쓰나

```bash
# 📍 bastion에서

# ticket-app이 Redis env/configmap 가지고 있나
kubectl get deploy ticket-app -n kosa-tickets -o yaml | grep -iE "redis|REDIS"

# 만약 안 쓴다면 → Redis는 설치만 되어있고 미활용 (정상)
```

> ⚠️ ticket-app은 데모 in-memory라 Redis 미사용일 가능성 ↑. 실제 비즈니스 워크로드(예: 세션 저장,
> 대기열) 추가 시 활용.

---

## 5. Harbor 검증

### 5.1 Pod / Ingress 상태

```bash
# 📍 bastion에서
kubectl get pods -n harbor
kubectl get ingress -n harbor
kubectl get cert -n harbor   # cert-manager cert
```

모두 Running / Ready=True / Cert Ready=True 이어야.

### 5.2 Web UI 로그인

```bash
# 📍 bastion (또는 노트북)에서 — pfSense를 DNS로 쓰는 곳이면 어디든
nslookup harbor.kosa.team2 172.16.24.2
# 172.16.23.50 응답

# cert chain 확인
echo | openssl s_client -connect harbor.kosa.team2:443 -servername harbor.kosa.team2 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# 응답
curl -s -o /dev/null -w "%{http_code}\n" https://harbor.kosa.team2/
# 200 또는 302
```

📍 **브라우저 (노트북)**: https://harbor.kosa.team2 → admin / kosa1004.

### 5.3 이미지 push/pull 라운드트립

```bash
# 📍 bastion (또는 Docker가 깔린 호스트) 에서
docker login harbor.kosa.team2 -u admin -p kosa1004

# 작은 이미지로 테스트
docker pull alpine:latest
docker tag alpine:latest harbor.kosa.team2/library/alpine-test:$(date +%s)
docker push harbor.kosa.team2/library/alpine-test:$(date +%s)
docker pull harbor.kosa.team2/library/alpine-test:$(date +%s)

# 정리
docker rmi harbor.kosa.team2/library/alpine-test:$(date +%s)
```

### 5.4 RGW 백엔드 확인

```bash
# 📍 bastion에서 → ceph1로 진입
ssh root@10.10.10.11
```

```bash
# 📍 ceph1 안에서
radosgw-admin bucket stats --bucket=harbor-registry | jq
radosgw-admin user info --uid=harbor | jq .stats
```

기대: bucket size > 0, num_objects > 0.

### 5.5 Trivy 스캔 (옵션)

Harbor UI → library/kosa-tickets → Scan → 결과 확인.

---

## 6. Jenkins / CI-CD 검증

### 6.1 Jenkins 상태

```bash
# 📍 bastion에서
kubectl get pods -n jenkins
kubectl get ingress -n jenkins

curl -s -o /dev/null -w "%{http_code}\n" https://jenkins.kosa.team2
# 200 / 302
```

### 6.2 빌드 트리거 (kosa-tickets-ci)

📍 **브라우저 (노트북)**:

1. https://jenkins.kosa.team2 → kosa-tickets-ci → Build Now
2. Console output 확인 — 3 stage 모두 SUCCESS?

CLI (jenkins-cli.jar):

```bash
# 📍 bastion에서 (kubectl exec로 Jenkins Pod 내부 명령)
kubectl exec -n jenkins jenkins-0 -- \
  java -jar /usr/share/jenkins/cli.jar -s http://localhost:8080 \
  -auth admin:kosa1004 build kosa-tickets-ci -s -v
```

### 6.3 결과 확인

```bash
# 📍 bastion에서

# 새 이미지 Harbor에 push 됐나
BUILD_NUM=$(kubectl exec -n jenkins jenkins-0 -- \
  bash -c "ls -1 /var/jenkins_home/jobs/kosa-tickets-ci/builds/ | grep -E '^[0-9]+$' | sort -n | tail -1")
echo "Latest build: $BUILD_NUM"

# Harbor API로 태그 존재 확인
curl -s -u admin:kosa1004 \
  https://harbor.kosa.team2/api/v2.0/projects/library/repositories/kosa-tickets/artifacts \
  | jq '.[].tags[].name' | grep "\"$BUILD_NUM\""

# GitOps repo에 반영
cd ~/kosa-gitops
git pull
grep "kosa-tickets:$BUILD_NUM" apps/ticket-app/deployment.yaml
```

### 6.4 ArgoCD sync → rollout 확인

```bash
# 📍 bastion에서
argocd app get ticket-app
# Status: Synced + Healthy

kubectl get pods -n kosa-tickets -o wide
# 새 Pod (image tag == BUILD_NUM) 떠있어야

# 실제 응답
curl -s https://ticket.kosa.team2/healthz
# {"status":"ok"}
```

---

## 7. ArgoCD 검증

> **📍 7장의 모든 명령은 bastion에서.**

### 7.1 Application 상태

```bash
# 📍 bastion에서
argocd app list

# 모두 Synced + Healthy인지
argocd app list -o json | jq -r '.[] | "\(.metadata.name)\t\(.status.sync.status)\t\(.status.health.status)"' | column -t
```

OutOfSync 라면:

```bash
argocd app diff <app-name>
argocd app get <app-name> --hard-refresh
argocd app sync <app-name>
```

### 7.2 selfHeal 동작 시험

```bash
# 시험용: ticket-app의 replicas를 수동으로 5로 변경
kubectl scale deploy ticket-app -n kosa-tickets --replicas=5

# 30초 기다림
sleep 30

# 다시 2로 돌아왔으면 selfHeal 정상
kubectl get deploy ticket-app -n kosa-tickets -o jsonpath='{.spec.replicas}'
echo
```

### 7.3 새 Application 추가 시험

```bash
# 임시 nginx app
cat > ~/kosa-gitops/apps/_applications/test-nginx.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: test-nginx, namespace: argocd }
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 18.x.x
    helm: { values: "service:\n  type: ClusterIP\n" }
  destination: { server: https://kubernetes.default.svc, namespace: test-nginx }
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
EOF

cd ~/kosa-gitops
git add . && git commit -m "test: add test-nginx" && git push

# 3분 기다린 후 (또는 root-app refresh)
argocd app get root-app --hard-refresh
sleep 60
argocd app list | grep test-nginx

# 정리
git rm apps/_applications/test-nginx.yaml
git commit -m "test: remove test-nginx" && git push
```

---

## 8. HA / Failover 시험

### ⚠️ 시험 전 주의

실제 트래픽이 흐르고 있는 시간은 피할 것. 일부 트래픽 끊김 발생 가능.

### 8.1 pfSense CARP failover

**준비**: continuous ping 시작

```bash
# 📍 노트북 (외부 환경) 에서
ping -i 0.5 192.168.21.109 | tee pfsense-ping.log
```

**시험**: pfSense Primary 다운

```bash
# 📍 pfSense Primary 콘솔 또는 SSH 후
sudo reboot
```

또는 CARP 강제 demote:

```bash
# 📍 pfSense Primary 쉘 (Option 8)에서
sysctl net.inet.carp.demotion=1
```

**측정**: ping.log에서 끊긴 패킷 수 × 0.5초 = 다운타임. 5초 이내 OK.

복귀 후 BACKUP이 MASTER로 승격됐는지: **📍 pfSense Web UI** → Status → CARP

### 8.2 K8s API VIP failover (Keepalived)

```bash
# 📍 bastion에서 (모든 명령)

# 사전: continuous kubectl
while true; do
  kubectl get nodes >/dev/null 2>&1 && echo "$(date +%T) OK" || echo "$(date +%T) FAIL"
  sleep 1
done | tee $VAL_DIR/api-vip-failover.log &
LOOP_PID=$!

# lb-1 (MASTER) keepalived 중단 (ssh로 명령 전달)
ssh ubuntu@172.16.23.6 "sudo systemctl stop keepalived"

# 30초 관찰
sleep 30

# 복구
ssh ubuntu@172.16.23.6 "sudo systemctl start keepalived"
sleep 5

kill $LOOP_PID
grep -c FAIL $VAL_DIR/api-vip-failover.log
# 0~3 정도면 OK (3초 이내 failover)
```

### 8.3 Edge HAProxy failover

```bash
# 📍 노트북 (외부 환경)에서 — continuous curl
while true; do
  code=$(curl -sk -o /dev/null -w "%{http_code}" https://ticket.kosa.team2/healthz --max-time 2)
  echo "$(date +%T) $code"
  sleep 1
done | tee edge-failover.log &
LOOP_PID=$!
```

```bash
# 📍 bastion에서 — edge-haproxy MASTER reboot
ssh ubuntu@172.16.22.10 "sudo reboot"
```

```bash
# 📍 노트북으로 돌아가서 — 60초 후 LOOP 중단
sleep 60
kill $LOOP_PID

grep -v 200 edge-failover.log | head -5
# 1~5개 실패면 정상 (~5초 failover)
```

### 8.4 K8s CP 노드 다운

```bash
# 📍 bastion에서 (모든 명령)

# cp1 shutdown (1분 후)
ssh ubuntu@172.16.23.10 "sudo shutdown -h +1"

# 30초 후 확인
sleep 90
kubectl get nodes
# k8s-cp1 NotReady

# kubectl 자체는 살아있어야 (cp2/cp3가 처리)
kubectl get pods -n kube-system

# etcd quorum (cp2 또는 cp3에서 명령 — bastion에서 ssh로)
ssh ubuntu@172.16.23.11 "sudo ETCDCTL_API=3 etcdctl \
  --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster"
# 2 healthy, 1 unhealthy

# 복구: cp1 부팅 후 자동으로 join 됨
# 확인: ssh ubuntu@172.16.23.10 "sudo systemctl status kubelet"
```

### 8.5 K8s 워커 다운

```bash
# 📍 bastion에서

# w1 shutdown (1분 후)
ssh ubuntu@172.16.23.20 "sudo shutdown -h +1"

# 5분 후 (eviction default 5m)
sleep 360
kubectl get nodes
# k8s-w1 NotReady

kubectl get pods -A -o wide | grep k8s-w1
# Pod들 Terminating → 다른 노드에 재schedule

# 복구 후 다시 Ready되면 Pod 분산
```

### 8.6 Ceph OSD failover

```bash
# 📍 bastion에서 → ceph1로 진입
ssh root@10.10.10.11
```

```bash
# 📍 ceph1 안에서

# 현재 상태
ceph -s
ceph osd tree

# osd.5 강제 out (데이터 마이그레이션 트리거)
ceph osd out osd.5

# 진행상황
watch -n 2 "ceph -s"
# Ctrl+C로 중단

# 모두 active+clean이면 복구 완료
# osd.5 다시 in
ceph osd in osd.5
```

`time` 으로 recovery 시간 측정 가능.

### 8.7 Harbor RGW failover (현재 SPoF)

ceph1 RGW down 시 Harbor push 불가 (이미 running Pod는 영향 X).

```bash
# 📍 bastion에서 — RGW 중단 명령 전달
ssh root@10.10.10.11 "systemctl stop ceph-radosgw.target"

# Harbor push 시도 → 실패해야 함
docker push harbor.kosa.team2/library/test:1 2>&1 | tail -3

# 복구
ssh root@10.10.10.11 "systemctl start ceph-radosgw.target"
```

→ 이 결과로 "RGW 2대 이상 + LB 추가" 로드맵 우선순위 확정.

### 8.8 Ingress LB failover (MetalLB L2)

```bash
# 📍 bastion에서

# 현재 어느 노드가 172.16.23.50 들고 있나
for w in 172.16.23.20 172.16.23.21 172.16.23.22 172.16.23.23; do
  ssh -o ConnectTimeout=2 ubuntu@$w "ip addr | grep 172.16.23.50" 2>/dev/null \
    && echo "  ^ $w"
done

# 그 노드 cordon (Pod 새로 안 받음) + 일정 시간 후 MetalLB가 다른 노드로 이동
kubectl cordon <해당-노드명>

# (failover 후) 다시 어디인지 확인
for w in 172.16.23.20 172.16.23.21 172.16.23.22 172.16.23.23; do
  ssh -o ConnectTimeout=2 ubuntu@$w "ip addr | grep 172.16.23.50" 2>/dev/null \
    && echo "  ^ $w"
done

# 복구
kubectl uncordon <해당-노드명>
```

---

## 9. 결과 기록 템플릿

각 섹션 끝낼 때 표 채우기. `validation-2026-MM-DD.md`로 git commit 권장.

### 9.1 10G 대역폭

| 경로               | 측정 (Gbps) | 기대     | 합격  |
| ------------------ | ----------- | -------- | ----- |
| ceph1 ↔ ceph2      |             | ~9.4     | ✅/❌ |
| ceph2 ↔ ceph3      |             | ~9.4     |       |
| kosa1 ↔ ceph1      |             | ~9.4     |       |
| w1 (10G) ↔ ceph1   |             | ~9.4     |       |
| Pod ↔ Pod (Calico) |             | ~860Mbps |       |

### 9.2 Ceph IOPS

| 측정        | 4K randwrite IOPS | 4K randread IOPS | 1M seqwrite (MB/s) |
| ----------- | ----------------- | ---------------- | ------------------ |
| RADOS bench |                   |                  |                    |
| RBD bench   |                   |                  |                    |
| Pod fio     |                   |                  |                    |

### 9.3 서비스 동작

| 서비스           | Pod Running | Ingress 응답 | 기능 테스트        | 합격 |
| ---------------- | ----------- | ------------ | ------------------ | ---- |
| Redis (Sentinel) |             | (N/A)        | set/get + failover |      |
| Harbor           |             |              | push/pull          |      |
| Jenkins          |             |              | Build #N SUCCESS   |      |
| ArgoCD           |             |              | selfHeal 동작      |      |
| Grafana          |             |              | dashboard 로드     |      |

### 9.4 HA / Failover

| 시험                | 다운타임 (s) | 자동 복구 | 비고               |
| ------------------- | ------------ | --------- | ------------------ |
| pfSense CARP        |              | ✅/❌     |                    |
| K8s API VIP         |              |           |                    |
| Edge HAProxy        |              |           |                    |
| K8s CP 1대 다운     | (eviction X) |           | etcd quorum OK?    |
| K8s Worker 1대 다운 | ~5min        |           | Pod 재배치?        |
| Ceph OSD 1개 down   |              |           | recovery 시간      |
| Harbor RGW down     | (push 불가)  | ❌ (SPoF) | RGW HA 로드맵 확정 |

---

## 10. 다음 단계

검증 결과를 보고 보강 우선순위 결정:

- 어떤 항목이 ❌ 또는 기대 미달이면 → 해당 챕터의 트러블슈팅 + 12장 인덱스 활용
- IOPS가 너무 낮으면 → Ceph SSD WAL/DB 분리, OSD 수 증가, 10G NIC2 활용 (Cluster Network 분리)
- failover 다운타임이 길면 → keepalived `advert_int`, HAProxy health-check 주기 조정
- Redis 미활용이면 → ticket-app에 session/대기열 기능 추가하고 검증 다시
- RGW SPoF → `ceph orch apply rgw harbor --placement="ceph1,ceph2"` + Service로 LB

### 정기 운영

- **분기 1회**: 이 챕터 전체 수행
- **큰 변경 후**: 영향 받는 섹션만
- **CI 자동화**: Jenkins job으로 일부 (iperf, fio, kubectl get) 매일 — 추후

검증 결과는 `~/validation/YYYYMMDD/` 디렉토리로 archive + git push 권장.

---

## 부록: 검증 자동화 스크립트 (요약본)

📍 **bastion에 저장 + 실행** (`~/bin/validate-onprem-quick.sh`).

```bash
#!/bin/bash
# validate-onprem-quick.sh — 5분 안에 끝나는 헬스 체크
# 📍 실행 위치: bastion
# 📍 호출되는 ssh 명령들이 각 노드에 접근

set +e

VAL_DIR=~/validation/$(date +%Y%m%d-%H%M)
mkdir -p $VAL_DIR
cd $VAL_DIR

echo "=== K8s nodes ===" | tee out.log
kubectl get nodes -o wide 2>&1 | tee -a out.log

echo "=== Pods not Running ===" | tee -a out.log
kubectl get pods -A 2>&1 | grep -vE "Running|Completed|NAMESPACE" | tee -a out.log

echo "=== ArgoCD apps ===" | tee -a out.log
argocd app list 2>&1 | tee -a out.log

echo "=== Ceph health (via ssh to ceph1) ===" | tee -a out.log
ssh root@10.10.10.11 "ceph -s" 2>&1 | tee -a out.log

echo "=== API VIP (via ssh to lb-1/lb-2) ===" | tee -a out.log
for ip in 172.16.23.6 172.16.23.7; do
  ssh -o ConnectTimeout=2 ubuntu@$ip "ip addr | grep 172.16.23.5"
done 2>&1 | tee -a out.log

echo "=== Endpoints (HTTPS, from bastion) ===" | tee -a out.log
for url in harbor jenkins ticket grafana argocd; do
  code=$(curl -sk -o /dev/null -w "%{http_code}" \
    https://$url.kosa.team2 --max-time 5)
  echo "$url.kosa.team2 → $code"
done 2>&1 | tee -a out.log

echo "=== Cert 만료 (bastion ~/pki) ==="  | tee -a out.log
openssl x509 -in ~/pki/ca.crt -noout -enddate 2>&1 | tee -a out.log
openssl x509 -in ~/pki/wildcard.crt -noout -enddate 2>&1 | tee -a out.log

echo "=== 완료: $VAL_DIR/out.log ==="
```

이걸 매일 cron에 등록 + Slack 알림 보내면 일상 모니터링.
