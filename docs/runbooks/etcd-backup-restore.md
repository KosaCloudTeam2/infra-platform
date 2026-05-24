# etcd 백업/복구 Runbook

> Status: Draft 범위: 온프레미스 kubeadm Kubernetes etcd snapshot 백업 기준. AWS EKS control plane
> etcd는 AWS 관리 영역이므로 직접 snapshot 대상에서 제외함.

---

## 1. 적용 범위

적용 대상:

- 온프레미스 Kubernetes control-plane
- kubeadm static pod 기반 etcd
- bastion에서 control-plane SSH 접속 가능 구조
- control-plane IP 예시: `172.16.23.10`
- bastion SSH key 예시: `/home/ubuntu/.ssh/kosa_iac`

제외 대상:

- AWS EKS etcd 직접 백업
- Ceph RGW object 백업
- PXC/MySQL 데이터 백업
- PV/RBD/CephFS 데이터 백업
- Harbor image/object 백업

> EKS control plane의 etcd는 AWS 관리형 구성 요소임. EKS는 etcd snapshot 대신 GitOps, Velero, 앱
> 데이터 백업, S3/RDS/DynamoDB 같은 데이터 계층 백업으로 관리함.

---

## 2. 권장 구조

권장 방식:

```text
bastion cron
    -> SSH to control-plane
    -> control-plane에서 etcd snapshot 생성
    -> snapshot status/sha256 검증
    -> bastion으로 snapshot 전송
    -> bastion에서 AWS S3 업로드
    -> Slack 알림
```

설계 이유:

- etcd 인증서/키를 bastion으로 복사하지 않음
- snapshot 생성은 control-plane에서 수행
- AWS 인증, S3 업로드, Slack 알림은 bastion에서 수행
- 기존 Object backup 운영 방식과 유사한 실행 흐름
- backup-runner VM 도입 전까지 현실적인 자동화 구조

권장 저장소:

```text
s3://team2-etcd-backup/onprem-k8s/daily/
s3://team2-etcd-backup/onprem-k8s/weekly/
s3://team2-etcd-backup/onprem-k8s/manual/
```

mode 의미:

- `daily`, `weekly`, `manual`은 서로 다른 snapshot 방식이 아님
- 세 mode 모두 동일한 etcd full snapshot 생성
- mode 차이는 S3 prefix, 파일명, 보관 정책 구분
- cron에서 실행 인자로 `daily` 또는 `weekly` 지정
- 중요한 작업 전에는 사람이 `manual` 인자로 직접 실행

구분 기준:

| mode     | 실행 주체 | 실행 방식               | 저장 prefix          | 의미                |
| :------- | :-------- | :---------------------- | :------------------- | :------------------ |
| `daily`  | cron      | `etcd-backup.sh daily`  | `onprem-k8s/daily/`  | 짧은 주기 복구 지점 |
| `weekly` | cron      | `etcd-backup.sh weekly` | `onprem-k8s/weekly/` | 장기 보관 복구 지점 |
| `manual` | 운영자    | `etcd-backup.sh manual` | `onprem-k8s/manual/` | 변경 전 수동 기준점 |

Object backup bucket과 분리하는 이유:

- etcd snapshot에 Kubernetes Secret 포함 가능
- 클러스터 전체 상태 포함
- 앱 업로드 객체보다 높은 민감도
- 접근 권한/보관 정책 분리 필요

---

## 3. 용량과 주기

용량 기준:

- 소규모 kubeadm 클러스터: 수십 MB 가능성 높음
- CRD/Helm/ArgoCD 리소스 많음: 수십~수백 MB 가능
- 대규모 클러스터: GB 단위 가능

실측 기준:

```bash
sudo ls -lh /var/backups/etcd/*.db
sudo du -h /var/backups/etcd/*.db
```

권장 주기:

| 구분         | 주기              | 보관 기준                | 설명                            |
| :----------- | :---------------- | :----------------------- | :------------------------------ |
| daily        | 매일 03:10        | 최근 7~14일              | 기본 운영 백업                  |
| weekly       | 매주 월요일 03:20 | 최근 4~8주               | 장기 복구 지점                  |
| manual       | 중요 작업 전      | 발표/변경 기간 동안 보관 | upgrade/대규모 변경 전 snapshot |
| restore test | 필요 시 수동      | 별도 test 환경           | 운영 cluster 직접 복구 금지     |

