# Tool Troubleshooting

로컬 도구 설치와 Git Hook 문제 해결 절차

---

## 1. Windows에서 winget 또는 Terraform이 인식되지 않을 때

Windows 10 환경에서 `winget`이 인식되지 않으면 먼저 OS 버전을 확인함.

```powershell
winver
```

Windows 10 19045 계열처럼 `winget` 사용 가능 버전인데도 명령이 없으면 App Installer를 직접 설치함.

```powershell
cd C:\Users\Samuel\Desktop\infra-platform
Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile winget.msixbundle
```

PowerShell 7에서 `Appx` 모듈 오류가 나면 Windows PowerShell 5.1을 열고 설치함.

```powershell
powershell
cd C:\Users\Samuel\Desktop\infra-platform
Add-AppxPackage -Path .\winget.msixbundle
```

설치 후 `winget.exe`가 있는지 확인함.

```powershell
dir "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
```

명령이 계속 인식되지 않으면 사용자 PATH에 WindowsApps 경로를 추가함.

```powershell
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$env:LOCALAPPDATA\Microsoft\WindowsApps",
  "User"
)
```

터미널을 완전히 다시 열고 확인함.

```powershell
winget --version
terraform version
```

주의:

- `winget.msixbundle`은 설치용 임시 파일이므로 커밋하지 않음.
- PATH를 바꾼 직후에는 기존 터미널에 반영되지 않을 수 있으므로 새 터미널에서 검증함.

## 2. Terraform hook에서 실행 파일을 찾지 못할 때

Terraform hook에서 `Executable terraform not found`가 나오면 터미널을 다시 열어 PATH 반영 여부를
확인함.

```powershell
where.exe terraform
terraform version
```

## 3. Git Hook 문제 해결

Husky가 동작하지 않으면 다음 순서로 복구함.

```powershell
pnpm install
git config core.hooksPath .husky
```

pre-commit 환경이 깨졌다면:

```powershell
uv sync
uv run pre-commit clean
uv run pre-commit run --all-files
```

## 4. Ruff 또는 pip-audit 실행 실패

`ruff` 또는 `pip-audit` 명령을 찾지 못하면 dev 그룹 의존성이 설치되지 않은 상태일 수 있음.

```powershell
uv sync --group dev
uv run ruff --version
uv run pip-audit --version
```

`pip-audit`는 Python 의존성 취약점 데이터와 lock 파일을 확인하므로 네트워크 상태에 따라 느릴 수
있음. 캐시 문제로 실패하면 캐시를 지우고 다시 실행함.

```powershell
Remove-Item -Recurse -Force .audit_cache
uv run pre-commit run pip-audit --hook-stage pre-push --all-files
```

현재 저장소에 Python 파일이 없으면 Ruff hook은 `no files to check`로 skip되는 것이 정상임.
