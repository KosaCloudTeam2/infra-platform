# PXC 백업/복구 Runbook

> Status: Draft 범위: 온프레미스 VM 기반 Percona XtraDB Cluster(PXC) 데이터 백업 정책과 절차. 현재
> 단계에서는 복구 실습을 수행하지 않고, 백업 산출물 생성/보관/복구 원칙만 문서화함.

---

## 1. 적용 범위

대상:

- 온프레미스 PXC 3노드
- ProxySQL endpoint 경유 앱 접속 구조
- MySQL/InnoDB 데이터
- Percona XtraBackup 기반 물리 백업

제외:

- Ceph RGW Object 백업
- Harbor registry blob 백업
- Harbor metadata 백업
- Kubernetes etcd 백업
- 애플리케이션 업로드 객체

> PXC replica와 Ceph RBD replica는 백업이 아님. 노드/디스크 장애 대응에는 유효하지만, 논리 삭제,
> 잘못된 migration, 데이터 오염, 랜섬웨어성 변경 복구에는 별도 백업 필요.

---

## 2. 용어

## 2.1 Full backup

전체 백업.

특징:

- 특정 시점의 전체 DB 파일 백업
- 복구 절차 단순
- 용량 큼
- 현재 PoC/발표 기준 우선 적용

## 2.2 Incremental backup

증분 백업.

```text
Full backup
    -> 이후 변경분만 incremental backup
    -> 복구 시 full + incremental 순서대로 적용
```

특징:

- 용량 절약
- 백업 시간 단축
- 복구 절차 복잡
- 현재 단계에서는 정책만 기록

## 2.3 PITR

Point-In-Time Recovery, 특정 시점 복구.

```text
full backup 복구
    -> binlog를 원하는 시점까지만 replay
    -> 장애 직전 시점 복구
```

특징:

- 데이터 손실 최소화
- binlog 보관 필요
- 시간 동기화 중요
- 복구 절차 복잡
- 현재 단계에서는 추후 개선 항목

## 2.4 SST

State Snapshot Transfer.

PXC/Galera에서 새 노드 또는 손상 노드가 클러스터에 합류할 때 정상 노드에서 전체 데이터 상태를
받아오는 동기화 방식.

주의:

- 백업이 아니라 클러스터 동기화 메커니즘
- donor 노드 부하 발생
- 데이터 크면 오래 걸림
- 복구 후 노드 재합류 시 발생 가능

---

## 3. 권장 구조

현재 추천:

```text
bastion cron
    -> SSH to PXC backup target node
    -> xtrabackup full backup 생성
    -> tar.gz 압축
    -> sha256 생성
    -> bastion으로 전송
    -> AWS S3 업로드
    -> Slack 알림
```

권장 실행 위치:

| 위치                | 권장도 | 설명                                        |
| :------------------ | :----- | :------------------------------------------ |
| PXC non-writer 노드 | 높음   | 앱 write 영향 최소화                        |
| PXC writer 노드     | 조건부 | 부하 낮은 시간대에만 수행                   |
| bastion 직접 실행   | 낮음   | DB 파일 접근 불가, SSH trigger만 권장       |
| backup-runner VM    | 향후   | 장기 운영 시 전용 스케줄러/저장소 역할 분리 |

저장 위치:

```text
s3://team2-pxc-backup/onprem-pxc/full/
s3://team2-pxc-backup/onprem-pxc/incremental/
s3://team2-pxc-backup/onprem-pxc/manual/
s3://team2-pxc-backup/onprem-pxc/binlog/
```

현재 단계:

- daily full backup 우선
- incremental 미적용
- PITR 미적용
- 복구 검증 미수행
- 복구 정책/주의사항만 문서화

---

## 4. 주기와 보관

PoC/발표 기준:

| 구분   | 주기         | 보관          | 설명                    |
| :----- | :----------- | :------------ | :---------------------- |
| full   | 매일 03:30   | 7~14일        | 기본 DB 백업            |
| manual | 중요 작업 전 | 발표 종료까지 | schema 변경 전 snapshot |

장기 운영 기준:

| 구분        | 주기                   | 보관             | 설명              |
| :---------- | :--------------------- | :--------------- | :---------------- |
| full        | 매주 1회               | 4~8주            | 기준 백업         |
| incremental | 매일                   | full 주기와 동일 | 변경분 백업       |
| binlog      | 15분~1시간 단위 업로드 | 7~30일           | PITR용            |
| manual      | 배포/마이그레이션 전   | 90~365일         | 변경 전 복구 지점 |

