# TS-02 Terraform hook에서 `Executable terraform not found`

## 증상

- pre-commit/hook 실행 시 `Executable terraform not found` 오류 발생.

## 점검

```powershell
where.exe terraform
terraform version
```

## 해결 절차

1. PATH 반영을 위해 터미널 재시작
2. 재확인

```powershell
where.exe terraform
terraform version
```

3. hook 재실행

```powershell
uv run pre-commit run --all-files
```

## 주의

- 설치 직후 기존 터미널에는 PATH가 반영되지 않을 수 있음.
