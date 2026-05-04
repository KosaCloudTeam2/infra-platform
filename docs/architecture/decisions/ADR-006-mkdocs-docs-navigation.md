# ADR-006: MkDocs navigation 기반 문서 사이트

## 상태

Accepted

## 날짜

2026-05-03

## 배경

`docs/` 바로 아래에 문서가 많아지고 있어 웹 문서 형태의 탐색성이 필요함. 하지만 현재 `00~21` 문서는
처음 읽는 순서를 표현하고 있으므로, 물리적으로 폴더를 크게 이동하면 링크 수정과 혼란이 커질 수 있음.

## 결정

문서 파일은 현재 구조를 유지하고, `docs/index.md`와 `mkdocs.yml`의 `nav`를 루트 문서 번호 흐름에 맞춰
제공함. 영역별 섹션은 유지하되 번호 순서를 깨지 않음. MkDocs Material을 사용하고 로컬 미리보기는
`127.0.0.1:8010` 포트를 사용함.

## 대안

- `docs/management`, `docs/engineering`, `docs/operations` 등으로 대규모 재구성
- MkDocs 없이 Markdown 파일만 유지
- 발표 자료만 Marp로 관리

## 영향

장점:

- 문서 이동 없이 탐색성을 높일 수 있음
- MkDocs navigation으로 파일명 번호 흐름과 역할별 문서를 함께 표현 가능
- 발표 자료는 기존 Marp 흐름을 유지할 수 있음

감수할 점:

- MkDocs 관련 dev 의존성이 추가됨
- navigation을 문서 추가 시 함께 갱신해야 함
- 정적 사이트 빌드 산출물 `site/`는 커밋하지 않도록 관리해야 함

## 관련 문서

- [Docs Index](../../index.md)
- [MkDocs Guide](../../20_mkdocs_guide.md)
- [Structure Review](../../15_structure_review.md)
