# Quality Checks

문서, 코드, Terraform 변경 후 수행할 품질 검증 절차

---

## 1. Prettier

AI로 생성한 Markdown/YAML/JSON/JavaScript는 줄바꿈과 들여쓰기가 흔들리기 쉬우므로 Prettier를 팀
표준으로 고정함.

```powershell
pnpm run format
pnpm run format:check
```

포맷 대상:

- `*.md`
- `*.yml`, `*.yaml`
- `*.json`
- `*.js`

제외 대상:

- `node_modules/`
- `.terraform/`
- Terraform state
- PDF
- lock 파일
- `.ini`
- `.env`

Prettier는 commit 단계에서 반드시 실행함. 팀원마다 에디터 저장 시 포맷 설정이 달라도, 커밋되는
문서와 JavaScript 파일의 스타일은 저장소 기준으로 맞춰야 하기 때문임.

단, Prettier는 모든 파일에 적용하지 않음. Terraform은 `terraform fmt`, Python은 Ruff, Shell script는
ShellCheck와 별도 포맷터가 더 적합함.

## 2. Python 품질 기준

Python은 **Ruff format + Ruff check**를 팀 표준으로 사용함.

Black + Ruff check도 좋은 조합이지만, 이 저장소는 Python 코드가 많지 않고 팀 온보딩이 중요하므로
도구를 하나로 줄이는 Ruff 기준이 더 적합함.

| 선택지                   | 역할                      | 권장 상황                                            |
| :----------------------- | :------------------------ | :--------------------------------------------------- |
| Ruff format + Ruff check | 포맷과 lint를 빠르게 수행 | 이 프로젝트 기본 선택                                |
| Black + Ruff check       | 포맷은 Black, lint는 Ruff | Python 코드가 많아지고 Black 호환성을 강하게 원할 때 |

커밋 단계에서는 staged Python 파일만 검사함.

```powershell
uv run ruff format --check .
uv run ruff check .
```

자동 수정이 필요할 때:

```powershell
uv run ruff format .
uv run ruff check --fix .
```

Python 의존성 보안 검사는 `pip-audit`로 수행함. 이 검사는 commit 단계가 아니라 pre-push 또는 manual
단계에 둠. 취약점 DB와 lock 파일 분석은 커밋마다 실행하기엔 무거울 수 있기 때문임.

```powershell
uv run pre-commit run pip-audit --hook-stage pre-push --all-files
```

## 3. pre-commit

커밋 단계에서는 커밋에 포함되는 staged 파일을 기준으로 빠른 검사를 수행함.

- Gitleaks 시크릿 스캔
- 개인키 탐지
- 대용량 파일 차단
- YAML/JSON 문법 검사
- Markdown/YAML/JSON/JavaScript Prettier 포맷
- Ruff Python format/lint
- ShellCheck
- Terraform fmt

수동 실행:

```powershell
uv run pre-commit run --all-files
```

첫 커밋 전처럼 파일이 아직 Git에 추적되지 않는 상태라면 `--all-files`가 검사 대상을 찾지 못할 수
있음. 이때는 파일 목록을 직접 넘겨 검사함.

```powershell
$files = rg --files
uv run pre-commit run --files $files
```

푸시 단계에서는 전체 파일 기준으로 보안 검사를 다시 수행함.

```powershell
uv run pre-commit run --hook-stage pre-push --all-files
```

커밋 단계와 push/CI 단계의 권장 분리는 다음과 같음.

| 단계              | 목적                                   | 권장 검사                                                                             |
| :---------------- | :------------------------------------- | :------------------------------------------------------------------------------------ |
| pre-commit        | 커밋 직전 빠른 실수 차단               | secret, private key, large file, YAML/JSON, Prettier, Ruff, ShellCheck, Terraform fmt |
| pre-push          | 원격 저장소 반영 전 보안/의존성 확인   | Gitleaks, private key, large file, `pnpm audit`, `pip-audit`                          |
| CI 또는 수동 검증 | 시간이 걸리거나 AWS 인증이 필요한 검증 | Terraform validate/plan, MkDocs build, 전체 품질 검사                                 |

Prettier는 commit 단계에 유지함. 다만 `git commit` 시에는 전체 저장소가 아니라 staged 파일 중
Markdown/YAML/JSON/JavaScript 파일만 검사됨.

## 4. Terraform 검증

Terraform 검증은 AWS 인증이 없어도 가능한 단계와 AWS 인증 이후에만 가능한 단계로 나눔.

### 4.1 AWS 인증 전

아래 검증은 AWS 계정 인증 없이 로컬 도구와 코드 구조만 확인함.

```powershell
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
```

통과 기준:

- Terraform 문법과 provider 설정이 유효함
- Terraform state, `.env`, 개인키, 인증서 파일이 Git 추적 대상에 없음
- DB 관련 포트가 코드상 인터넷 전체에 열리지 않음

### 4.2 AWS 인증 확인

`terraform plan`은 AWS provider가 실제 리전, AMI, 계정 정보를 조회하므로 AWS CLI 인증이 필요함. 장기
Access Key 저장보다 AWS IAM Identity Center(SSO) 또는 일시 자격 증명을 우선함.

```powershell
aws --version
aws sts get-caller-identity
```

`No valid credential sources found`가 나오면 AWS CLI 설치와 인증 상태를 먼저 복구함.

```powershell
aws configure sso
aws sso login --profile <profile_name>
$env:AWS_PROFILE = "<profile_name>"
aws sts get-caller-identity
```

### 4.3 AWS 인증 후

AWS 인증이 완료된 뒤 실제 생성 예정 리소스를 확인함.

```powershell
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -recursive
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan -var-file=env/dev.tfvars
```

`plan` 전 확인 사항:

- `infra/terraform/env/dev.tfvars`의 `github_repository = "OWNER/REPO"`가 실제 저장소명으로 바뀌어
  있음
- AWS 리전이 팀 기준과 일치함
- 비용 발생 리소스(ALB, NAT Gateway, EC2, WAF)를 생성해도 되는 시점임
- 팀에서 정한 apply 담당자와 state 파일 보관 위치가 명확함

`plan` 결과 검토 기준:

- AWS burst app EC2는 App Private Subnet에 배치됨
- ProxySQL과 PXC EC2는 Data Private Subnet에 배치되고 Public IP가 없음
- DB 관련 포트가 `0.0.0.0/0`에 열리지 않음
- GitHub OIDC Role의 trust policy가 실제 저장소로 제한됨
- WAF, CloudWatch Log Group, AWS EC2 Auto Scaling 기준이 포함됨
- 예기치 않은 고비용 리소스 또는 불필요한 공개 리소스가 없음

`apply`는 팀 합의 후 담당자 1명만 실행함.

```powershell
terraform -chdir=infra/terraform apply -var-file=env/dev.tfvars
```

## 5. 샘플 앱 로컬 검증

```powershell
docker build -t cloud-infra-app:local ./app
docker run --rm -p 8080:8080 cloud-infra-app:local
```

다른 터미널에서 확인:

```powershell
.\scripts\smoke-test.ps1 -BaseUrl http://localhost:8080
```