현재 추천:

- daily full 14일
- manual 중요 작업 전
- weekly/incremental/binlog는 추후 개선

---

## 5. 사전 확인

## 5.1 PXC 노드 확인

bastion에서:

```bash
kubectl config current-context
kubectl get nodes -o wide
```

PXC 노드 접속 예시:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@<PXC_NODE_IP>
```

PXC 상태 확인:

```bash
mysql -uroot -p -e "SHOW STATUS LIKE 'wsrep_cluster_status';"
mysql -uroot -p -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"
mysql -uroot -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

기대:

- `wsrep_cluster_status`: `Primary`
- `wsrep_local_state_comment`: `Synced`
- `wsrep_cluster_size`: `3`

백업 대상 노드 기준:

- `Synced` 상태
- disk 여유 공간 충분
- 앱 트래픽 적은 시간대
- 가능하면 ProxySQL writer가 아닌 노드

## 5.2 XtraBackup 확인

PXC 노드:

```bash
xtrabackup --version
```

없으면 설치 필요.

> XtraBackup version은 MySQL/PXC major version과 호환되어야 함. 버전 불일치 시 백업 성공 후 복구
> 실패 가능성 있음.

## 5.3 백업 계정

PXC에서 전용 계정 생성 예시:

```sql
CREATE USER 'pxc_backup'@'localhost' IDENTIFIED BY '<STRONG_PASSWORD>';
GRANT BACKUP_ADMIN, PROCESS, RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'pxc_backup'@'localhost';
GRANT SELECT ON performance_schema.log_status TO 'pxc_backup'@'localhost';
GRANT SELECT ON performance_schema.keyring_component_status TO 'pxc_backup'@'localhost';
GRANT SELECT ON performance_schema.replication_group_members TO 'pxc_backup'@'localhost';
FLUSH PRIVILEGES;
```

주의:

- 권한은 MySQL/PXC version에 따라 달라질 수 있음
- `SHOW PRIVILEGES`와 XtraBackup 실행 결과 기준으로 조정
- 백업 계정 password는 저장소 커밋 금지

PXC 노드에 credential 파일 생성:

```bash
sudo install -m 600 -o root -g root /dev/null /root/.pxc-backup.cnf

sudo tee /root/.pxc-backup.cnf >/dev/null <<'EOF'
[client]
user=pxc_backup
password=REPLACE_STRONG_PASSWORD
socket=/var/lib/mysql/mysql.sock
EOF
```

---

## 6. S3 bucket 준비

AWS CLI 실행 위치:

- bastion
- AWS CLI 인증 완료

bucket 생성:

```bash
export AWS_REGION=ap-northeast-2

aws s3api create-bucket \
  --bucket team2-pxc-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}
```

Versioning:

```bash
aws s3api put-bucket-versioning \
  --bucket team2-pxc-backup \
  --versioning-configuration Status=Enabled
```

Public Access Block:

```bash
aws s3api put-public-access-block \
  --bucket team2-pxc-backup \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

기본 암호화:

```bash
aws s3api put-bucket-encryption \
  --bucket team2-pxc-backup \
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

## 7. S3 Lifecycle

`pxc-lifecycle.json`:

```json
{
  "Rules": [
    {
      "ID": "expire-daily-pxc-full",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-pxc/full/"
      },
      "Expiration": {
        "Days": 14
      }
    },
    {
      "ID": "archive-manual-pxc-backup",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-pxc/manual/"
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
      "ID": "abort-incomplete-multipart-pxc",
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
  --bucket team2-pxc-backup \
  --lifecycle-configuration file://pxc-lifecycle.json
```

---

## 8. 백업 스크립트

파일:

```text
/home/ubuntu/backup-test/pxc-backup.sh
```

전제:

- PXC 노드에 `/root/.pxc-backup.cnf` 존재
- PXC 노드에서 `sudo -n true` 가능
- bastion에서 PXC 노드 SSH 가능
- bastion AWS CLI 인증 완료
- `/home/ubuntu/backup-test/backup.env`에 Slack Webhook 설정 가능

스크립트:

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/home/ubuntu/backup-test"
ENV_FILE="${WORKDIR}/backup.env"
LOGDIR="${WORKDIR}/logs"
LOCAL_DIR="${WORKDIR}/pxc"

SSH_KEY="/home/ubuntu/.ssh/kosa_iac"
PXC_USER="ubuntu"
PXC_HOST="<PXC_NODE_IP>"
REMOTE_DIR="/var/backups/pxc"