PoC 기준 추천:

- `daily`: 14일 보관
- `weekly`: 8주 보관
- `manual`: 발표 종료 후 정리

용량이 부담되면:

- daily 7일로 축소
- weekly 4주로 축소
- manual snapshot만 장기 보관
- S3 Lifecycle로 오래된 weekly/manual snapshot Glacier 전환

---

## 4. 사전 확인

## 4.1 bastion 확인

현재 context 확인:

```bash
kubectl config current-context
# 기대값: kubernetes-admin@kubernetes

kubectl get nodes -o wide
```

bastion에 etcd 인증서가 없는 상태가 정상:

```bash
ls -l /etc/kubernetes/pki/etcd/
sudo find /etc/kubernetes -maxdepth 4 -type f | grep -E 'etcd|apiserver-etcd'
```

예상 결과:

- `/etc/kubernetes/pki/etcd/` 없음
- `/etc/kubernetes` 없음
- `~/.kube/config`만 존재

의미:

- bastion은 Kubernetes API client 역할
- etcd 직접 snapshot 권한 없음
- etcd key를 bastion으로 복사하지 않음

## 4.2 control-plane SSH 확인

bastion에서 control-plane 접속:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10
```

자동화용 sudo 확인:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10 \
  'sudo -n true && echo "sudo ok"'
```

etcd static pod와 인증서 확인:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10 \
  'sudo ls -l /etc/kubernetes/manifests/etcd.yaml /etc/kubernetes/pki/etcd/'
```

etcdctl/etcdutl 확인:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10 \
  'etcdctl version; if command -v etcdutl >/dev/null 2>&1; then etcdutl version; else echo "etcdutl not found"; fi'
```

주의:

- `etcdctl`은 snapshot 생성에 필요
- `etcdutl`은 snapshot status/restore 검증에 권장
- control-plane etcd version과 호환되는 도구 사용 권장
- host에 도구가 없으면 4.3 기준으로 설치 또는 container fallback 선택

etcd image version 확인:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10 \
  "sudo awk '/image:.*etcd/{print}' /etc/kubernetes/manifests/etcd.yaml"
```

현재 확인 결과 해석:

- `sudo ok`: bastion cron 자동화 가능
- `/etc/kubernetes/manifests/etcd.yaml` 존재: kubeadm static pod etcd 확인
- `/etc/kubernetes/pki/etcd/` 존재: snapshot용 인증서 control-plane에 존재
- `etcdctl: command not found`: host OS에 etcd client 미설치
- `etcdutl not found`: host OS에 restore/status 도구 미설치

## 4.3 etcdctl 준비 방식

선택 기준:

| 방식                          | 권장도 | 설명                                                              |
| :---------------------------- | :----- | :---------------------------------------------------------------- |
| matching binary 설치          | 높음   | control-plane host에 etcd version과 맞는 `etcdctl`/`etcdutl` 설치 |
| etcd container 내부 도구 사용 | 임시   | static pod container에 포함된 `etcdctl` 사용                      |
| bastion으로 인증서 복사       | 낮음   | etcd key 노출 범위 증가. 기본 금지                                |

권장 방식: control-plane에 matching binary 설치.

버전 확인:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10 \
  "sudo awk '/image:.*etcd/{print \$2}' /etc/kubernetes/manifests/etcd.yaml"
```

확인 예시:

```text
registry.k8s.io/etcd:3.5.15-0
```

설치 명령 실행 위치:

- control-plane `172.16.23.10`
- bastion에서 SSH 접속 후 실행

control-plane 접속:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10
```

설치 예시:

```bash
# registry.k8s.io/etcd:3.5.15-0 기준
ETCD_VER="3.5.15"

curl -L "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VER}/etcd-v${ETCD_VER}-linux-amd64.tar.gz" \
  -o "etcd-v${ETCD_VER}-linux-amd64.tar.gz"

tar -xzf "etcd-v${ETCD_VER}-linux-amd64.tar.gz"

sudo install -m 0755 "etcd-v${ETCD_VER}-linux-amd64/etcdctl" /usr/local/bin/etcdctl
sudo install -m 0755 "etcd-v${ETCD_VER}-linux-amd64/etcdutl" /usr/local/bin/etcdutl

