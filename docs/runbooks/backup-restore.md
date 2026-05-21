# 백업/복구 Runbook

> Status: Unverified 범위: 현재 우선순위는 **Object 백업**과 **Thanos 장기 지표 백업**임.
> DB/PVC/etcd/GitOps/Secret 전체 백업은 현재 범위에서 제외하고, 한계만 명시함.

---

## 1. 백업 범위와 제외 범위

## 1.1 현재 우선 적용 범위

| 구분            | 대상                       | 현재 저장소     | 백업 대상  | 전략                      |
| :-------------- | :------------------------- | :-------------- | :--------- | :------------------------ |
| Harbor Object   | Harbor registry blob       | Ceph RGW bucket | AWS S3     | 동일 key copy-only        |
| App/Object      | 사용자 업로드/서비스 객체  | Ceph RGW bucket | AWS S3     | 동일 key copy-only        |
| Thanos Metrics  | Prometheus 장기 지표 block | Ceph RGW bucket | AWS S3     | active bucket 백업본 생성 |
| Glacier Archive | 오래된 백업본              | AWS S3          | S3 Glacier | S3 Lifecycle로 전환       |

## 1.2 현재 제외 범위

| 구분                | 제외 사유                                                                            | 한계                                                                         |
| :------------------ | :----------------------------------------------------------------------------------- | :--------------------------------------------------------------------------- |
| DB 백업             | 현재 PXC 3노드 + Ceph RBD(`team2-rbd-block`) 기반으로 노드/디스크 장애 대응을 우선함 | RBD replica는 논리 삭제/오염 복구용 백업은 아님. 추후 XtraBackup/binlog 필요 |
| etcd/Velero         | 이번 우선 목표가 Object/Thanos 백업임                                                | 클러스터 전체 재해복구는 별도 Runbook 필요                                   |
| GitOps/Secret       | Git 저장소와 Secret 관리 정책은 별도 주제                                            | Secret 평문 백업 금지. SOPS/SealedSecret/ExternalSecret 검토 필요            |
| pfSense/Proxmox/IaC | 인프라 설정 백업은 별도 운영 절차                                                    | config.xml, Terraform state 등 별도 보관 필요                                |

> 발표 시 표현: 현재는 안전한 **copy-only 백업** 단계이며, 검증 후 오래된 객체를 Ceph에서 삭제하고
> AWS S3를 직접 조회하는 **Tiered Storage** 구조로 확장한다.

---

## 2. 설계 원칙

## 2.1 Object key는 동일하게 유지

AWS S3에서 직접 조회할 가능성이 있는 객체는 Ceph RGW와 AWS S3의 object key를 동일하게 유지함.

예:

```text
Ceph RGW
bucket: harbor-registry
key: docker/registry/v2/blobs/sha256/...

AWS S3
bucket: team2-harbor-registry-backup
key: docker/registry/v2/blobs/sha256/...
```

앱 객체도 동일 원칙을 적용함.

```text
Ceph RGW key: uploads/2026/05/image.png
AWS S3 key:  uploads/2026/05/image.png
```

이렇게 해야 향후 DB 메타데이터를 아래처럼 단순화할 수 있음.

```text
storage_type = ceph | s3
bucket       = <bucket_name>
object_key   = <same_key>
```

## 2.2 초기에는 Ceph 원본 삭제 금지

초기 단계는 copy-only임.

```text
Ceph RGW 원본 유지
AWS S3 백업본 생성
```

Ceph 원본 삭제는 아래 조건을 만족한 뒤에만 고려함.

1. AWS S3 복사 성공
2. object count/size/checksum 검증
3. 애플리케이션이 AWS S3 객체를 직접 조회 가능
4. DB 메타데이터로 저장 위치 구분 가능
5. Glacier 전환 객체는 실시간 조회 대상에서 제외
6. rollback 절차 존재

## 2.3 Thanos active bucket은 Glacier로 보내지 않음

Thanos가 실제 조회하는 active bucket은 Ceph RGW에 둠.

```text
Prometheus -> Thanos Sidecar -> Ceph RGW thanos-metrics
```

AWS S3/Glacier는 active bucket의 백업본에만 적용함.

