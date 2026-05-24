# Harbor metadata 백업/복구 Runbook

> Status: Draft 범위: Harbor project/user/robot/replication policy 같은 metadata와 Kubernetes 설정
> 백업. Harbor registry blob 백업은 제외함. 현재 image pull 최적화는 Harbor -> ECR replication 기준.

---

## 1. 적용 범위

대상:

- Harbor namespace: `harbor`
- Harbor Helm chart 기반 배포
- Harbor metadata DB
- Harbor Kubernetes Secret/ConfigMap/Ingress/Service/Deployment/StatefulSet/PVC 정의
- Harbor Helm values/manifest
- Harbor API export 가능한 registry/replication/project 정보

제외:

- Harbor registry blob S3 copy
- Ceph RGW `harbor-registry` bucket copy
- ECR image backup
- Trivy cache
- Redis session/job runtime data
- 실제 복구 검증

현재 Harbor 구성 기준:

| 항목             | 값                          |
| :--------------- | :-------------------------- |
| Namespace        | `harbor`                    |
| URL              | `https://harbor.kosa.team2` |
| Helm chart       | `harbor/harbor 1.16.0`      |
| Harbor version   | v2.12 계열                  |
| Registry backend | Ceph RGW S3                 |
| Registry bucket  | `harbor-registry`           |
| ECR replication  | `kosa-tickets-to-ecr`       |

> ECR mirror는 Harbor 전체 백업이 아님. ECR은 image artifact pull 경로이고, Harbor DB/config
> metadata는 별도 백업 대상.

---

## 2. 백업 대상

필수:

- Harbor PostgreSQL DB dump
- Kubernetes Secret/ConfigMap
- Harbor Helm values
- Harbor Ingress/Service/Deployment/StatefulSet/PVC 정의
- Harbor replication policy export
- Harbor registry endpoint export

선택:

- Harbor project list
- Harbor robot account list
- Harbor scanner 설정
- Harbor label
- Harbor certificate 정보

백업하지 않는 항목:

- `harbor-registry` image blob 전체
- Redis runtime cache
- 미완료 job/session 상태

이유:

- image blob은 Ceph RGW/ECR 경로와 중복
- Redis는 runtime/cache 성격
- metadata 복구 목표는 Harbor 재구성 가능성 확보

---

## 3. 권장 구조

```text
bastion cron
    -> kubectl/helm으로 Harbor metadata export
    -> Harbor DB pod에서 pg_dump
    -> Harbor API export
    -> tar.gz 압축
    -> sha256 생성
    -> AWS S3 업로드
    -> Slack 알림
```

저장 위치:

```text
s3://team2-harbor-metadata-backup/onprem-harbor/daily/
s3://team2-harbor-metadata-backup/onprem-harbor/weekly/
s3://team2-harbor-metadata-backup/onprem-harbor/manual/
```

권장 이유:

- Harbor image blob 백업과 metadata 백업 분리
- ECR replication 한계 보완
- Harbor 재설치/정책 복원에 필요한 정보 확보
- Object backup, etcd backup, PXC backup과 권한 분리

---

## 4. 주기와 보관

PoC/발표 기준:

| 구분   | 주기            | 보관          | 설명                                 |
| :----- | :-------------- | :------------ | :----------------------------------- |
| daily  | 매일 03:50      | 14일          | 기본 metadata 백업                   |
| manual | 설정 변경 전/후 | 발표 종료까지 | registry/replication/robot 변경 전후 |

장기 운영 기준:

| 구분   | 주기                | 보관    | 설명           |
| :----- | :------------------ | :------ | :------------- |
| daily  | 매일                | 14~30일 | 운영 복구 지점 |
| weekly | 매주                | 8주     | 장기 복구 지점 |
| manual | 중요한 설정 변경 전 | 365일   | 변경 전 기준점 |

manual 권장 시점:

- registry endpoint 추가/수정
- replication policy 추가/수정
- robot account 생성/삭제
- project 권한 변경
- Harbor chart/values 변경
- TLS 인증서 변경

---

## 5. S3 bucket 준비

bucket 생성:

```bash
export AWS_REGION=ap-northeast-2

aws s3api create-bucket \
  --bucket team2-harbor-metadata-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}
```

Versioning:

```bash
aws s3api put-bucket-versioning \
  --bucket team2-harbor-metadata-backup \
  --versioning-configuration Status=Enabled
```

Public Access Block:

```bash
aws s3api put-public-access-block \
  --bucket team2-harbor-metadata-backup \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

기본 암호화:

```bash
aws s3api put-bucket-encryption \
  --bucket team2-harbor-metadata-backup \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'