etcdctl version
etcdutl version

rm -rf "etcd-v${ETCD_VER}-linux-amd64" "etcd-v${ETCD_VER}-linux-amd64.tar.gz"
```

주의:

- `ETCD_VER`는 `etcd.yaml` image tag 기준
- image tag가 `3.5.12-0`이면 upstream release는 보통 `v3.5.12`
- 인터넷 다운로드 불가 환경이면 운영 PC에서 파일 다운로드 후 control-plane으로 전송
- `apt install etcd-client`는 version mismatch 가능성 확인 필요
- `/usr/local/bin` 설치 후 다운로드 tarball과 압축 해제 디렉터리는 삭제 가능

임시 방식: etcd container 내부 도구 사용.

container 확인:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10 \
  'sudo crictl ps --name etcd'
```

확인 기준:

- `NAME`: `etcd`
- `STATE`: `Running`
- `POD`: `etcd-k8s-cp1` 같은 control-plane etcd pod

`crictl` endpoint 경고:

```text
runtime connect using default endpoints ... deprecated
image connect using default endpoints ... deprecated
```

의미:

- 명령 실패 아님
- `crictl`이 container runtime endpoint를 자동 탐색했다는 경고
- host `etcdctl`/`etcdutl` 설치 완료 상태면 container fallback 경로는 필수 아님

경고 제거가 필요하면 control-plane에서 endpoint 설정:

```bash
sudo tee /etc/crictl.yaml >/dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo crictl ps --name etcd
```

container 내부 `etcdctl` 확인:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10 \
  'ETCD_CONTAINER_ID="$(sudo crictl ps --name etcd -q | head -n 1)"; sudo crictl exec "${ETCD_CONTAINER_ID}" etcdctl version'
```

container fallback snapshot 수동 예시:

```bash
ssh -i /home/ubuntu/.ssh/kosa_iac ubuntu@172.16.23.10

sudo -i
mkdir -p /var/backups/etcd

SNAPSHOT_NAME="etcd-snapshot-manual-$(date +%Y%m%d-%H%M%S).db"
ETCD_CONTAINER_ID="$(crictl ps --name etcd -q | head -n 1)"

crictl exec "${ETCD_CONTAINER_ID}" sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health -w table"

crictl exec "${ETCD_CONTAINER_ID}" sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/${SNAPSHOT_NAME}"

if crictl exec "${ETCD_CONTAINER_ID}" sh -c "command -v etcdutl >/dev/null 2>&1"; then
  crictl exec "${ETCD_CONTAINER_ID}" sh -c "etcdutl snapshot status /var/lib/etcd/${SNAPSHOT_NAME} -w table"
else
  crictl exec "${ETCD_CONTAINER_ID}" sh -c "ETCDCTL_API=3 etcdctl \
    snapshot status /var/lib/etcd/${SNAPSHOT_NAME} -w table"
fi

mv "/var/lib/etcd/${SNAPSHOT_NAME}" "/var/backups/etcd/${SNAPSHOT_NAME}"
sha256sum "/var/backups/etcd/${SNAPSHOT_NAME}" > "/var/backups/etcd/${SNAPSHOT_NAME}.sha256"
ls -lh "/var/backups/etcd/${SNAPSHOT_NAME}"*
du -h "/var/backups/etcd/${SNAPSHOT_NAME}"*
```

주의:

- `/var/lib/etcd`는 etcd data hostPath
- container fallback에서는 snapshot 파일을 잠깐 `/var/lib/etcd`에 생성
- 생성 직후 `/var/backups/etcd`로 이동
- `/var/lib/etcd`에 snapshot 파일 장기 방치 금지
- bastion으로 `scp` 전송하려면 `chown ubuntu:ubuntu /var/backups/etcd/${SNAPSHOT_NAME}*` 필요
- control-plane 내부 보관만 할 경우 `root:root` 유지 가능
- `etcdctl snapshot status`의 `Deprecated: Use etcdutl snapshot status instead.` 문구는 실패가 아님
- 장기 자동화는 host에 matching `etcdctl`/`etcdutl` 설치 권장

수동 테스트 snapshot 삭제:

```bash
test -n "${SNAPSHOT_NAME:-}"
rm -f "/var/backups/etcd/${SNAPSHOT_NAME}" "/var/backups/etcd/${SNAPSHOT_NAME}.sha256"
ls -lh /var/backups/etcd/
```

삭제 기준:

- S3 업로드하지 않을 임시 검증 snapshot
- 자동화 스크립트 검증 전 container fallback 동작 확인용 snapshot
- 복구 기준점으로 보관하지 않을 snapshot

변수가 사라진 경우:

```bash
ls -lh /var/backups/etcd/