```text
Ceph RGW thanos-metrics
  -> AWS S3 team2-thanos-metrics-backup
  -> Lifecycle -> Glacier
```

## 2.4 백업 경로는 서비스 경로와 분리

백업 경로가 Kubernetes/MetalLB에 의존하면 K8s 장애 시 Ceph RGW가 정상이어도 백업이 실패할 수 있음.

현재 기본 백업 경로:

```text
bastion VM
  -> 10.10.10.11:7480 (Ceph RGW 직접 접근)
  -> AWS S3 backup bucket
```

Deprecated 경로:

```text
Kubernetes / EKS / 관리망
  -> 172.16.23.60:7480 (MetalLB RGW bridge)
  -> 10.10.10.11:7480 (Ceph RGW)
```

운영 원칙:

- 기본 실행 위치: bastion VM
- 기본 RGW endpoint: `http://10.10.10.11:7480`
- MetalLB RGW bridge: 신규 백업 경로로 사용하지 않음
- MetalLB RGW bridge 사용 범위: 기존 문서 호환, 임시 연결 확인, 마이그레이션 전 경로
- Kubernetes CronJob: 편의 자동화 후보, 주 백업 경로 아님
- 향후 개선: backup-runner VM 분리, 백업 전용 역할/키/스케줄 관리

---

## 3. 예시 bucket 이름

아래 이름은 예시임. 실제 계정/프로젝트 정책에 맞게 변경 가능함.

| 용도                     | Ceph RGW bucket 예시  | AWS S3 bucket 예시                                               |
| :----------------------- | :-------------------- | :--------------------------------------------------------------- |
| Harbor registry          | `harbor-registry`     | `team2-harbor-registry-backup`                                   |
| App/Object               | `<app-object-bucket>` | `team2-app-objects-backup`                                       |
| Thanos metrics           | `thanos-metrics`      | `team2-thanos-metrics-backup`                                    |
| Glacier lifecycle 테스트 | 해당 없음             | `team2-lifecycle-test` 또는 위 bucket의 `lifecycle-test/` prefix |

---

## 4. AWS S3 bucket 준비

AWS CLI 실행 위치: 운영자 PC 또는 AWS CLI가 설정된 bastion.

```bash
export AWS_REGION=ap-northeast-2
```

bucket 생성 예시:

```bash
aws s3api create-bucket \
  --bucket team2-harbor-registry-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}

aws s3api create-bucket \
  --bucket team2-app-objects-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}

aws s3api create-bucket \
  --bucket team2-thanos-metrics-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}
```

Versioning 활성화:

```bash
for b in team2-harbor-registry-backup team2-app-objects-backup team2-thanos-metrics-backup; do
  aws s3api put-bucket-versioning \
    --bucket "$b" \
    --versioning-configuration Status=Enabled
 done
```

Public Access Block 적용:

```bash
for b in team2-harbor-registry-backup team2-app-objects-backup team2-thanos-metrics-backup; do
  aws s3api put-public-access-block \
    --bucket "$b" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
 done
```

---

## 5. Lifecycle 정책

## 5.1 운영용 Lifecycle 예시

서비스에서 직접 조회할 가능성이 있는 bucket에는 Deep Archive를 바로 적용하지 않음. 장기 보관/감사용
archive 성격의 백업본에만 Glacier를 적용함.

`lifecycle-prod.json`:

```json
{
  "Rules": [
    {
      "ID": "backup-tiering-prod",
      "Status": "Enabled",
      "Filter": {},
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        },
        {
          "Days": 180,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ],
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
  --bucket team2-thanos-metrics-backup \
  --lifecycle-configuration file://lifecycle-prod.json
```

> `GLACIER`는 S3 Glacier Flexible Retrieval을 의미함. Deep Archive는 복구 시간이 길어 서비스 직접
> 조회 대상에는 부적합함.

## 5.2 Glacier 테스트용 짧은 Lifecycle

Glacier 전환을 테스트하려면 운영 객체와 분리된 prefix에서 수행함.

`lifecycle-test.json`:

```json
{
  "Rules": [
    {
      "ID": "demo-short-glacier-test",
      "Status": "Enabled",
      "Filter": {
        "And": {
          "Prefix": "lifecycle-test/",
          "ObjectSizeGreaterThan": 131072
        }
      },
      "Transitions": [
        {
          "Days": 0,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 3
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 1
      }
    }
  ]
}
```

적용:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket team2-app-objects-backup \
  --lifecycle-configuration file://lifecycle-test.json
```

테스트 객체 업로드:

Linux/macOS/WSL/Git Bash 기준:

```bash
head -c 200000 /dev/urandom > lifecycle-test.bin
aws s3 cp lifecycle-test.bin s3://team2-app-objects-backup/lifecycle-test/lifecycle-test.bin
```

Windows Terminal의 PowerShell 기준:

```powershell
$bytes = New-Object byte[] 200000
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
[System.IO.File]::WriteAllBytes("lifecycle-test.bin", $bytes)
$rng.Dispose()

aws s3 cp .\lifecycle-test.bin s3://team2-app-objects-backup/lifecycle-test/lifecycle-test.bin
```

`/dev/urandom`은 Linux 계열의 난수 장치 파일이므로 순수 PowerShell에서는 사용할 수 없음. 위
PowerShell 예시는 같은 목적의 200KB 테스트 파일을 Windows에서 생성하는 방식임.

확인:

```bash
aws s3api head-object \
  --bucket team2-app-objects-backup \
  --key lifecycle-test/lifecycle-test.bin
```

주의:

- Lifecycle 전환은 즉시 보장되지 않음.
- 128KB 미만 객체는 기본 정책상 전환되지 않을 수 있으므로 테스트 객체는 128KB 초과로 생성함.
- Glacier Flexible Retrieval은 최소 저장 기간 과금이 있으므로 테스트 객체는 소량으로만 사용함.

---

## 6. rclone 기반 Ceph RGW -> AWS S3 copy-only 백업

AWS CLI 하나로 Ceph RGW와 AWS S3를 서로 다른 credential/endpoint로 동시에 다루기 어렵기 때문에, 두
S3 backend를 명확히 분리할 수 있는 `rclone` 사용을 권장함.

## 6.1 rclone 설치

기본 실행 위치는 bastion VM임.

설치 여부 확인:

```bash
rclone version
```

Ubuntu/Debian 계열 bastion에서 패키지로 설치:

```bash
sudo apt update
sudo apt install -y rclone
rclone version
```

패키지 버전이 너무 오래된 경우 공식 설치 스크립트 사용:

```bash
curl -fsSL https://rclone.org/install.sh | sudo bash
rclone version
```

주의:

- 공식 설치 스크립트는 인터넷 접근 필요
- bastion에서 실행 전 명령 내용을 확인하고 사용
- 운영 자동화 전 버전 고정 방식 검토 필요
- Ceph RGW/AWS S3 credential은 설치 명령에 포함하지 않음

Windows Terminal에서 수동 검증하는 경우:

```powershell
winget install Rclone.Rclone
rclone version
```

`winget` 사용이 어려우면 rclone 공식 다운로드 페이지에서 Windows binary를 내려받아 PATH에 추가함.

## 6.2 rclone config 위치와 실행 위치

`rclone.conf`는 저장소에 커밋하는 파일이 아님. RGW Access Key/Secret Key가 들어가므로 **명령을
실행하는 작업 디렉터리의 임시 파일**로만 둠.

예시 위치:

```text
Linux/bastion: /home/ubuntu/backup-test/rclone.conf
Windows:       C:\Users\<USER>\backup-test\rclone.conf
```

문서의 명령은 `--config ./rclone.conf`를 사용하므로, 명령 실행 위치와 `rclone.conf` 위치가 같아야
함.

```bash
mkdir -p ~/backup-test
cd ~/backup-test
vi rclone.conf
```

Windows PowerShell 기준:

```powershell
mkdir $HOME\backup-test
cd $HOME\backup-test
notepad .\rclone.conf
```

실행 위치는 아래 조건을 모두 만족하는 곳이어야 함.

1. Ceph RGW 직접 접근 가능: `http://10.10.10.11:7480`
2. AWS S3에 접근 가능: 인터넷 또는 AWS endpoint 경로
3. `rclone`과 AWS 인증 정보가 준비됨