S3_BUCKET="team2-pxc-backup"
MODE="${1:-full}"

case "${MODE}" in
  full|manual)
    ;;
  *)
    echo "Usage: $0 [full|manual]" >&2
    exit 2
    ;;
esac

if [ "${MODE}" = "manual" ]; then
  S3_PREFIX="onprem-pxc/manual"
else
  S3_PREFIX="onprem-pxc/full"
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="pxc-${MODE}-${TS}"
ARCHIVE_NAME="${BACKUP_NAME}.tar.gz"
LOGFILE="${LOGDIR}/pxc-backup-$(date +%Y%m%d).log"

mkdir -p "${LOGDIR}" "${LOCAL_DIR}"

if [ -f "${ENV_FILE}" ]; then
  set -a
  . "${ENV_FILE}"
  set +a
fi

STATUS=0

{
  echo "[START] $(date -Is)"
  echo "[MODE] ${MODE}"
  echo "[PXC] ${PXC_USER}@${PXC_HOST}"
  echo "[BACKUP] ${BACKUP_NAME}"

  echo "[CHECK] AWS identity"
  aws sts get-caller-identity >/dev/null

  echo "[CHECK] S3 bucket"
  aws s3api head-bucket --bucket "${S3_BUCKET}"

  echo "[CHECK] SSH and sudo"
  ssh -i "${SSH_KEY}" -o BatchMode=yes "${PXC_USER}@${PXC_HOST}" \
    'sudo -n true && xtrabackup --version'

  echo "[SNAPSHOT] xtrabackup on PXC node"
  ssh -i "${SSH_KEY}" -o BatchMode=yes "${PXC_USER}@${PXC_HOST}" \
    "sudo env BACKUP_NAME='${BACKUP_NAME}' REMOTE_DIR='${REMOTE_DIR}' REMOTE_OWNER='${PXC_USER}:${PXC_USER}' bash -s" <<'REMOTE'
set -euo pipefail

TARGET="${REMOTE_DIR}/${BACKUP_NAME}"
ARCHIVE="${REMOTE_DIR}/${BACKUP_NAME}.tar.gz"

mkdir -p "${TARGET}"

mysql --defaults-extra-file=/root/.pxc-backup.cnf \
  -e "SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_status','wsrep_local_state_comment','wsrep_cluster_size');"

xtrabackup --defaults-extra-file=/root/.pxc-backup.cnf \
  --backup \
  --galera-info \
  --target-dir="${TARGET}"

test -f "${TARGET}/xtrabackup_checkpoints"
test -f "${TARGET}/xtrabackup_galera_info"

tar -C "${REMOTE_DIR}" -czf "${ARCHIVE}" "${BACKUP_NAME}"
cd "${REMOTE_DIR}"
sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.tar.gz.sha256"
chown "${REMOTE_OWNER}" "${ARCHIVE}" "${ARCHIVE}.sha256"
rm -rf "${TARGET}"
REMOTE

  echo "[COPY] PXC node -> bastion"
  scp -i "${SSH_KEY}" -o BatchMode=yes \
    "${PXC_USER}@${PXC_HOST}:${REMOTE_DIR}/${ARCHIVE_NAME}" \
    "${LOCAL_DIR}/"
  scp -i "${SSH_KEY}" -o BatchMode=yes \
    "${PXC_USER}@${PXC_HOST}:${REMOTE_DIR}/${ARCHIVE_NAME}.sha256" \
    "${LOCAL_DIR}/"

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
  find "${LOCAL_DIR}" -type f -name 'pxc-*.tar.gz*' -mtime +2 -delete

  echo "[CLEANUP] remote retention"
  ssh -i "${SSH_KEY}" -o BatchMode=yes "${PXC_USER}@${PXC_HOST}" \
    "sudo find '${REMOTE_DIR}' -maxdepth 2 -type f -name 'pxc-*.tar.gz*' -mtime +2 -delete"

  echo "[END] $(date -Is)"
} >> "${LOGFILE}" 2>&1 || STATUS=$?

if [ "${STATUS}" -eq 0 ]; then
  MESSAGE="[SUCCESS] PXC backup command completed on $(hostname) at $(date -Is). mode=${MODE}, s3=s3://${S3_BUCKET}/${S3_PREFIX}/${ARCHIVE_NAME}, log=${LOGFILE}"
