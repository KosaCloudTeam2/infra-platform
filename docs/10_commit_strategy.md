# Git 작업 전략

## 1. 브랜치

- `main`: 발표 가능한 안정 상태
- `feature/network-iac`: VPC/ALB/SG
- `feature/ecs-runtime`: ECS/ECR/Task Definition
- `feature/cicd-security`: GitHub Actions/IAM/WAF
- `feature/observability`: CloudWatch/Alarm/Runbook
- `docs/presentation`: 발표 자료

## 2. 커밋 메시지

```text
type(scope): summary
```

예시

- `feat(terraform): add vpc and alb baseline`
- `feat(ecs): add fargate service definition`
- `ci(github): add oidc based deploy workflow`
- `docs(plan): add 13 plus 3 schedule`

## 3. PR 기준

- 변경 목적이 명확함
- 관련 문서가 함께 갱신됨
- Terraform 변경 시 `fmt/validate/plan` 결과를 남김
- 배포 관련 변경 시 롤백 방법을 적음
- GitHub 공유 정책은 [Repository Sharing Policy](./12_repository_sharing_policy.md)를 따름

## 4. 커밋 단계 검사 기준

커밋할 때 실행되는 pre-commit 검사는 “커밋에 포함되는 파일”을 기준으로 동작함. 따라서 팀원이 일부
파일만 커밋하면 해당 staged 파일 중 hook 조건에 맞는 파일만 검사함.

커밋 단계에 유지할 검사:

- Gitleaks 시크릿 스캔
- 개인키 탐지
- 대용량 파일 차단
- YAML/JSON 문법 검사
- 파일 끝 개행, trailing whitespace 정리
- merge conflict marker 검사
- Prettier 포맷 검사
- Ruff Python 포맷/lint 검사
- ShellCheck
- Terraform fmt

Prettier는 커밋 단계에서 반드시 유지함. 이유는 팀원마다 VSCode 저장 시 포맷 설정이 다르더라도,
저장소에 들어가는 Markdown, YAML, JSON, JavaScript 파일의 스타일은 동일해야 하기 때문임.

Prettier는 모든 파일에 적용하지 않고 Prettier가 안정적으로 다루는 파일에만 적용함.

| 파일 유형              | 커밋 단계 포맷 기준                                  |
| :--------------------- | :--------------------------------------------------- |
| Markdown               | Prettier                                             |
| YAML                   | Prettier + check-yaml                                |
| JSON                   | Prettier + check-json                                |
| JavaScript             | Prettier                                             |
| Terraform              | `terraform fmt`                                      |
| Shell script           | ShellCheck로 검사, 자동 포맷은 별도 도입 전까지 보류 |
| Python                 | `ruff format --check` + `ruff check`                 |
| INI, `.env`, lock 파일 | Prettier 대상 아님                                   |

## 5. pre-push 또는 CI로 분리할 검사

커밋 단계는 빠른 피드백을 목표로 함. 시간이 오래 걸리거나 AWS 인증이 필요한 검사는 pre-push 또는
CI로 분리함.

pre-push 또는 CI 후보:

- `pnpm audit`
- `pip-audit`
- Terraform `validate`
- Terraform `plan`
- MkDocs build
- 전체 파일 기준 품질 검사

Prettier는 문서가 많아지면 체감될 수 있지만, 기본 정책은 commit 단계 유지임. 단, 실행 대상은 전체
저장소가 아니라 커밋에 포함된 staged 파일로 제한함.
