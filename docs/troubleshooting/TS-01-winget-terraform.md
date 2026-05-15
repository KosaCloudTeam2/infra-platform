# TS-01 winget-terraform

- Status: **Resolved**
- Date: 2026-05-15

## 증상

- `winget` 또는 `terraform` 명령이 인식되지 않음.

## 점검

```powershell
winver
where.exe winget
where.exe terraform
```

## 해결 절차

1. App Installer 설치 파일 다운로드

```powershell
cd C:\Users\Samuel\Desktop\infra-platform
Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile winget.msixbundle
```

2. PowerShell 5.1에서 설치

```powershell
powershell
cd C:\Users\Samuel\Desktop\infra-platform
Add-AppxPackage -Path .\winget.msixbundle
```

3. PATH 확인/추가

```powershell
dir "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$env:LOCALAPPDATA\Microsoft\WindowsApps",
  "User"
)
```

4. 새 터미널에서 재검증

```powershell
winget --version
terraform version
```

## 주의

- `winget.msixbundle`은 임시 파일이므로 커밋하지 않음.
