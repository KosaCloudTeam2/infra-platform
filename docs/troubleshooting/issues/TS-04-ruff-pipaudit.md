# TS-04 `ruff`/`pip-audit` 실행 실패

## 증상

- `ruff` 또는 `pip-audit` 명령을 찾지 못함
- `pip-audit` 실행 실패

## 해결 절차

1. dev 의존성 재설치

```powershell
uv sync --group dev
```

2. 버전 확인

```powershell
uv run ruff --version
uv run pip-audit --version
```

3. `pip-audit` 캐시 정리 후 재실행

```powershell
Remove-Item -Recurse -Force .audit_cache
uv run pre-commit run pip-audit --hook-stage pre-push --all-files
```

## 참고

- Python 파일이 없으면 Ruff는 `no files to check`로 skip될 수 있음.
