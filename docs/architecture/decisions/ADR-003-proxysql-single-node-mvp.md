# ADR-003: ProxySQL 1대 MVP와 이중화 확장 경로

## 상태

Accepted

## 날짜

2026-05-03

## 배경

ProxySQL은 앱의 DB 접근을 단일화하고 PXC backend 라우팅을 담당함. 운영 관점에서는 ProxySQL도
이중화해야 하지만, 처음부터 2대 + Internal NLB를 필수로 잡으면 설정 동기화, Health Check, 단일
엔드포인트 검증까지 작업량이 커짐.

## 결정

MVP는 ProxySQL 1대로 시작함. 단, 이 구조는 단일 장애점(SPoF)임을 문서와 발표에서 명시함. 일정 여유가
있으면 `proxysql_count = 2`, `enable_proxysql_internal_nlb = true`로 Internal NLB 기반 이중화로
전환함.

## 대안

- 처음부터 ProxySQL 2대 + Internal NLB 필수 구성
- Keepalived 기반 VIP
- 앱에서 여러 ProxySQL endpoint 직접 관리

## 영향

장점:

- Day 8까지 앱이 ProxySQL을 통해 PXC에 접속하는 핵심 흐름을 우선 완성 가능
- Terraform 변수로 이중화 확장 경로를 남길 수 있음
- 발표에서 MVP 한계와 개선안을 명확히 설명 가능

감수할 점:

- ProxySQL EC2 장애 시 앱 DB 접속이 중단됨
- 운영 권장 구성은 아니므로 한계 설명이 필요함
- 2대로 확장해도 설정 동기화와 backend 상태 검증은 별도 과제임

## 관련 문서

- [Architecture](../../01_architecture.md)
- [Structure Review](../../15_structure_review.md)
- [Database Storage Runbook](../../runbooks/database_storage.md)
