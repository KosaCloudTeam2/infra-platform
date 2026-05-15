# Architecture Decisions

아키텍처 의사결정(Decision Log) 문서 목록.

## 네이밍 규칙

- 파일명: `DR-NN-<1~3단어-kebab-case>.md`
- 예: `DR-01-k6-vs-jmeter.md`
- 번호 중복은 허용하되, 발견 시 수동으로 정정함.

## 상태 규칙

- Proposed: 검토 중
- Accepted: 채택
- Deprecated: 사용 중단 권고
- Rejected: 기각
- Superseded: 후속 DR로 대체됨

## 작성 템플릿

- 신규 DR 작성 시 [DR-TEMPLATE](./DR-TEMPLATE.md)를 복사해서 시작함.

## Decision 목록

| ID    | Status   | 제목                                    | 파일                                          |
| :---- | :------- | :-------------------------------------- | :-------------------------------------------- |
| DR-01 | Accepted | 부하 테스트 도구로 k6 채택(JMeter 대비) | [DR-01-k6-vs-jmeter](./DR-01-k6-vs-jmeter.md) |