rm -f /var/backups/etcd/etcd-snapshot-manual-YYYYMMDD-HHMMSS.db \
      /var/backups/etcd/etcd-snapshot-manual-YYYYMMDD-HHMMSS.db.sha256
```

주의:

- `SNAPSHOT_NAME`이 비어 있으면 삭제 명령 실행 금지
- 삭제 전 `ls -lh /var/backups/etcd/`로 실제 파일명 확인
- directory 삭제 명령 사용 금지

보관 기준:

- S3 업로드 완료 전 원본
- 발표/작업 전 manual snapshot
- 장애 분석에 필요한 snapshot

---

## 5. AWS S3 bucket 준비

AWS CLI 실행 위치:

- bastion
- AWS CLI 인증 완료 상태
- `aws sts get-caller-identity` 성공 상태

bucket 생성:

```bash
export AWS_REGION=ap-northeast-2

aws s3api create-bucket \
  --bucket team2-etcd-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}
```

Versioning:

```bash
aws s3api put-bucket-versioning \
  --bucket team2-etcd-backup \
  --versioning-configuration Status=Enabled
```

Public Access Block:

```bash
aws s3api put-public-access-block \
  --bucket team2-etcd-backup \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

기본 암호화:

```bash
aws s3api put-bucket-encryption \
  --bucket team2-etcd-backup \
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

확인:

```bash
aws s3api get-bucket-versioning --bucket team2-etcd-backup
aws s3api get-public-access-block --bucket team2-etcd-backup
aws s3api get-bucket-encryption --bucket team2-etcd-backup
```

---

## 6. S3 Lifecycle

`etcd-lifecycle.json`:

```json
{
  "Rules": [
    {
      "ID": "expire-daily-etcd-snapshots",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-k8s/daily/"
      },
      "Expiration": {
        "Days": 14
      }
    },
    {
      "ID": "archive-weekly-etcd-snapshots",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-k8s/weekly/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 120
      }
    },
    {
      "ID": "archive-manual-etcd-snapshots",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "onprem-k8s/manual/"
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
      "ID": "abort-incomplete-multipart-etcd",
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
  --bucket team2-etcd-backup \
  --lifecycle-configuration file://etcd-lifecycle.json
```

확인:

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket team2-etcd-backup
```

주의:

- `daily/`: 짧은 복구 지점, 14일 후 삭제
- `weekly/`: 30일 후 Glacier, 120일 후 삭제
- `manual/`: 30일 후 Glacier, 365일 후 삭제
- 발표/심사 기간에는 `manual/` 삭제 시점 조정 가능

---

## 7. backup.env

기존 Object backup의 `/home/ubuntu/backup-test/backup.env` 재사용 가능.

필수:

```bash
AWS_DEFAULT_REGION="ap-northeast-2"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/REPLACE/REPLACE/REPLACE"
```

주의:

- etcd 인증서/키를 `backup.env`에 넣지 않음
- AWS CLI 인증이 이미 성공하면 AWS Access Key/Secret Key를 넣지 않음
- Slack Webhook URL은 Secret 취급
- 파일 권한 `600` 유지

권한:

```bash
chmod 600 /home/ubuntu/backup-test/backup.env
```

---

## 8. 백업 스크립트

파일:

```text
/home/ubuntu/backup-test/etcd-backup.sh
```

스크립트:

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/home/ubuntu/backup-test"
ENV_FILE="${WORKDIR}/backup.env"
LOGDIR="${WORKDIR}/logs"
LOCAL_DIR="${WORKDIR}/etcd"

SSH_KEY="/home/ubuntu/.ssh/kosa_iac"
CP_USER="ubuntu"
CP_HOST="172.16.23.10"
REMOTE_DIR="/var/backups/etcd"

S3_BUCKET="team2-etcd-backup"
MODE="${1:-daily}"

case "${MODE}" in
  daily|weekly|manual)
    ;;
  *)
    echo "Usage: $0 [daily|weekly|manual]" >&2
    exit 2
    ;;
