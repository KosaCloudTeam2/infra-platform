# Quality Checks

문서 구조 개편 이후 기본 검증 기준은 아래 1개로 고정함.

## 필수 검증

```powershell
uv run mkdocs build
```

## 운영 원칙

- 위 명령이 통과하면 문서 변경 검증을 완료한 것으로 판단함.
- 링크 체크 전용 도구, pre-commit, format check는 현재 프로젝트 필수 게이트로 사용하지 않음.
- 검증 실패 시 우선 `mkdocs.yml` nav 경로, 문서 상대 링크, Mermaid 블록 문법을 확인함.

## 변경 보고 기준

- 주요 문서 구조 변경 시 `docs/15_structure_review.md`와 `docs/16_change_log.md`를 함께 갱신함.
- 검증을 실행하지 못한 경우 사유를 변경 보고에 명시함.