```

---

## 6. S3 Lifecycle

`harbor-metadata-lifecycle.json`:

```json
{
  "Rules": [
    {
      "ID": "expire-daily-harbor-metadata",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-harbor/daily/"
      },
      "Expiration": {
        "Days": 14
      }
    },
    {
      "ID": "archive-weekly-harbor-metadata",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-harbor/weekly/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 56
      }
    },
    {
      "ID": "archive-manual-harbor-metadata",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-harbor/manual/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 365
      }
    },
    {
      "ID": "abort-incomplete-multipart-harbor-metadata",
      "Status": "Enabled",
      "Filter": {},
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
```

적용:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket team2-harbor-metadata-backup \
  --lifecycle-configuration file://harbor-metadata-lifecycle.json
```

---

## 7. backup.env

파일:

```text
/home/ubuntu/backup-test/backup.env
```

추가 가능 값:

```bash
AWS_DEFAULT_REGION="ap-northeast-2"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/REPLACE/REPLACE/REPLACE"

# 선택: Harbor API export용
HARBOR_URL="https://harbor.kosa.team2"
HARBOR_API_USER="REPLACE_HARBOR_USER"
HARBOR_API_PASSWORD="REPLACE_HARBOR_PASSWORD"
```

주의:

- `HARBOR_API_PASSWORD`는 Secret
- 저장소 커밋 금지
- Slack/스크린샷 노출 금지
- API export가 없어도 DB dump와 Kubernetes manifest 백업은 가능

---

## 8. 백업 스크립트

파일:

```text
/home/ubuntu/backup-test/harbor-metadata-backup.sh
```

전제:

- bastion에서 `kubectl --context kubernetes-admin@kubernetes` 가능
- bastion에서 `aws sts get-caller-identity` 가능
- Harbor namespace `harbor` 존재
- Harbor DB pod 접근 가능

스크립트:

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/home/ubuntu/backup-test"
ENV_FILE="${WORKDIR}/backup.env"
LOGDIR="${WORKDIR}/logs"
LOCAL_DIR="${WORKDIR}/harbor-metadata"

KUBE_CONTEXT="kubernetes-admin@kubernetes"
NAMESPACE="harbor"

S3_BUCKET="team2-harbor-metadata-backup"
MODE="${1:-daily}"

case "${MODE}" in
  daily|weekly|manual)
    ;;
  *)
    echo "Usage: $0 [daily|weekly|manual]" >&2
    exit 2
    ;;
esac

S3_PREFIX="onprem-harbor/${MODE}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="harbor-metadata-${MODE}-${TS}"
BACKUP_DIR="${LOCAL_DIR}/${BACKUP_NAME}"
ARCHIVE_NAME="${BACKUP_NAME}.tar.gz"
LOGFILE="${LOGDIR}/harbor-metadata-backup-$(date +%Y%m%d).log"

mkdir -p "${LOGDIR}" "${LOCAL_DIR}" "${BACKUP_DIR}"

if [ -f "${ENV_FILE}" ]; then
  set -a
  . "${ENV_FILE}"
  set +a
fi

STATUS=0

