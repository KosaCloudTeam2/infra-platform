# Ansible Optional Area

EC2 기반 DB, Bastion, 자체 운영 Prometheus/Grafana 같은 선택 확장을 구성할 때 사용하는 영역

## 현재 MVP

Terraform은 AWS burst app EC2와 DB용 EC2 골격까지만 만들고, PXC/ProxySQL 설치는 Runbook 또는 선택
Ansible로 처리함. Day 14 발표 가능 상태가 우선이므로 처음부터 모든 설치를 Ansible 자동화하지 않음.

## 선택 확장 예시

- EC2 기반 PXC/ProxySQL 설치
- Bastion 또는 관리 VM 보안 하드닝
- CloudWatch Agent 설치
- Prometheus Node Exporter 설치