esac

S3_PREFIX="onprem-k8s/${MODE}"
TS="$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_NAME="etcd-snapshot-${MODE}-${TS}.db"
LOGFILE="${LOGDIR}/etcd-backup-$(date +%Y%m%d).log"

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
  echo "[CONTROL_PLANE] ${CP_USER}@${CP_HOST}"
  echo "[SNAPSHOT] ${SNAPSHOT_NAME}"

  echo "[CHECK] AWS identity"
  aws sts get-caller-identity >/dev/null

  echo "[CHECK] S3 bucket"
  aws s3api head-bucket --bucket "${S3_BUCKET}"

  echo "[CHECK] SSH and sudo"
  ssh -i "${SSH_KEY}" -o BatchMode=yes "${CP_USER}@${CP_HOST}" \
    'sudo -n true && sudo test -f /etc/kubernetes/manifests/etcd.yaml && sudo test -d /etc/kubernetes/pki/etcd'

  echo "[SNAPSHOT] create on control-plane"
  ssh -i "${SSH_KEY}" -o BatchMode=yes "${CP_USER}@${CP_HOST}" \
    "sudo env SNAPSHOT_NAME='${SNAPSHOT_NAME}' REMOTE_DIR='${REMOTE_DIR}' REMOTE_OWNER='${CP_USER}:${CP_USER}' bash -s" <<'REMOTE'
set -euo pipefail

mkdir -p "${REMOTE_DIR}"
SNAPSHOT="${REMOTE_DIR}/${SNAPSHOT_NAME}"
ETCD_ARGS="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

if command -v etcdctl >/dev/null 2>&1; then
  ETCDCTL_API=3 etcdctl ${ETCD_ARGS} endpoint health -w table
  ETCDCTL_API=3 etcdctl ${ETCD_ARGS} snapshot save "${SNAPSHOT}"

  if command -v etcdutl >/dev/null 2>&1; then
    etcdutl snapshot status "${SNAPSHOT}" -w table
  else
    ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT}" -w table
  fi
else
  ETCD_CONTAINER_ID="$(crictl ps --name etcd -q | head -n 1)"
  if [ -z "${ETCD_CONTAINER_ID}" ]; then
    echo "etcdctl not found on host and etcd container not found" >&2
    exit 1
  fi

  CONTAINER_SNAPSHOT="/var/lib/etcd/${SNAPSHOT_NAME}"

  crictl exec "${ETCD_CONTAINER_ID}" sh -c "ETCDCTL_API=3 etcdctl ${ETCD_ARGS} endpoint health -w table"
  crictl exec "${ETCD_CONTAINER_ID}" sh -c "ETCDCTL_API=3 etcdctl ${ETCD_ARGS} snapshot save '${CONTAINER_SNAPSHOT}'"

  if crictl exec "${ETCD_CONTAINER_ID}" sh -c "command -v etcdutl >/dev/null 2>&1"; then
    crictl exec "${ETCD_CONTAINER_ID}" sh -c "etcdutl snapshot status '${CONTAINER_SNAPSHOT}' -w table"
  else
    crictl exec "${ETCD_CONTAINER_ID}" sh -c "ETCDCTL_API=3 etcdctl snapshot status '${CONTAINER_SNAPSHOT}' -w table"
  fi

  mv "${CONTAINER_SNAPSHOT}" "${SNAPSHOT}"
fi