권장 실행 위치:

| 위치                      | 권장도    | 설명                                                                                 |
| :------------------------ | :-------- | :----------------------------------------------------------------------------------- |
| 온프레 bastion VM         | 높음      | 현재 Ceph망 접근 가능, `10.10.10.11:7480` 직접 접근과 AWS S3 업로드를 함께 검증 가능 |
| backup-runner VM          | 향후 권장 | 백업 전용 VM으로 역할 분리, 운영 자동화 개선 대상                                    |
| 온프레 Kubernetes CronJob | 비권장    | 자동화는 편하지만 K8s/MetalLB 장애 시 백업 영향 가능                                 |
| Windows Terminal          | 조건부    | Windows PC에서 Ceph망 직접 접근 가능해야 함                                          |
| Ceph 노드                 | 조건부    | RGW 내부 endpoint 접근은 쉽지만 운영 노드에 백업 도구/키 배치 최소화 필요            |

Windows에서 접근 확인:

```powershell
Test-NetConnection 10.10.10.11 -Port 7480
aws sts get-caller-identity
rclone version
```

Linux/bastion에서 접근 확인:

```bash
curl -I http://10.10.10.11:7480
aws sts get-caller-identity
rclone version
```

Deprecated MetalLB RGW bridge는 기존 문서 호환 또는 임시 확인이 필요할 때만 확인함.

```bash
curl -I http://172.16.23.60:7480
```

## 6.3 rclone config 예시

`rclone.conf` 예시:

```ini
[ceph-rgw]
type = s3
provider = Ceph
env_auth = false
access_key_id = <CEPH_RGW_ACCESS_KEY>
secret_access_key = <CEPH_RGW_SECRET_KEY>
endpoint = http://10.10.10.11:7480
region = default
acl = private

[aws-s3]
type = s3
provider = AWS
env_auth = true
region = ap-northeast-2
acl = private
```

> `10.10.10.11:7480`은 bastion에서 Ceph망으로 직접 접근하는 기본 endpoint임. `172.16.23.60:7480`은
> 신규 백업 경로로 사용하지 않는 deprecated MetalLB RGW bridge endpoint임.

## 6.4 수동 dry-run

`dry-run`은 실제 복사 전에 어떤 객체가 복사될지 미리 보는 단계임.

- AWS S3에 실제 객체를 만들지 않음
- Ceph RGW 원본도 변경하지 않음
- destination에 없는 객체/변경될 객체 목록을 사전 확인함
- 처음 실행할 때는 반드시 dry-run을 먼저 수행함

Harbor registry bucket:

```bash
rclone copy ceph-rgw:harbor-registry aws-s3:team2-harbor-registry-backup \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

Thanos bucket:

```bash
rclone copy ceph-rgw:thanos-metrics aws-s3:team2-thanos-metrics-backup \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

## 6.5 실제 copy-only 실행

`dry-run` 결과가 정상일 때만 실제 copy-only를 실행함.

- Ceph RGW 원본은 유지됨
- AWS S3 destination에 객체가 복사됨
- `rclone copy`는 destination에만 있는 객체를 삭제하지 않음
- 따라서 초기 백업 검증 단계에서는 `sync`, `delete`, `purge`를 사용하지 않음

```bash
rclone copy ceph-rgw:harbor-registry aws-s3:team2-harbor-registry-backup \
  --config ./rclone.conf \
  --progress \
  --checksum

rclone copy ceph-rgw:thanos-metrics aws-s3:team2-thanos-metrics-backup \
  --config ./rclone.conf \
  --progress \
  --checksum
```

`copy`는 원본에 없는 destination 객체를 삭제하지 않음. 초기 단계에서는 `sync --delete` 성격의 동작을
사용하지 않음.

## 6.6 key 보존 확인

Ceph와 AWS S3에서 같은 key가 유지되는지 확인함.

```bash
rclone lsf ceph-rgw:harbor-registry --config ./rclone.conf --recursive | head
rclone lsf aws-s3:team2-harbor-registry-backup --config ./rclone.conf --recursive | head
```

---

## 7. Kubernetes CronJob 적용 예시

