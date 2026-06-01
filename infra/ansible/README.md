# Ansible Area

온프레미스 bastion, Kubernetes node, edge HAProxy 운영 자동화 영역.

## 현재 기준

- 실행 위치 우선순위: bastion
- bastion inventory: `inventories/onprem-bastion.ini`
- operator inventory: `inventories/onprem-operator.ini`
- 기본 검증: `playbooks/verify.yml`
- K8s node 기준 설정: `playbooks/bootstrap-k8s-node.yml`
- edge HAProxy 기준 설정: `playbooks/edge-haproxy.yml`
- 비밀값 원칙: private key, vault 파일, 비밀번호 저장소 저장 금지

## 파일 요약

- `inventories/onprem-bastion.ini`: bastion 내부 실행용 inventory, bastion local connection 기준
- `inventories/onprem-operator.ini`: 작업자 PC 실행용 inventory, bastion ProxyJump 경유 기준
- `inventories/group_vars/all.yml`: Ubuntu, Kubernetes, containerd, MetalLB, StorageClass 기준값
- `inventories/group_vars/edge.yml`: HAProxy domain, backend ingress, stats 설정값
- `playbooks/verify.yml`: bastion Kubernetes API, K8s node runtime, edge HAProxy 검증
- `playbooks/bootstrap-k8s-node.yml`: K8s node OS baseline 적용
- `playbooks/edge-haproxy.yml`: edge HAProxy 설정 적용
- `roles/common`: 공통 package, qemu guest agent, chrony 설정
- `roles/kubernetes_node`: swap 비활성화, kernel module, sysctl, kubelet/containerd 설정
- `roles/edge_haproxy`: HAProxy 설치, TLS 인증서 확인, config render, service enable

## 실행 흐름

- 1단계: bastion 접속
- 2단계: inventory 선택
- 3단계: `verify.yml` 상태 확인
- 4단계: 변경 playbook `--check --diff` 실행
- 5단계: 담당자 1명만 실제 반영

## 실행 예시

```bash
ansible-playbook -i infra/ansible/inventories/onprem-bastion.ini infra/ansible/playbooks/verify.yml
```

## 주의

- `edge-haproxy.yml`: `/etc/haproxy/haproxy.cfg` 변경 대상
- `bootstrap-k8s-node.yml`: swap, kernel module, sysctl 변경 대상
- 운영 반영 전 `--check --diff` 우선 실행
