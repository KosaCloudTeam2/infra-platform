# Ansible Optional Area

EC2 기반 DB, Bastion, 자체 운영 Prometheus/Grafana 같은 선택 확장을 구성할 때 사용하는 영역

## 현재 MVP

ECS Fargate는 서버를 직접 관리하지 않으므로 Ansible이 필수는 아님.

## 선택 확장 예시

- EC2 기반 MariaDB/ProxySQL 설치
- Bastion 또는 관리 VM 보안 하드닝
- CloudWatch Agent 설치
- Prometheus Node Exporter 설치