{
  echo "[START] $(date -Is)"
  echo "[MODE] ${MODE}"
  echo "[NAMESPACE] ${NAMESPACE}"
  echo "[BACKUP] ${BACKUP_NAME}"

  echo "[CHECK] AWS identity"
  aws sts get-caller-identity >/dev/null

  echo "[CHECK] S3 bucket"
  aws s3api head-bucket --bucket "${S3_BUCKET}"

  echo "[CHECK] Kubernetes access"
  kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get pod

  echo "[EXPORT] Kubernetes resources"
  kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" \
    get secret,configmap,ingress,svc,deploy,sts,pvc \
    -o yaml > "${BACKUP_DIR}/harbor-k8s-resources.yaml"

  echo "[EXPORT] Helm values and manifest"
  if command -v helm >/dev/null 2>&1; then
    helm -n "${NAMESPACE}" get values harbor -o yaml > "${BACKUP_DIR}/harbor-helm-values.yaml" || true
    helm -n "${NAMESPACE}" get manifest harbor > "${BACKUP_DIR}/harbor-helm-manifest.yaml" || true
  else
    echo "helm not found" > "${BACKUP_DIR}/helm-not-found.txt"
  fi

  echo "[EXPORT] Harbor database dump"
  DB_POD="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get pod -l component=database -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -z "${DB_POD}" ]; then
    DB_POD="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get pod --no-headers | awk '/database|postgres/{print $1; exit}')"
  fi

  if [ -z "${DB_POD}" ]; then
    echo "Harbor database pod not found" >&2
    exit 1
  fi

  kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" exec "${DB_POD}" -- sh -c '
    set -e
    DB_USER="${POSTGRESQL_USERNAME:-postgres}"
    DB_NAME="${POSTGRESQL_DATABASE:-registry}"
    export PGPASSWORD="${POSTGRESQL_PASSWORD:-${POSTGRES_PASSWORD:-}}"
    pg_dump -U "${DB_USER}" -d "${DB_NAME}" -Fc
  ' > "${BACKUP_DIR}/harbor-db.dump"

  echo "[EXPORT] Harbor API metadata"
  if [ -n "${HARBOR_URL:-}" ] && [ -n "${HARBOR_API_USER:-}" ] && [ -n "${HARBOR_API_PASSWORD:-}" ]; then
    curl -ksS -u "${HARBOR_API_USER}:${HARBOR_API_PASSWORD}" \
      "${HARBOR_URL}/api/v2.0/registries" > "${BACKUP_DIR}/harbor-api-registries.json" || true
    curl -ksS -u "${HARBOR_API_USER}:${HARBOR_API_PASSWORD}" \
      "${HARBOR_URL}/api/v2.0/replication/policies" > "${BACKUP_DIR}/harbor-api-replication-policies.json" || true
    curl -ksS -u "${HARBOR_API_USER}:${HARBOR_API_PASSWORD}" \
      "${HARBOR_URL}/api/v2.0/projects?page_size=100" > "${BACKUP_DIR}/harbor-api-projects.json" || true
    curl -ksS -u "${HARBOR_API_USER}:${HARBOR_API_PASSWORD}" \
      "${HARBOR_URL}/api/v2.0/robots?page_size=100" > "${BACKUP_DIR}/harbor-api-robots.json" || true
  else
    echo "Harbor API credential not configured" > "${BACKUP_DIR}/harbor-api-skipped.txt"
  fi

  echo "[ARCHIVE] tar.gz"
  tar -C "${LOCAL_DIR}" -czf "${LOCAL_DIR}/${ARCHIVE_NAME}" "${BACKUP_NAME}"
  (cd "${LOCAL_DIR}" && sha256sum "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256")

  echo "[VERIFY] local archive"
  ls -lh "${LOCAL_DIR}/${ARCHIVE_NAME}" "${LOCAL_DIR}/${ARCHIVE_NAME}.sha256"
  (cd "${LOCAL_DIR}" && sha256sum -c "${ARCHIVE_NAME}.sha256")

  echo "[UPLOAD] S3"
  aws s3 cp "${LOCAL_DIR}/${ARCHIVE_NAME}" \
    "s3://${S3_BUCKET}/${S3_PREFIX}/${ARCHIVE_NAME}" \
    --sse AES256
  aws s3 cp "${LOCAL_DIR}/${ARCHIVE_NAME}.sha256" \
    "s3://${S3_BUCKET}/${S3_PREFIX}/${ARCHIVE_NAME}.sha256" \
    --sse AES256

  echo "[VERIFY] S3"
  aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${ARCHIVE_NAME}"
  aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${ARCHIVE_NAME}.sha256"

  echo "[CLEANUP] local retention"
  find "${LOCAL_DIR}" -maxdepth 1 -type f -name 'harbor-metadata-*.tar.gz*' -mtime +2 -delete
  find "${LOCAL_DIR}" -maxdepth 1 -type d -name 'harbor-metadata-*' -mtime +2 -exec rm -rf {} +

  echo "[END] $(date -Is)"
} >> "${LOGFILE}" 2>&1 || STATUS=$?

if [ "${STATUS}" -eq 0 ]; then
  MESSAGE="[SUCCESS] Harbor metadata backup command completed on $(hostname) at $(date -Is). mode=${MODE}, s3=s3://${S3_BUCKET}/${S3_PREFIX}/${ARCHIVE_NAME}, log=${LOGFILE}"
else
  MESSAGE="[FAILED] Harbor metadata backup command failed on $(hostname) at $(date -Is). mode=${MODE}, log=${LOGFILE}"
fi

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  curl -fsS -X POST \
    -H "Content-Type: application/json" \
    --data "{\"text\":\"${MESSAGE}\"}" \
    "${SLACK_WEBHOOK_URL}" >/dev/null || true
fi