else
  MESSAGE="[FAILED] PXC backup command failed on $(hostname) at $(date -Is). mode=${MODE}, log=${LOGFILE}"
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
chmod 700 /home/ubuntu/backup-test/pxc-backup.sh
```

---

## 9. 수동 실행

full backup:

```bash
/home/ubuntu/backup-test/pxc-backup.sh full
echo $?
```

manual backup:

```bash
/home/ubuntu/backup-test/pxc-backup.sh manual
echo $?
```

로그 확인:

```bash
tail -n 160 /home/ubuntu/backup-test/logs/pxc-backup-$(date +%Y%m%d).log
```

S3 확인:

```bash
aws s3 ls s3://team2-pxc-backup/onprem-pxc/full/ --recursive --summarize
aws s3 ls s3://team2-pxc-backup/onprem-pxc/manual/ --recursive --summarize
```

성공 기준:

- PXC node SSH 성공
- `xtrabackup --version` 출력
- `wsrep_*` 상태 출력
- `xtrabackup_checkpoints` 존재
- `xtrabackup_galera_info` 존재
- tar.gz 생성
- sha256 검증 성공
- S3 업로드 확인
- Slack `[SUCCESS]` 수신

---

## 10. cron 등록

PoC/발표 기준:

```cron
30 3 * * * /home/ubuntu/backup-test/pxc-backup.sh full
```

중요 변경 전 수동:

```bash
/home/ubuntu/backup-test/pxc-backup.sh manual
```

주의:

- Object backup, etcd backup과 시간 분리
- DB 부하가 낮은 시간대 선택
- PXC node maintenance와 겹치지 않게 배치
- 복구 자동화 금지

---

## 11. 복구 정책

현재 단계:

- 복구 실습 미수행
- 절차와 주의사항만 문서화
- 운영 cluster in-place 복구 금지

복구 기본 흐름:

```text
S3에서 backup archive 다운로드
    -> sha256 검증
    -> tar.gz 해제
    -> xtrabackup --prepare
    -> 격리 VM 또는 신규 PXC 노드에 restore
    -> MySQL 기동
    -> 데이터 정합성 확인
    -> PXC cluster 재구성 또는 ProxySQL cutover 검토
```

복구 시 고려:

- `xtrabackup --prepare` 필요
- restore 전 MySQL 중지 필요
- 기존 datadir 보존 필요
- datadir owner `mysql:mysql` 확인 필요
- PXC cluster에 재합류 시 SST/IST 발생 가능
- ProxySQL writer/read hostgroup 재확인 필요
- 앱 접속은 PXC 직접 연결이 아니라 ProxySQL endpoint 유지

복구 검증 기준:

- 별도 test VM 또는 isolated PXC 환경
- 운영 PXC에 직접 덮어쓰기 금지
- restore 후 row count/schema smoke test
- ProxySQL 연결 smoke test
- 실제 검증은 추후 DR drill 항목

---

## 12. 추후 개선

Incremental backup:

- weekly full + daily incremental
- `--incremental-basedir` 또는 history 기반 구성
- 복구 시 순서 적용 필요

PITR:

- binlog 활성화
- binlog S3 업로드
- `mysqlbinlog --stop-datetime` 기준 특정 시점 replay
- NTP/timezone 정합성 중요

backup-runner:

- bastion cron에서 전용 VM으로 이전
- SSH key와 AWS credential 분리
- systemd timer 전환

보안:

- SSE-KMS 적용
- backup 전용 IAM role
- DB backup credential rotation
- S3 bucket access logging 검토

---

## 13. 보안 기준

주의:

- DB backup에는 개인정보/업무 데이터 포함 가능
- tar.gz, sha256 외부 노출 금지
- Git 저장소 커밋 금지
- Slack에 DB 내용 출력 금지
- 백업 계정 password 문서화 금지

파일 권한:

```bash
chmod 700 /home/ubuntu/backup-test/pxc-backup.sh
chmod 600 /home/ubuntu/backup-test/backup.env
chmod 600 /home/ubuntu/.ssh/kosa_iac
sudo chmod 600 /root/.pxc-backup.cnf
```

---

## 14. 참고

- Percona XtraBackup: <https://docs.percona.com/percona-xtrabackup/8.0/index.html>
- XtraBackup 권한: <https://docs.percona.com/percona-xtrabackup/8.0/privileges.html>
- XtraBackup `--galera-info`:
  <https://docs.percona.com/percona-xtrabackup/8.0/xtrabackup-option-reference.html>
- Percona XtraDB Cluster: <https://docs.percona.com/percona-xtradb-cluster/8.0/intro.html>
