# Troubleshooting

트러블슈팅 이슈 문서 목록.

## 네이밍 규칙

- 파일명: `TS-NN-<1~3단어-kebab-case>.md`
- 예: `TS-01-winget-terraform.md`
- 번호 중복은 허용하되, 발견 시 수동으로 정정함.

## 상태 규칙

- Open: 미해결
- Resolved: 해결 완료
- Deprecated: 더 이상 유효하지 않음

## 이슈 목록

| ID    | Status   | 제목                                            | 파일                                                                    |
| :---- | :------- | :---------------------------------------------- | :---------------------------------------------------------------------- |
| TS-01 | Resolved | winget/terraform 명령 미인식                    | [TS-01-winget-terraform](./TS-01-winget-terraform.md)                   |
| TS-02 | Resolved | terraform hook 실행 파일 미인식                 | [TS-02-terraform-hook](./TS-02-terraform-hook.md)                       |
| TS-03 | Resolved | husky/pre-commit 동작 불안정                    | [TS-03-husky-precommit](./TS-03-husky-precommit.md)                     |
| TS-04 | Resolved | ruff/pip-audit 실행 실패                        | [TS-04-ruff-pipaudit](./TS-04-ruff-pipaudit.md)                         |
| TS-05 | Resolved | Ceph endpoint가 잘못된 대역으로 설정됨          | [TS-05-ceph-endpoint-ip-mismatch](./TS-05-ceph-endpoint-ip-mismatch.md) |
| TS-06 | Resolved | FlaskApp 이미지 미표시(presigned URL 직통 구조) | [TS-06-flask-s3-image-proxy](./TS-06-flask-s3-image-proxy.md)           |
| TS-07 | Resolved | Bastion→RGW 경로 timeout(NIC/라우팅 불일치)     | [TS-07-bastion-rgw-route-timeout](./TS-07-bastion-rgw-route-timeout.md) |
