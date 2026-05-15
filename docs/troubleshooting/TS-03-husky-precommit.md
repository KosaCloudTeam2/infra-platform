# TS-03 husky-precommit

- Status: **Resolved**
- Date: 2026-05-15

## 증상

- Husky hook 미동작
- pre-commit 환경 깨짐

## 해결 절차

1. Husky 재설정

```powershell
pnpm install
git config core.hooksPath .husky
```

2. pre-commit 환경 복구

```powershell
uv sync
uv run pre-commit clean
uv run pre-commit run --all-files
```

## 검증

```powershell
git config core.hooksPath
uv run pre-commit run --all-files
```