cd "${REMOTE_DIR}"
sha256sum "${SNAPSHOT_NAME}" > "${SNAPSHOT_NAME}.sha256"
chown "${REMOTE_OWNER}" "${SNAPSHOT}" "${SNAPSHOT}.sha256"
REMOTE

  echo "[COPY] control-plane -> bastion"
  scp -i "${SSH_KEY}" -o BatchMode=yes \
    "${CP_USER}@${CP_HOST}:${REMOTE_DIR}/${SNAPSHOT_NAME}" \
    "${LOCAL_DIR}/"
  scp -i "${SSH_KEY}" -o BatchMode=yes \
    "${CP_USER}@${CP_HOST}:${REMOTE_DIR}/${SNAPSHOT_NAME}.sha256" \
    "${LOCAL_DIR}/"

  echo "[VERIFY] local files"
  ls -lh "${LOCAL_DIR}/${SNAPSHOT_NAME}" "${LOCAL_DIR}/${SNAPSHOT_NAME}.sha256"
  (cd "${LOCAL_DIR}" && sha256sum -c "${SNAPSHOT_NAME}.sha256")

  echo "[UPLOAD] S3"
  aws s3 cp "${LOCAL_DIR}/${SNAPSHOT_NAME}" \
    "s3://${S3_BUCKET}/${S3_PREFIX}/${SNAPSHOT_NAME}" \
    --sse AES256
  aws s3 cp "${LOCAL_DIR}/${SNAPSHOT_NAME}.sha256" \
    "s3://${S3_BUCKET}/${S3_PREFIX}/${SNAPSHOT_NAME}.sha256" \
    --sse AES256

  echo "[VERIFY] S3"
  echo "[VERIFY] s3://${S3_BUCKET}/${S3_PREFIX}/${SNAPSHOT_NAME}"
  aws s3api head-object \
    --bucket "${S3_BUCKET}" \
    --key "${S3_PREFIX}/${SNAPSHOT_NAME}" \
    --query '{Size:ContentLength,LastModified:LastModified,VersionId:VersionId}'
  echo "[VERIFY] s3://${S3_BUCKET}/${S3_PREFIX}/${SNAPSHOT_NAME}.sha256"
  aws s3api head-object \
    --bucket "${S3_BUCKET}" \
    --key "${S3_PREFIX}/${SNAPSHOT_NAME}.sha256" \
    --query '{Size:ContentLength,LastModified:LastModified,VersionId:VersionId}'

  echo "[CLEANUP] local retention"
  find "${LOCAL_DIR}" -type f -name 'etcd-snapshot-*.db*' -mtime +2 -delete

  echo "[CLEANUP] remote retention"
  ssh -i "${SSH_KEY}" -o BatchMode=yes "${CP_USER}@${CP_HOST}" \
    "sudo find '${REMOTE_DIR}' -type f -name 'etcd-snapshot-*.db*' -mtime +2 -delete"

  echo "[END] $(date -Is)"
} >> "${LOGFILE}" 2>&1 || STATUS=$?

if [ "${STATUS}" -eq 0 ]; then
  MESSAGE="[SUCCESS] etcd backup command completed on $(hostname) at $(date -Is). mode=${MODE}, s3=s3://${S3_BUCKET}/${S3_PREFIX}/${SNAPSHOT_NAME}, log=${LOGFILE}"
else
  MESSAGE="[FAILED] etcd backup command failed on $(hostname) at $(date -Is). mode=${MODE}, log=${LOGFILE}"
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
chmod 700 /home/ubuntu/backup-test/etcd-backup.sh
```

---

## 9. 수동 실행 검증

daily mode:

```bash
/home/ubuntu/backup-test/etcd-backup.sh daily
echo $?
```

manual mode:

```bash
/home/ubuntu/backup-test/etcd-backup.sh manual
echo $?
```

로그 확인:

```bash
tail -n 120 /home/ubuntu/backup-test/logs/etcd-backup-$(date +%Y%m%d).log
```

S3 확인:

```bash
aws s3 ls s3://team2-etcd-backup/onprem-k8s/daily/ --recursive --summarize
aws s3 ls s3://team2-etcd-backup/onprem-k8s/manual/ --recursive --summarize
```

성공 기준:

- `[CHECK] AWS identity` 성공
- `[CHECK] SSH and sudo` 성공
- `endpoint health` 성공
- `snapshot save` 성공
- `snapshot status` table 출력
- `sha256sum -c` 성공
- S3 snapshot 업로드 확인
- S3 `.sha256` 업로드 확인
- Slack `[SUCCESS]` 수신

주의:

- `aws s3 ls s3://bucket/prefix/file.db`는 exact key가 아니라 prefix 조회처럼 보일 수 있음
- `file.db.sha256`이 `file.db` prefix에 함께 잡혀 `.sha256`이 두 번 보일 수 있음
- 실제 중복 여부는 `aws s3 ls ... --recursive --summarize`의 object count 기준 확인
- 스크립트의 S3 exact key 확인은 `aws s3api head-object` 기준 권장

