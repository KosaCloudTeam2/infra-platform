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

## 실행 예시

```bash
ansible-playbook -i infra/ansible/inventories/onprem-bastion.ini infra/ansible/playbooks/verify.yml
```

## 주의

- `edge-haproxy.yml`: `/etc/haproxy/haproxy.cfg` 변경 대상
- `bootstrap-k8s-node.yml`: swap, kernel module, sysctl 변경 대상
- 운영 반영 전 `--check --diff` 우선 실행