GitOps 저장소에는 실제 Secret 값을 넣지 않음. 아래 YAML은 구조 예시이며, Secret은 수동 생성 또는
ExternalSecret/SOPS/SealedSecret으로 관리함.

주의:

- 현재 기본 백업 실행 위치는 bastion VM임.
- Kubernetes CronJob은 추후 자동화 후보임.
- K8s/MetalLB 장애 시 백업까지 영향받을 수 있으므로 운영 주 경로로 사용하지 않음.
- CronJob을 사용할 경우에도 `rclone.conf` endpoint는 `10.10.10.11:7480` 직접 접근을 우선함.
- `172.16.23.60:7480`은 기존 구성 마이그레이션 전 임시 확인용으로만 사용함.

## 7.1 Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: backup
```

## 7.2 rclone config Secret 생성

수동 생성 예시:

```bash
kubectl --context kubernetes-admin@kubernetes create namespace backup --dry-run=client -o yaml | \
  kubectl --context kubernetes-admin@kubernetes apply -f -

kubectl --context kubernetes-admin@kubernetes -n backup create secret generic rclone-config \
  --from-file=rclone.conf=./rclone.conf
```

## 7.3 AWS credential Secret 또는 IRSA

온프레 Kubernetes에서 실행하는 경우 AWS IAM Role을 직접 붙이기 어렵기 때문에, 초기 검증은 AWS Access
Key Secret 방식으로 수행할 수 있음.

```bash
kubectl --context kubernetes-admin@kubernetes -n backup create secret generic aws-s3-backup-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
```

> 운영 기준에서는 장기 Access Key보다 OIDC/IRSA/외부 비밀 관리 도입을 우선 검토함.

## 7.4 CronJob 예시

`object-backup-cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: object-backup-copy-only
  namespace: backup
spec:
  schedule: "0 3 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: rclone
              image: rclone/rclone:latest
              env:
                - name: AWS_ACCESS_KEY_ID
                  valueFrom:
                    secretKeyRef:
                      name: aws-s3-backup-credentials
                      key: AWS_ACCESS_KEY_ID
                - name: AWS_SECRET_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      name: aws-s3-backup-credentials
                      key: AWS_SECRET_ACCESS_KEY
              command:
                - /bin/sh
                - -ec
                - |
                  rclone copy ceph-rgw:harbor-registry aws-s3:team2-harbor-registry-backup --config /config/rclone.conf --checksum --stats 30s
                  rclone copy ceph-rgw:thanos-metrics aws-s3:team2-thanos-metrics-backup --config /config/rclone.conf --checksum --stats 30s
              volumeMounts:
                - name: rclone-config
                  mountPath: /config
                  readOnly: true
          volumes:
            - name: rclone-config
              secret:
                secretName: rclone-config
```

적용:

```bash
kubectl --context kubernetes-admin@kubernetes apply -f object-backup-cronjob.yaml
```

수동 실행:

```bash
kubectl --context kubernetes-admin@kubernetes -n backup create job \
  --from=cronjob/object-backup-copy-only object-backup-manual-$(date +%Y%m%d%H%M%S)
```

로그 확인:

```bash
kubectl --context kubernetes-admin@kubernetes -n backup get jobs,pods
kubectl --context kubernetes-admin@kubernetes -n backup logs job/<JOB_NAME>
```

---

## 8. 복구 절차

## 8.1 Object bucket 복구 기본 원칙

- 운영 bucket에 바로 덮어쓰지 않음.
- 먼저 test bucket 또는 임시 prefix로 복구함.
- key 구조와 object count/size를 비교함.

예시: AWS S3 backup -> Ceph RGW test bucket

```bash
rclone copy aws-s3:team2-harbor-registry-backup ceph-rgw:harbor-registry-restore-test \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

검증 후 실제 복구:

```bash
rclone copy aws-s3:team2-harbor-registry-backup ceph-rgw:harbor-registry-restore-test \
  --config ./rclone.conf \
  --progress \
  --checksum
```

## 8.2 Thanos bucket 복구

Thanos bucket은 block 구조를 수동으로 수정하지 않음.

안전 절차:

1. 새 bucket에 복구
2. `thanos-objstore` Secret을 test bucket으로 교체
3. StoreGateway/Query에서 조회 확인
4. 문제가 없으면 운영 bucket 전환 검토

