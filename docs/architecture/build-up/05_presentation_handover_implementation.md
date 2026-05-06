# 05 Presentation / Handover Implementation

담당: 전원

## 1. 목표

구현 결과를 각 담당자가 직접 설명하고 시연 가능한 이야기로 정리하고, 발표 후 리소스 정리와 인계가
가능한 상태로 문서와 산출물을 마감함.

## 2. 사전 조건

- 각 담당자가 구현 결과, 검증 결과, 캡처, 설명 스크립트를 제공함
- 발표 자료 원본은 `docs/presentation/presentation.md`로 관리함
- Demo Script, Q&A, Cleanup Plan이 최신 상태임
- Secret, 계정 ID, 개인 정보가 캡처에 노출되지 않음

## 3. 구현 순서

1. 발표 목차를 전체 아키텍처 흐름에 맞게 정리
2. Cloud/Network/IaC 담당 캡처와 설명 스크립트 수집
3. DB/Storage 담당 캡처와 설명 스크립트 수집
4. CI/CD/App Runtime 담당 캡처와 설명 스크립트 수집
5. Observability/Integration/Demo 담당 캡처와 설명 스크립트 수집
6. 발표 자료에 비용, 한계, 향후 확장 정리
7. Demo Script와 발표 자료 순서 일치 확인
8. Q&A 예상 질문 업데이트
9. PDF 생성 및 리허설
10. 리소스 정리 계획 최종 확인

## 4. 발표 자료 생성

```powershell
pnpm run slides:pdf
```

또는:

```powershell
.\gen-pdf.ps1
```

검증 기준:

- PDF가 정상 생성됨
- 다이어그램과 표가 깨지지 않음
- 발표 시간이 10-15분 안에 들어옴
- Secret, AWS Account ID, 개인 정보가 노출되지 않음

## 5. 담당자별 인계 자료

| 담당                           | 필수 자료                                                            |
| :----------------------------- | :------------------------------------------------------------------- |
| Cloud/Network/IaC              | ALB DNS, Subnet/SG/WAF 캡처, EC2 ASG, Terraform plan 요약            |
| DB/Storage                     | PXC 상태, ProxySQL endpoint, Ceph 백업 경로, 복구 절차               |
| CI/CD/App Runtime              | GitHub Actions 실행 결과, Docker Hub 태그, Argo CD sync, K8s rollout |
| Observability/Integration/Demo | Prometheus/Grafana 또는 CloudWatch 캡처, 장애 시나리오 결과          |

## 6. 마감 체크리스트

- [ ] `docs/presentation/presentation.md` 최신화
- [ ] `docs/presentation/demo_script.md` 최신화
- [ ] `docs/presentation/qna.md` 최신화
- [ ] `docs/09_cleanup_plan.md` 최신화
- [ ] `docs/runbooks/*` 링크 확인
- [ ] 발표 PDF 생성 확인
- [ ] 리허설 시간 측정
- [ ] 각 담당자가 자기 영역 설명과 시연을 직접 수행 가능

## 7. 리소스 정리 기준

발표 후 정리 대상:

- AWS burst EC2/ASG 또는 ECS fallback 리소스
- ALB
- NAT Gateway
- WAF Web ACL
- EC2 기반 PXC/ProxySQL
- CloudWatch Log Group 보존 정책 확인
- Docker Hub 이미지 보존 정책 확인

## 8. 주의 사항

- Day 14 이후에는 신규 기능보다 발표 안정화와 캡처 확보를 우선함
- 실패한 기능은 숨기기보다 한계와 향후 과제로 정리함
- 비용 발생 리소스는 발표 후 정리 여부를 팀장이 최종 확인함
