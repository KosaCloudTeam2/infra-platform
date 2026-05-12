# Ansible — K8s 부트스트랩

> Terraform이 만든 VM 7대를 K8s 클러스터로 변환.
> 실행 순서: 00 → 10 → 20 → 30 → 40 (또는 site.yml로 한 번에)

## 무엇을 하는가

| 플레이북 | 역할 | 대상 |
|---|---|---|
| `00-bootstrap.yml` | hostname, swap off, NTP, 기본 패키지 | 전체 VM |
| `10-k8s-prepare.yml` | containerd 설치, 커널 모듈, sysctl | k8s_cluster |
| `20-k8s-install.yml` | kubeadm/kubelet/kubectl 설치 (apt hold) | k8s_cluster |
| `30-k8s-init.yml` | kubeadm init + 다른 CP/Worker join | k8s_cluster |
| `40-k8s-addons.yml` | Calico, MetalLB, Metrics Server 설치 | primary CP |
| `site.yml` | 위 5개 순차 실행 | - |

## 파일 구조

```
ansible/
├── ansible.cfg                       # 프로젝트 설정 (SSH 옵션 등)
├── requirements.yml                  # 필요 collections
├── inventory/
│   ├── hosts.yml                     # Terraform output에서 자동 생성됨
│   ├── hosts.yml.example             # 수동 작성 예제
│   └── group_vars/
│       ├── all.yml                   # K8s 버전, CIDR 등 공통
│       ├── k8s_control_plane.yml     # CP 전용 변수
│       └── k8s_workers.yml           # 워커 전용
└── playbooks/
    ├── site.yml                      # 마스터 (모든 단계 import)
    ├── 00-bootstrap.yml
    ├── 10-k8s-prepare.yml
    ├── 20-k8s-install.yml
    ├── 30-k8s-init.yml
    └── 40-k8s-addons.yml
```

## 사전 준비

- [ ] Terraform으로 VM 7대 생성 완료
- [ ] `terraform output -raw ansible_inventory > inventory/hosts.yml` 실행
- [ ] 로컬 또는 Bastion에 Ansible 설치 (`pip install ansible` 또는 `apt install ansible`)
- [ ] Collection 설치: `ansible-galaxy collection install -r requirements.yml`

## 사용법

### 1) 연결 테스트

```bash
cd ansible
ansible all -m ping
```

기대: 모든 호스트 `SUCCESS`.

### 2) 한 번에 전체 실행

```bash
ansible-playbook playbooks/site.yml
```

소요 시간: 약 30분~1시간.

### 3) 단계별 실행 (학습/디버깅)

```bash
# OS 기본 설정
ansible-playbook playbooks/00-bootstrap.yml

# K8s 사전 준비 (containerd 등)
ansible-playbook playbooks/10-k8s-prepare.yml

# K8s 패키지 설치
ansible-playbook playbooks/20-k8s-install.yml

# 클러스터 초기화 + 노드 join
ansible-playbook playbooks/30-k8s-init.yml

# CNI + 애드온
ansible-playbook playbooks/40-k8s-addons.yml
```

### 4) 멱등성 검증

같은 플레이북 두 번 실행해서 두 번째는 `changed=0` 인지 확인:

```bash
ansible-playbook playbooks/00-bootstrap.yml
# 두 번째 실행
ansible-playbook playbooks/00-bootstrap.yml
# PLAY RECAP에 changed=0 이면 멱등성 OK
```

### 5) 검증 (K8s 클러스터)

```bash
# Bastion 또는 k8s-cp1에 SSH 후
kubectl get nodes
# 6대 모두 Ready 상태여야 함

kubectl get pods -A
# kube-system, calico-system, metallb-system 모두 Running

kubectl top nodes  # Metrics Server 작동 확인
```

## 핵심 결정 사항

### CNI: Calico
- Tigera Operator 방식 (Day-2 운영 편함)
- Pod CIDR: 10.244.0.0/16
- VXLAN encapsulation

### 컨테이너 런타임: containerd
- K8s 1.24+ 표준
- Docker는 빌드용으로만 사용

### LoadBalancer: MetalLB
- Layer 2 모드 (BGP 안 씀)
- IP 풀: 172.16.22.50 ~ 172.16.22.100 (VLAN 20 DMZ)

### Metrics Server
- HPA 작동 위해 필수
- `--kubelet-insecure-tls` (자체 서명 환경)

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| `Permission denied (publickey)` | SSH 키 경로 확인 (`ansible.cfg`의 `private_key_file`) |
| `kubeadm init` 실패 — swap | `swapon -s` 비어있어야 함. 00-bootstrap 다시 |
| `kubeadm init` 실패 — br_netfilter | `lsmod \| grep br_netfilter`, 10-k8s-prepare 다시 |
| join 실패 — token 만료 | 24시간 후엔 토큰 만료. 새 토큰: `kubeadm token create --print-join-command` |
| Calico 노드 NotReady | Tigera Operator 로그: `kubectl logs -n tigera-operator -l name=tigera-operator` |
| Metrics Server "X509 certificate signed by unknown authority" | `--kubelet-insecure-tls` 옵션 추가 확인 |

## 변경 / 재설치

### 클러스터 완전 리셋 (재구축)

```bash
# 위험! K8s 전부 삭제됨
ansible all -m shell -a "sudo kubeadm reset --force" --become
ansible all -m shell -a "sudo rm -rf /etc/cni/net.d" --become
ansible all -m shell -a "sudo rm -rf $HOME/.kube" --become

# 다시 실행
ansible-playbook playbooks/site.yml
```

### 노드 추가 (예: 워커 1대 더)

1. `terraform/onprem/variables.tf` 의 `worker_nodes` 리스트에 추가
2. `terraform apply`
3. `scripts/generate-inventory.sh`
4. `ansible-playbook playbooks/00-bootstrap.yml --limit new_node`
5. `ansible-playbook playbooks/10-k8s-prepare.yml --limit new_node`
6. `ansible-playbook playbooks/20-k8s-install.yml --limit new_node`
7. `kubeadm token create --print-join-command` (CP에서)
8. 새 노드에서 그 명령 실행

## 다음 단계

K8s 클러스터 6/6 Ready 상태 되면:
- ArgoCD 부트스트랩 (Helm)
- Ceph CSI 연결 (RBD StorageClass)
- 앱 매니페스트 생성
- 자세한 건 `Onprem_Build_Guide.md` 참고
