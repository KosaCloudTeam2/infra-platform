# Environment Setup Guide (Demo Version)

> **주의**: 본 문서는 프로젝트의 **데모(Demo) 버전** 또는 **임시 구조**를 설명하고 있습니다. 향후
> 전체적인 프로젝트 구조가 변경될 예정이므로 참고하시기 바랍니다.

13일 구축 + 3일 발표 준비 기간 동안 팀원 환경 차이로 시간을 잃지 않기 위한 초기 환경 설정 기준

---

## 1. 목적

이 문서는 프로젝트에 처음 참여하는 팀원이 로컬 환경을 빠르게 맞추기 위한 최소 절차만 다룸.

상세 절차는 아래 문서를 따름.

| 문서                                                              | 내용                                      |
| :---------------------------------------------------------------- | :---------------------------------------- |
| [Quality Checks](./project_info/18_quality_checks.md)             | Prettier, pre-commit, Terraform 검증 절차 |
| [Tool Troubleshooting](./project_info/19_tool_troubleshooting.md) | winget, Terraform, Git Hook 문제 해결     |
| [MkDocs Guide](./03_mkdocs_guide.md)                              | MkDocs 설치와 로컬 문서 사이트 실행       |

## 2. 공통 필수 도구

모든 팀원은 Day 1에 아래 도구 설치와 버전 확인을 완료함.

| 도구        | 용도                                          | 확인 명령           |
| :---------- | :-------------------------------------------- | :------------------ |
| Git         | 형상 관리                                     | `git --version`     |
| Node.js LTS | Prettier, Marp, Husky 실행                    | `node --version`    |
| pnpm        | Node 패키지 관리                              | `pnpm --version`    |
| Python/uv   | pre-commit, MkDocs, Ruff, pip-audit 실행 환경 | `uv --version`      |
| AWS CLI v2  | AWS 리소스 확인                               | `aws --version`     |
| Terraform   | IaC 실행                                      | `terraform version` |

## 3. 최초 설치

### 3.1 Windows

Windows는 `cmd` 또는 PowerShell 기준으로 진행함.

#### 3.1.1 Node.js와 pnpm

`cmd`에서 `nvm-windows` 설치:

```cmd
winget install CoreyButler.NVMforWindows
```

설치 후 기존 `cmd`를 닫고 새 `cmd`를 열어 확인:

```cmd
nvm version
```

Node.js LTS와 pnpm 설치:

```cmd
nvm install lts
nvm use lts
npm install -g pnpm
```

설치 확인:

```cmd
node --version
npm --version
pnpm --version
```

#### 3.1.2 uv

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

설치 후 새 터미널에서 확인:

```powershell
uv --version
```

#### 3.1.3 Terraform

```powershell
winget install Hashicorp.Terraform
```

설치 후 새 터미널에서 확인:

```powershell
terraform version
```

### 3.2 macOS

macOS는 기본 shell이 `zsh`인 환경 기준으로 진행함.

#### 3.2.1 Node.js와 pnpm

`nvm` 설치:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
```

설치 후 새 터미널을 열거나 shell 설정을 다시 불러옴.

```bash
source ~/.zshrc
nvm --version
```

Node.js LTS와 pnpm 설치:

```bash
nvm install --lts
nvm use --lts
npm install -g pnpm
```

설치 확인:

```bash
node --version
npm --version
pnpm --version
```

#### 3.2.2 uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

설치 후 새 터미널을 열거나 shell 설정을 다시 불러옴.

```bash
source ~/.zshrc
uv --version
```

#### 3.2.3 Terraform

Homebrew 사용 권장:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

설치 확인:

```bash
terraform version
```

## 4. 저장소 초기화

```powershell
git clone <repository_url>
cd infra-platform
pnpm install
uv sync --group dev
```

`pnpm install`은 Husky Git Hook을 활성화함. `uv sync --group dev`는 pre-commit, MkDocs, Ruff,
pip-audit 같은 개발/검증 도구를 설치함. 이후 커밋/푸시 시 품질 검사가 자동 실행됨.

## 5. 온보딩 확인

```powershell
git status
pnpm --version
uv --version
uv run ruff --version
uv run pip-audit --version
terraform version
aws --version
```

Docker Desktop은 Windows 로컬 필수 설치 대상이 아님. 앱 이미지는 GitHub Actions에서 빌드하는 것을
기본 경로로 두고, 로컬에서 Dockerfile을 직접 검증해야 하는 팀원만 설치함.

AWS 인증은 Terraform `plan` 또는 실제 리소스 확인을 시작하기 전 설정함.

```powershell
aws sts get-caller-identity
```

인증 전에도 가능한 검증은 [Project Info: Quality Checks](./project_info/18_quality_checks.md)를
따름.

## 6. 팀 운영 규칙

- Day 1에 전원 환경 구축 완료
- Day 14부터 신규 기능 추가 금지
- `.env`, `*.tfstate`, 개인키, 인증서, AWS Access Key 커밋 금지