주의:

- 운영 bucket에 in-place 복구하는 경우 Compactor를 먼저 중지함.
- Compactor가 실행 중인 상태에서 과거 block을 덮어쓰거나 삭제하면 overlap/삭제 문제가 생길 수 있음.

---

## 9. Glacier 복구 절차

Glacier Flexible Retrieval/Deep Archive 객체는 즉시 읽을 수 없음. 먼저 restore 요청이 필요함.

```bash
aws s3api restore-object \
  --bucket team2-thanos-metrics-backup \
  --key <OBJECT_KEY> \
  --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'
```

상태 확인:

```bash
aws s3api head-object \
  --bucket team2-thanos-metrics-backup \
  --key <OBJECT_KEY>
```

`Restore` 헤더에 복구 진행/만료 정보가 표시됨.

복구 완료 후 영구적으로 Standard로 되돌리려면 같은 key로 copy함.

```bash
aws s3 cp \
  s3://team2-thanos-metrics-backup/<OBJECT_KEY> \
  s3://team2-thanos-metrics-backup/<OBJECT_KEY> \
  --storage-class STANDARD \
  --metadata-directive COPY
```

---

## 10. 검증 체크리스트

| 검증 항목             | 명령/방법                                   | 기대 결과                                             |
| :-------------------- | :------------------------------------------ | :---------------------------------------------------- |
| RGW 직접 접근         | `curl -I http://10.10.10.11:7480`           | `200 OK`, `Ceph Object Gateway`                       |
| Deprecated RGW bridge | `curl -I http://172.16.23.60:7480`          | 기존 구성 확인 시에만 `200 OK`, `Ceph Object Gateway` |
| Ceph bucket 목록      | `rclone lsd ceph-rgw:`                      | 대상 bucket 표시                                      |
| AWS bucket 목록       | `aws s3 ls`                                 | backup bucket 표시                                    |
| Dry-run               | `rclone copy ... --dry-run`                 | 삭제 없이 복사 대상 확인                              |
| Copy-only             | `rclone copy ...`                           | 원본 유지, destination에 key 생성                     |
| Key 보존              | `rclone lsf ... --recursive`                | Ceph/AWS key 경로 일치                                |
| Thanos upload         | sidecar log                                 | block upload 오류 없음                                |
| Thanos Query          | `up{cluster="onprem"}`, `up{cluster="eks"}` | 양쪽 cluster label 조회                               |
| Glacier test          | `head-object`                               | StorageClass/Restore 상태 확인                        |

---

## 11. 발표용 To-Be 문장

현재 단계:

> bastion VM에서 Ceph RGW(`10.10.10.11:7480`)에 직접 접근해 Object 데이터를 AWS S3로 동일 key 구조로
> 복제하는 copy-only 백업을 우선 적용한다. 이 단계에서는 Ceph 원본을 유지해 서비스 영향 없이 백업
> 무결성과 복구 가능성을 검증한다.

향후 단계:

> 검증이 완료되면 DB 메타데이터에 `storage_type`, `bucket`, `object_key`를 관리하도록 확장하고,
> 오래된 객체는 Ceph에서 삭제한 뒤 AWS S3를 직접 조회하는 Tiered Storage 구조로 전환한다. 장기 보관
> 데이터는 S3 Lifecycle을 통해 Glacier로 이동한다.

백업 경로 설명:

> 백업 경로는 서비스 경로와 분리한다. K8s/MetalLB에 의존하는 RGW bridge는 deprecated 경로로 두고
> 신규 백업에는 사용하지 않는다. 현재는 Ceph망 접근이 가능한 bastion VM에서 RGW에 직접 접근한다.
> 추후에는 백업 전용 backup-runner VM으로 역할을 분리한다.

DB 범위 설명:

> DB는 현재 PXC 3노드와 Ceph RBD 기반으로 노드/디스크 장애에 대응한다. 다만 이는 논리 삭제나 데이터
> 오염 복구를 위한 백업은 아니므로, 추후 PITR 요구가 생기면 XtraBackup/binlog 기반 DB 백업을 별도
> 도입한다.