---

## 10. cron 등록

테스트용 1회 실행 후 등록.

cron이 실행 mode를 결정함.

- 매일 실행: `daily`
- 매주 실행: `weekly`
- 수동 실행: `manual`
- 백업 방식 자체는 모두 동일한 etcd full snapshot

권장 cron:

```cron
10 3 * * * /home/ubuntu/backup-test/etcd-backup.sh daily
20 3 * * 1 /home/ubuntu/backup-test/etcd-backup.sh weekly
```

등록:

```bash
crontab -e
crontab -l
```

주의:

- Object backup cron과 10분 이상 분리
- control-plane 작업 시간과 겹치지 않게 배치
- cron timezone은 bastion system timezone 기준
- 복구 작업 자동화 금지

---

## 11. 복구 원칙

복구는 자동화하지 않음.

복구가 필요한 상황:

- etcd quorum 손실
- control-plane 전체 손상
- Kubernetes API object 심각한 오염
- GitOps rollback만으로 복구 불가

복구 전 확인:

- snapshot 파일 확보
- `.sha256` 검증
- snapshot status 확인
- 현재 cluster 상태 백업
- 정비 시간 확보
- control-plane 구성 정보 확보
- restore 대상 노드 확정

주의:

- etcd restore는 cluster 상태를 snapshot 시점으로 되돌림
- Kubernetes Secret도 snapshot 시점으로 되돌림
- PV 데이터 자체는 복구하지 않음
- DB 데이터 자체는 복구하지 않음
- HA control-plane restore는 단일 노드보다 위험도 높음
- Kubernetes informer/cache 문제 방지를 위해 revision bump/mark compacted 검토 필요

복구 명령은 별도 DR 작업으로 관리함.

참고 기준:

- `etcdutl snapshot restore`
- `--bump-revision`
- `--mark-compacted`
- kubeadm static pod manifest 조정
- 모든 control-plane member 동일 snapshot 기준 재구성

---

## 12. 보안 기준

민감도:

- etcd snapshot은 Kubernetes Secret 포함 가능
- cluster-admin 수준 민감 데이터로 취급
- 공개 채팅/스크린샷 노출 금지
- Git 저장소 커밋 금지

권한:

- S3 bucket public access block 필수
- bucket write 권한 최소화
- restore read 권한 제한
- Slack 메시지에 snapshot 파일 내용/Secret 출력 금지

파일 권한:

```bash
chmod 700 /home/ubuntu/backup-test/etcd-backup.sh
chmod 600 /home/ubuntu/backup-test/backup.env
chmod 600 /home/ubuntu/.ssh/kosa_iac
```

장기 개선:

- backup-runner VM 분리
- SSH key rotation
- SSE-KMS 전환
- IAM Role 기반 인증
- restore drill 전용 test cluster 구성

---

## 13. 검증 체크리스트

| 검증 항목       | 명령/방법                                | 기대 결과                     |
| :-------------- | :--------------------------------------- | :---------------------------- |
| bastion context | `kubectl config current-context`         | `kubernetes-admin@kubernetes` |
| SSH             | `ssh -i ... ubuntu@172.16.23.10`         | 접속 성공                     |
| sudo            | `sudo -n true`                           | password prompt 없음          |
| etcd manifest   | `/etc/kubernetes/manifests/etcd.yaml`    | 파일 존재                     |
| etcd cert       | `/etc/kubernetes/pki/etcd/`              | 인증서/키 존재                |
| endpoint health | host `etcdctl` 또는 container fallback   | healthy                       |
| snapshot 생성   | host `etcdctl` 또는 container fallback   | `.db` 파일 생성               |
| snapshot 검증   | `etcdutl` 또는 `etcdctl snapshot status` | revision/hash/size 출력       |
| checksum        | `sha256sum -c`                           | OK                            |
| S3 업로드       | `aws s3 ls s3://team2-etcd-backup/...`   | snapshot 표시                 |
| Slack           | Webhook message                          | SUCCESS/FAILED 수신           |

---

## 14. 참고

- Kubernetes etcd 운영 문서:
  <https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/>
- etcd disaster recovery 문서: <https://etcd.io/docs/v3.6/op-guide/recovery/>
