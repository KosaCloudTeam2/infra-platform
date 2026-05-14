# Troubleshooting Index

트러블슈팅 항목을 표 형태로 빠르게 확인하는 인덱스 문서.

---

## 이슈 요약표

| ID    | 증상                                           | 빠른 점검                               | 상세 가이드                                 |
| :---- | :--------------------------------------------- | :-------------------------------------- | :------------------------------------------ |
| TS-01 | Windows에서 `winget`/`terraform` 명령 미인식   | `winget --version`, `terraform version` | [TS-01](./issues/TS-01-winget-terraform.md) |
| TS-02 | Git hook에서 `terraform` 실행 파일을 찾지 못함 | `where.exe terraform`                   | [TS-02](./issues/TS-02-terraform-hook.md)   |
| TS-03 | Husky/pre-commit 동작 불안정                   | `git config core.hooksPath .husky`      | [TS-03](./issues/TS-03-husky-precommit.md)  |
| TS-04 | `ruff`, `pip-audit` 실행 실패                  | `uv sync --group dev`                   | [TS-04](./issues/TS-04-ruff-pipaudit.md)    |

---

## 운영 규칙

- 신규 이슈는 `docs/troubleshooting/issues/TS-XX-*.md` 파일로 추가하고, 본 인덱스 표를 동기화함.
- 검증은 `uv run mkdocs build` 기준으로 수행함.
