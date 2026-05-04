# Repository Sharing Policy

인프라 프로젝트에서 GitHub에 공유할 자료와 공유하면 안 되는 자료를 구분하기 위한 기준

---

## 1. 핵심 원칙

웹개발 프로젝트는 애플리케이션 코드가 중심이지만, 인프라 프로젝트는 **재현 가능한 구축 과정**이 핵심
산출물임. 따라서 GitHub에는 코드뿐 아니라 설계 근거, 운영 절차, 검증 기록, 발표 자료 원본을 함께
관리함.

- **공유해야 할 것:** 다시 만들 수 있는 코드와 절차
- **공유하면 안 되는 것:** 실제 계정·권한·비밀·상태 파일
- **팀 합의가 필요한 것:** 비용 발생 리소스, 콘솔 캡처, 발표용 산출물 PDF

---

## 2. 반드시 공유할 자료

| 분류             | 경로                                                                  | 공유 이유                                          |
| :--------------- | :-------------------------------------------------------------------- | :------------------------------------------------- |
| 인프라 코드(IaC) | `infra/terraform/**`                                                  | VPC, ALB, ECS, IAM, WAF 등을 재현 가능하게 구축    |
| CI/CD            | `.github/workflows/**`                                                | 배포 자동화 흐름과 권한 사용 방식을 팀 전체가 확인 |
| 앱 배포 기준     | `app/Dockerfile`, `app/README.md`                                     | 인프라가 실제 컨테이너를 실행하는지 검증           |
| 아키텍처 문서    | `docs/01_architecture.md`                                             | 왜 이 구조를 선택했는지 설명                       |
| 일정/역할        | `docs/02_schedule_13_plus_3.md`, `docs/03_roles_and_work_packages.md` | 4인 팀 작업 분담과 마감 기준 공유                  |
| 보안 정책        | `docs/05_security_policy.md`                                          | IAM, SG, WAF, Secret 관리 기준 명확화              |
| Runbook          | `docs/runbooks/**`                                                    | 배포, 롤백, 장애 대응을 누구나 수행 가능하게 함    |
| 환경 구축        | `docs/ENVIRONMENT_SETUP.md`                                           | 팀원 로컬 환경과 품질 자동화 기준 통일             |
| 발표 원본        | `docs/presentation/*.md`                                              | 발표 자료를 코드처럼 리뷰하고 버전 관리            |
| 검증 체크리스트  | `tests/checklist.md`                                                  | 구축 완료 기준과 검증 흔적 관리                    |

---

## 3. 공유하면 안 되는 자료

| 자료                | 예시                                         | 이유                                   |
| :------------------ | :------------------------------------------- | :------------------------------------- |
| Terraform 상태 파일 | `*.tfstate`, `*.tfstate.backup`              | 리소스 ID, 출력값, 민감 정보 포함 가능 |
| 환경 변수 파일      | `.env`, `.env.prod`                          | Secret, DB 접속 정보, 토큰 포함 가능   |
| AWS 장기 키         | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | 계정 탈취 위험                         |
| 개인키/인증서       | `*.pem`, `*.key`, `*.p12`, `*.pfx`           | 서버 접속 또는 인증 권한 유출          |
| 로컬 캐시/의존성    | `.terraform/`, `node_modules/`, `.venv/`     | 재생성 가능하고 저장소 비대화 유발     |
| 빌드 산출물         | `dist/`, `build/`, PDF                       | 원본으로 재생성 가능                   |
| 민감 콘솔 캡처      | 계정 ID, Role ARN, Secret 값 노출 이미지     | 발표 자료라도 마스킹 필요              |

---

## 4. GitHub에 올리기 전 점검

커밋 전 확인

- [ ] `.env` 또는 실제 Secret 값이 포함되지 않음
- [ ] `*.tfstate` 파일이 포함되지 않음
- [ ] 개인키, 인증서, AWS Access Key가 없음
- [ ] 콘솔 캡처 이미지에 계정 ID, 이메일, ARN, Secret 값이 노출되지 않음
- [ ] `pnpm run format:check` 통과
- [ ] `uv run pre-commit run --all-files` 통과

푸시 전 확인

- [ ] Terraform 변경 시 `terraform fmt`, `terraform validate`, `terraform plan` 결과 확인
- [ ] GitHub Actions 변경 시 workflow 변수와 Secret 이름 확인
- [ ] 발표 자료 변경 시 `pnpm run slides:pdf`로 PDF 생성 가능 여부 확인

---

## 5. 인프라 구축 시 GitHub의 역할

GitHub는 단순 파일 저장소가 아니라 다음 역할을 수행함.

1. **설계 합의 공간:** 아키텍처, 보안 정책, 비용 선택 기준 리뷰
2. **구축 레시피:** Terraform과 Runbook을 통한 재현 가능한 인프라 구성
3. **배포 제어면:** GitHub Actions 이미지 빌드와 Argo CD GitOps 배포
4. **감사 기록:** PR, 커밋, Actions 로그를 통한 변경 이력 추적
5. **발표 준비 공간:** 시연 스크립트, Q&A, 발표 원본 관리

---

## 6. 현재 프로젝트 기준 공유 구조

```text
.
├── .github/workflows/        # CI/CD와 Terraform 검사
├── app/                      # 샘플 앱 또는 기존 앱 연결 기준
├── docs/
│   ├── ENVIRONMENT_SETUP.md  # 팀원 온보딩
│   ├── 01_architecture.md    # 설계와 선택 근거
│   ├── 02_schedule_13_plus_3.md
│   ├── 03_roles_and_work_packages.md
│   ├── 05_security_policy.md
│   ├── 12_repository_sharing_policy.md
│   ├── runbooks/             # 배포/롤백/장애 대응
│   └── presentation/         # 발표 자료 원본
├── infra/terraform/          # AWS 인프라 코드
├── scripts/                  # 테스트/운영 보조 스크립트
└── tests/                    # 검증 체크리스트
```

---

## 7. 발표 자료와 PDF 관리

발표 자료 원본은 `docs/presentation/presentation.md`로 관리함. PDF는 `pnpm run slides:pdf`로 생성
가능한 산출물이므로 기본적으로 Git 추적 대상에서 제외함.

단, 제출 플랫폼이 PDF 파일 자체를 요구하거나 발표 당일 버전 고정이 필요하면 다음 기준으로만 예외
허용함.

- 파일명에 날짜 또는 발표 버전 명시: `cloud-infra-presentation-v1.pdf`
- Secret, 계정 ID, 이메일, ARN 등이 마스킹되어 있음
- 원본 Markdown과 동일한 버전에서 생성됨

---

## 8. 팀 규칙

- 인프라 변경은 PR로 공유하고 최소 1명 리뷰 후 병합
- `apply`는 담당자 1명만 수행하고 결과를 PR 또는 이슈에 기록
- 콘솔 수작업이 발생하면 반드시 Runbook 또는 문서에 반영
- Day 14 이후에는 발표 안정화를 위해 새 인프라 기능 추가 금지
- 발표 후 비용 발생 리소스는 `docs/09_cleanup_plan.md` 기준으로 정리
