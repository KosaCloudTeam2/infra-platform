# DR-01 k6-vs-jmeter

- Status: **Accepted**
- Date: 2026-05-15
- Owner: Team Infra

## Context

MVP(13+3 일정)에서 발표 시연용 부하 테스트는 AWS burst 경로(ALB/ASG) 검증을 짧고 반복 가능하게
수행해야 함. 현재 문서에는 k6/JMeter가 모두 후보로 표기되어 있어 도구 단일화가 필요함.

## Decision

부하 테스트 기본 도구를 **k6**로 채택함.

## Options

### Option A. k6

- 장점
  - JavaScript 스크립트 기반으로 Git 저장소/코드리뷰에 적합
  - threshold로 p95, 오류율을 CI 게이트로 바로 활용 가능
  - GitHub Actions 연동이 단순함
- 단점
  - JMeter GUI 중심 워크플로에 익숙한 인원에게 초기 학습 필요

### Option B. JMeter

- 장점
  - GUI 기반 시나리오 작성이 쉬움
  - 레거시/기존 JMX 자산이 있으면 재사용 가능
- 단점
  - 본 프로젝트 기준(짧은 일정, 자동화 중심)에서 스크립트/리포트 운영이 상대적으로 무거움

## Consequences

- `runbooks/monitoring.md`, `presentation/qna.md`에서 기본 도구를 k6 기준으로 정렬함.
- JMeter는 대안(비교/보조)으로 유지함.
- 부하 테스트 시간 제한 원칙은 기존 결정(비용 통제)대로 유지함.

## Validation

- `uv run mkdocs build`
