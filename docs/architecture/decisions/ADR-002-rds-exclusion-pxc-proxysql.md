# ADR-002: RDS 제외와 PXC/ProxySQL 채택

## 상태

Accepted

## 날짜

2026-05-03

## 배경

AWS RDS는 안정적이고 빠르게 구성할 수 있지만, 이번 프로젝트는 클라우드 인프라 구축과 운영 경험을
보여주는 것이 목표임. DB 장애 대응, 백업/복구, 프록시 기반 접근 제어를 직접 시연하려면 관리형 DB보다
직접 운영 DB 구성이 더 적합함.

## 결정

AWS RDS를 제외하고 EC2 기반 Percona XtraDB Cluster(PXC) 3노드와 ProxySQL을 사용함.

## 대안

- Amazon RDS for MySQL
- Amazon Aurora MySQL
- 단일 EC2 MySQL
- 온프레미스 Proxmox VM 기반 DB

## 영향

장점:

- RDS 없이 DB 클러스터, 백업, 장애 대응을 직접 설명 가능
- ProxySQL을 통해 앱이 DB 노드에 직접 접근하지 않는 구조를 만들 수 있음
- Percona XtraBackup과 Ceph RGW 백업 시연이 자연스럽게 연결됨

감수할 점:

- PXC 설치, 운영, 장애 복구 복잡도가 높음
- EC2 DB 운영은 RDS보다 패치, 백업, 모니터링 책임이 큼
- 13일 일정에서 자동화 범위는 제한될 수 있음

## 관련 문서

- [Architecture](../../01_architecture.md)
- [DB Storage Build-up](../build-up/02_db_storage.md)
- [Database Storage Runbook](../../runbooks/database_storage.md)