exit "${STATUS}"
```

권한:

```bash
chmod 700 /home/ubuntu/backup-test/harbor-metadata-backup.sh
```

주의:

- `harbor-k8s-resources.yaml`에는 Secret이 포함됨
- `harbor-api-registries.json`의 registry credential은 마스킹될 수 있음
- 마스킹된 credential은 복구용 Secret을 대체하지 않음
- Secret 원본은 Kubernetes Secret 백업과 별도 비밀 관리 정책 기준으로 보호

---

## 9. 수동 실행

daily:

```bash
/home/ubuntu/backup-test/harbor-metadata-backup.sh daily
echo $?
```

weekly:

```bash
/home/ubuntu/backup-test/harbor-metadata-backup.sh weekly
echo $?
```

manual:

```bash
/home/ubuntu/backup-test/harbor-metadata-backup.sh manual
echo $?
```

로그 확인:

```bash
tail -n 160 /home/ubuntu/backup-test/logs/harbor-metadata-backup-$(date +%Y%m%d).log
```

S3 확인:

```bash
aws s3 ls s3://team2-harbor-metadata-backup/onprem-harbor/daily/ --recursive --summarize
aws s3 ls s3://team2-harbor-metadata-backup/onprem-harbor/weekly/ --recursive --summarize
aws s3 ls s3://team2-harbor-metadata-backup/onprem-harbor/manual/ --recursive --summarize
```

성공 기준:

- Harbor namespace 접근 성공
- DB dump 생성
- K8s resource YAML 생성
- Helm values 또는 manifest export 시도
- tar.gz 생성
- sha256 검증 성공
- S3 업로드 확인
- Slack `[SUCCESS]` 수신

---

## 10. cron 등록

PoC/발표 기준:

```cron
50 3 * * * /home/ubuntu/backup-test/harbor-metadata-backup.sh daily
```

중요 변경 전/후:

```bash
/home/ubuntu/backup-test/harbor-metadata-backup.sh manual
```

주의:

- Object backup, etcd backup, PXC backup과 시간 분리
- Harbor chart upgrade 전 manual backup
- replication policy 변경 전후 manual backup
- registry credential 변경 전후 manual backup

---

## 11. 복구 정책

현재 단계:

- 복구 실습 미수행
- 정책/절차만 문서화
- 운영 Harbor in-place 복구 금지

복구 기본 흐름:

```text
S3에서 metadata archive 다운로드
    -> sha256 검증
    -> tar.gz 해제
    -> Harbor Helm values/Secret/ConfigMap 확인
    -> test namespace 또는 신규 Harbor에 배포
    -> PostgreSQL DB dump restore
    -> project/user/robot/replication policy 확인
    -> ECR replication 재검증
```

복구 시 주의:

- Harbor image blob은 이 문서 백업 대상 아님
- ECR mirror는 image pull 경로이지 Harbor metadata 복구가 아님
- registry credential은 API export에서 마스킹될 수 있음
- robot token은 재생성 필요 가능성 있음
- Redis runtime data는 복구 대상 아님
- running job/session 손실 가능
- 운영 Harbor에 바로 덮어쓰기 금지

복구 검증 기준:

- test namespace 또는 별도 cluster
- Harbor UI login
- project 목록 확인
- robot account 재생성/검증
- replication policy 확인
- ECR push-based replication dry-run 또는 실제 tag test
- pull secret 영향 확인

---

## 12. Velero 선택지

Harbor가 Kubernetes에 Helm chart로 배포되어 있으므로 Velero도 선택 가능.

장점:

- Kubernetes resource/PV 단위 백업
- Harbor chart 전체에 가까운 복구 가능
- namespace 단위 복구 흐름 단순화

한계:

- Redis runtime data는 제한 가능
- registry blob까지 포함하면 백업 범위와 비용 증가
- 현재 Harbor image는 ECR replication으로 별도 최적화
- metadata만 명확히 백업하려는 목적에는 DB dump + config export가 더 가벼움

현재 추천:

- 지금은 DB dump + K8s/Helm/API export
- 장기 운영 시 Velero 기반 Harbor 전체 DR 별도 검토

---

## 13. 보안 기준

민감 정보:

- Harbor DB dump
- Kubernetes Secret YAML
- robot account 정보
- registry endpoint credential
- S3 access key
- Slack webhook

보안 원칙:

- Git 저장소 커밋 금지
- Slack에 Secret 출력 금지
- S3 bucket public access block 필수
- SSE-S3 또는 SSE-KMS 적용
- read 권한 최소화
- 복구 담당자 제한

파일 권한:

```bash
chmod 700 /home/ubuntu/backup-test/harbor-metadata-backup.sh
chmod 600 /home/ubuntu/backup-test/backup.env
chmod 600 /home/ubuntu/.kube/config
```

---

## 14. 참고

- Harbor administration: <https://goharbor.io/docs/main/administration/>
- Harbor Velero backup/restore: <https://goharbor.io/docs/main/administration/backup-restore/>
