# 백업/복구 Runbook

> Status: Unverified 범위: 현재 우선순위는 **App/Object Ceph RGW -> AWS S3 백업**과 **Harbor -> ECR
> image replication 운영 기준**임. DB/PVC/etcd/GitOps/Secret 전체 백업은 현재 범위에서 제외하고,
> 한계만 명시함.

---

## 1. 백업 범위와 제외 범위

## 1.1 현재 우선 적용 범위

| 구분            | 대상                      | 현재 저장소     | 백업 대상   | 전략                |
| :-------------- | :------------------------ | :-------------- | :---------- | :------------------ |
| App/Object      | 사용자 업로드/서비스 객체 | Ceph RGW bucket | AWS S3      | 동일 key copy-only  |
| Harbor Image    | Kubernetes 배포 이미지    | Harbor RGW      | AWS ECR     | event-based mirror  |
| ECR Archive     | 오래된 container image    | AWS ECR         | ECR archive | ECR Lifecycle 적용  |
| Glacier Archive | 오래된 백업본             | AWS S3          | S3 Glacier  | S3 Lifecycle로 전환 |

## 1.2 현재 제외 범위

| 구분                | 제외 사유                                                                              | 한계                                                                             |
| :------------------ | :------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------- |
| Harbor RGW S3 백업  | cloud bursting 이미지 pull 속도 확보를 위해 Harbor -> ECR event-based replication 적용 | ECR은 이미지 복제본이며 Harbor project/user/robot/정책 metadata 전체 백업은 아님 |
| DB 백업             | 현재 PXC 3노드 + Ceph RBD(`team2-rbd-block`) 기반으로 노드/디스크 장애 대응을 우선함   | RBD replica는 논리 삭제/오염 복구용 백업은 아님. 추후 XtraBackup/binlog 필요     |
| Thanos Metrics      | 현재 Thanos 미사용 전제                                                                | Thanos 도입 후 `thanos-metrics` bucket과 별도 RGW user/key 기준 추가 필요        |
| etcd/Velero         | 이번 우선 목표가 Object 백업임                                                         | 클러스터 전체 재해복구는 별도 Runbook 필요                                       |
| GitOps/Secret       | Git 저장소와 Secret 관리 정책은 별도 주제                                              | Secret 평문 백업 금지. SOPS/SealedSecret/ExternalSecret 검토 필요                |
| pfSense/Proxmox/IaC | 인프라 설정 백업은 별도 운영 절차                                                      | config.xml, Terraform state 등 별도 보관 필요                                    |

> 발표 시 표현: 사용자 업로드 객체는 **copy-only 백업**으로 S3에 보관하고, 배포 이미지는 cloud
> bursting 시 EKS pull 지연을 줄이기 위해 Harbor에서 ECR로 event-based replication한다. Harbor
> registry blob을 S3로 다시 백업하는 방식은 현재 기본 경로에서 제외한다.

---

## 2. 설계 원칙

## 2.1 Object key는 동일하게 유지

AWS S3에서 직접 조회할 가능성이 있는 앱 객체는 Ceph RGW와 AWS S3의 object key를 동일하게 유지함.

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

## 2.3 Harbor image는 ECR replication 경로 사용

Harbor registry blob은 S3 copy-only 백업 대상에서 제외함. 현재 Harbor에는 ECR 원격 registry와
event-based replication policy가 구성되어 있음.

확인된 Harbor 설정:

| 항목               | 값                                                 |
| :----------------- | :------------------------------------------------- |
| Registry name      | `aws-ecr-seoul`                                    |
| Registry type      | `aws-ecr`                                          |
| Registry URL       | `https://api.ecr.ap-northeast-2.amazonaws.com`     |
| Replication policy | `kosa-tickets-to-ecr`                              |
| Source             | `Local` Harbor                                     |
| Destination        | `aws-ecr-seoul`                                    |
| Mode               | push-based                                         |
| Trigger            | event-based                                        |
| Filter             | `library/kosa-tickets`, tag `**`, resource `image` |
| ECR repository     | `library/kosa-tickets`                             |

구조:

```text
CI / developer
  -> Harbor library/kosa-tickets:<tag>
  -> Harbor event-based replication
  -> ECR ap-northeast-2 library/kosa-tickets:<tag>
  -> EKS cloud bursting node image pull
```

설계 이유:

- EKS node가 온프레 Harbor에서 WAN/VPN 경유로 image pull하는 지연 제거
- AWS 내부 ECR에서 같은 Region pull 수행
- cloud bursting 시 Pod cold start 시간 감소
- Harbor 장애 또는 온프레-WAN 지연이 EKS scale-out에 미치는 영향 완화
- 이미지 배포 경로와 일반 객체 백업 경로 분리

주의:

- ECR replication은 image artifact 복제 경로
- Harbor project, user, robot account, scanner 설정, replication policy 자체의 전체 백업은 아님
- Harbor registry blob을 S3에 별도 copy하면 저장 비용과 운영 경로가 중복됨
- ECR의 active image는 burst 시 즉시 pull 가능해야 하므로 무분별한 archive/expire 금지

Harbor UI 확인 경로:

- Harbor
  - 관리
    - 레지스트리
      - `aws-ecr-seoul` 상태 확인
    - 복제
      - `kosa-tickets-to-ecr` 정책 확인
      - 정책 상세 또는 실행 이력/작업 이력에서 최근 tag replication 성공 여부 확인

Harbor API 확인:

```bash
curl -k -u '<HARBOR_ADMIN_USER>:<HARBOR_ADMIN_PASSWORD>' \
  https://harbor.kosa.team2/api/v2.0/replication/policies
```

> API 응답의 `dest_registry.credential.access_secret`은 마스킹되어 표시되더라도 민감 정보로 취급함.

## 2.4 Thanos active bucket은 추후 적용

Thanos 도입 시 실제 조회하는 active bucket은 Ceph RGW에 둠.

```text
Prometheus -> Thanos Sidecar -> Ceph RGW thanos-metrics
```

AWS S3/Glacier는 active bucket의 백업본에만 적용함.

```text
Ceph RGW thanos-metrics
  -> AWS S3 team2-thanos-metrics-backup
  -> Lifecycle -> Glacier
```

현재 문서의 즉시 실행 대상에서는 제외함.

## 2.5 백업 경로는 서비스 경로와 분리

백업 제어 경로는 보호 대상 서비스의 런타임 경로와 분리함.

표준 원칙:

- 백업 작업은 애플리케이션 배포/서비스 노출 계층과 독립
- 백업 대상 저장소에 가장 짧고 직접적인 경로 사용
- 복구 시 필요한 구성 요소 수 최소화
- 서비스 트래픽 경로와 백업 트래픽 경로 분리
- 임시 bridge/ingress/load balancer 경유 최소화

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
- bastion VM cron: 현재 자동화 기본 방식
- Kubernetes CronJob: deprecated, 신규 백업 경로로 사용하지 않음
- 향후 개선: backup-runner VM 분리, 백업 전용 역할/키/스케줄 관리

---

## 3. 예시 bucket 이름

아래 이름은 예시임. 실제 계정/프로젝트 정책에 맞게 변경 가능함.

| 용도                     | Ceph RGW user | Ceph RGW bucket 예시 | AWS S3 bucket/prefix 예시                                        | 상태      |
| :----------------------- | :------------ | :------------------- | :--------------------------------------------------------------- | :-------- |
| App/Object 일반          | `team2-admin` | `team2-bucket`       | `team2-app-objects-backup/team2-bucket/`                         | 즉시 백업 |
| App/Object 이미지        | `team2-admin` | `team2-photo-bucket` | `team2-app-objects-backup/team2-photo-bucket/`                   | 즉시 백업 |
| Thanos metrics           | `thanos`      | `thanos-metrics`     | `team2-thanos-metrics-backup`                                    | 추후 적용 |
| Glacier lifecycle 테스트 | 해당 없음     | 해당 없음            | `team2-lifecycle-test` 또는 위 bucket의 `lifecycle-test/` prefix | 테스트    |

> 현재 확인된 bucket owner 기준: `team2-admin`은 `team2-bucket`과 `team2-photo-bucket` 소유. Harbor
> registry bucket(`harbor-registry`)은 ECR replication 경로를 사용하므로 S3 backup bucket 목록에서
> 제외함. Thanos bucket은 추후 Thanos 사용 시 추가함.

## 3.1 실제 Ceph RGW bucket 확인

Ceph 노드에서 전체 bucket 확인:

```bash
radosgw-admin bucket list
radosgw-admin bucket list --uid=team2-admin
```

bucket별 소유자와 객체 수 확인:

```bash
radosgw-admin bucket stats --bucket team2-bucket
radosgw-admin bucket stats --bucket team2-photo-bucket
```

bastion에서 rclone 기준 확인은 `backup.env`와 `rclone.conf` 작성 후 6.5에서 수행함.

주의:

- 3.1은 Ceph 노드 기준 bucket owner 확인 단계
- bastion S3 API 확인은 rclone credential 준비 후 수행
- 특정 bucket만 `AccessDenied`면 해당 bucket 소유자/권한 확인
- 앱 업로드 bucket이 추가로 발견되면 6.4/6.5/7.2 복사 대상에 추가
- Harbor registry bucket은 S3 백업 대상이 아니라 ECR replication 상태로 검증

---

## 4. AWS S3 bucket 준비

AWS CLI 실행 위치: 운영자 PC 또는 AWS CLI가 설정된 bastion.

```bash
export AWS_REGION=ap-northeast-2
```

bucket 생성 예시:

```bash
aws s3api create-bucket \
  --bucket team2-app-objects-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}
```

Versioning 활성화:

```bash
for b in team2-app-objects-backup; do
  aws s3api put-bucket-versioning \
    --bucket "$b" \
    --versioning-configuration Status=Enabled
 done
```

Public Access Block 적용:

```bash
for b in team2-app-objects-backup; do
  aws s3api put-public-access-block \
    --bucket "$b" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
 done
```

Thanos 사용 시 추가 bucket 생성:

```bash
aws s3api create-bucket \
  --bucket team2-thanos-metrics-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}

aws s3api put-bucket-versioning \
  --bucket team2-thanos-metrics-backup \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket team2-thanos-metrics-backup \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
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
      "Filter": {
        "ObjectSizeGreaterThan": 0
      },
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
      ]
    },
    {
      "ID": "abort-incomplete-multipart-prod",
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
  --bucket team2-thanos-metrics-backup \
  --lifecycle-configuration file://lifecycle-prod.json
```

> `GLACIER`는 S3 Glacier Flexible Retrieval을 의미함. Deep Archive는 복구 시간이 길어 서비스 직접
> 조회 대상에는 부적합함.

> 백업 정책의 목적이 "만료 전 archive 전환"이면 `ObjectSizeGreaterThan: 0`을 명시함. 현재 S3 기본
> 동작은 128KB 미만 객체를 Lifecycle transition 대상에서 제외할 수 있음. 단순히 size 조건을 제거하면
> 작은 객체가 archive되지 않고 expiration만 적용될 수 있으므로 주의함.

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
          "ObjectSizeGreaterThan": 0
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
      }
    },
    {
      "ID": "abort-incomplete-multipart-test",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "lifecycle-test/"
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 1
      }
    }
  ]
}
```

> AWS S3 Lifecycle에서 `ObjectSizeGreaterThan` 같은 object size 조건과
> `AbortIncompleteMultipartUpload`는 같은 rule에 함께 지정할 수 없음. 테스트 rule은 Glacier
> 전환/만료 rule과 multipart abort rule을 분리함.

적용:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket team2-app-objects-backup \
  --lifecycle-configuration file://lifecycle-test.json
```

테스트 객체 업로드:

Linux/macOS/WSL/Git Bash 기준:

```bash
head -c 1024 /dev/urandom > lifecycle-test.bin
aws s3 cp lifecycle-test.bin s3://team2-app-objects-backup/lifecycle-test/lifecycle-test.bin
```

Windows Terminal의 PowerShell 기준:

```powershell
$bytes = New-Object byte[] 1024
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
[System.IO.File]::WriteAllBytes("lifecycle-test.bin", $bytes)
$rng.Dispose()

aws s3 cp .\lifecycle-test.bin s3://team2-app-objects-backup/lifecycle-test/lifecycle-test.bin
```

`/dev/urandom`은 Linux 계열의 난수 장치 파일이므로 순수 PowerShell에서는 사용할 수 없음. 위
PowerShell 예시는 같은 목적의 1KB 테스트 파일을 Windows에서 생성하는 방식임.

확인:

```bash
aws s3api head-object \
  --bucket team2-app-objects-backup \
  --key lifecycle-test/lifecycle-test.bin
```

prefix 전체 추적:

```bash
aws s3api list-object-versions \
  --bucket team2-app-objects-backup \
  --prefix lifecycle-test/ \
  --query 'Versions[].{Key:Key,StorageClass:StorageClass,LastModified:LastModified,Size:Size}' \
  --output table
```

전환 완료 기준:

- `StorageClass`: `STANDARD`이면 아직 전환 전
- `StorageClass`: `GLACIER`이면 Glacier 전환 완료
- 직접 `--storage-class GLACIER`로 업로드한 객체는 즉시 `GLACIER`
- Lifecycle으로 업로드 후 전환되는 객체는 AWS 내부 비동기 처리 대기

직접 Glacier 업로드 검증:

```bash
echo "direct glacier test" > direct-glacier-test.txt

aws s3api put-object \
  --bucket team2-app-objects-backup \
  --key lifecycle-test/direct-glacier-test.txt \
  --body direct-glacier-test.txt \
  --storage-class GLACIER

aws s3api head-object \
  --bucket team2-app-objects-backup \
  --key lifecycle-test/direct-glacier-test.txt \
  --query '{StorageClass:StorageClass, LastModified:LastModified}'
```

> 직접 Glacier 업로드는 S3 Glacier 사용 가능 여부 확인용임. Lifecycle 자동 전환 검증은
> `aws s3 cp ... s3://.../lifecycle-test/...`로 `STANDARD` 업로드 후 `list-object-versions`에서
> `StorageClass=GLACIER`로 바뀌는지 추적함.

직접 Glacier 테스트 객체 삭제:

```bash
# 1. 일반 삭제. Versioning bucket에서는 delete marker 생성.
aws s3api delete-object \
  --bucket team2-app-objects-backup \
  --key lifecycle-test/direct-glacier-test.txt

# 2. 남아 있는 object version/delete marker 확인.
aws s3api list-object-versions \
  --bucket team2-app-objects-backup \
  --prefix lifecycle-test/direct-glacier-test.txt

# 3. 실제 object version 완전 삭제.
aws s3api delete-object \
  --bucket team2-app-objects-backup \
  --key lifecycle-test/direct-glacier-test.txt \
  --version-id <OBJECT_VERSION_ID>

# 4. delete marker 완전 삭제.
aws s3api delete-object \
  --bucket team2-app-objects-backup \
  --key lifecycle-test/direct-glacier-test.txt \
  --version-id <DELETE_MARKER_VERSION_ID>
```

삭제 완료 확인:

```bash
aws s3api list-object-versions \
  --bucket team2-app-objects-backup \
  --prefix lifecycle-test/direct-glacier-test.txt
```

완전 삭제 기준:

- `Versions` 없음
- `DeleteMarkers` 없음
- 출력에 `Prefix`와 `RequestCharged`만 표시

주의:

- Lifecycle 전환은 즉시 보장되지 않음.
- `ObjectSizeGreaterThan: 0`은 0바이트 객체를 제외한 모든 객체를 transition 대상으로 지정함.
- 0바이트 directory marker는 백업 데이터로 보지 않으며 archive 전환 대상에서 제외함.
- 작은 객체 transition은 비용 절감 효과보다 요청 비용이 클 수 있으나, 현재 테스트는 정책 동작 확인
  목적임.
- Glacier Flexible Retrieval은 최소 저장 기간 과금이 있으므로 테스트 객체는 소량으로만 사용함.

## 5.3 테스트 후 운영 Lifecycle로 복귀

`lifecycle-test.json`은 Glacier 전환 확인용 짧은 정책임.

테스트 완료 후 선택:

| 선택             | 적용 대상                  | 설명                                                     |
| :--------------- | :------------------------- | :------------------------------------------------------- |
| 테스트 정책 삭제 | `team2-app-objects-backup` | 테스트 bucket/prefix에 더 이상 Lifecycle을 적용하지 않음 |
| 운영 정책 적용   | 운영 백업 bucket           | 장기 보관 기준으로 `lifecycle-prod.json` 적용            |

테스트 정책 삭제:

```bash
aws s3api delete-bucket-lifecycle \
  --bucket team2-app-objects-backup
```

운영 정책 적용 예:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket team2-app-objects-backup \
  --lifecycle-configuration file://lifecycle-prod.json
```

현재 Lifecycle 확인:

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket team2-app-objects-backup
```

주의:

- `delete-bucket-lifecycle`은 해당 bucket의 모든 Lifecycle rule을 삭제함.
- 운영 bucket에 기존 rule이 있으면 삭제 전 `get-bucket-lifecycle-configuration`으로 백업함.
- `lifecycle-test/` prefix 객체는 테스트 완료 후 삭제하거나 비용 확인 후 유지 여부 결정함.

## 5.4 ECR image Lifecycle/Archive 정책

Harbor image는 S3 Glacier가 아니라 ECR에서 직접 보관 정책을 적용함.

정리:

- ECR active image: EKS cloud bursting 시 즉시 pull 대상
- ECR archive image: 장기 보관 대상, 즉시 pull 대상 아님
- S3 Glacier: 객체 저장소용 archive 계층, ECR image pull 경로와 직접 연결되지 않음
- Harbor -> S3 registry blob 백업: 현재 기본 경로에서 제외

운영 원칙:

- `latest`, 최근 배포 tag, rollback 후보 tag는 ECR Standard 유지
- 오래되었고 pull되지 않는 image만 ECR archive 전환
- archived image는 burst 시 즉시 pull 대상으로 보지 않음
- archive 적용 전 lifecycle preview 필수
- ECR repository별 lifecycle policy 적용 필요

현재 확인된 ECR repository:

```bash
aws ecr describe-repositories --region ap-northeast-2

aws ecr describe-images \
  --repository-name library/kosa-tickets \
  --region ap-northeast-2 \
  --query 'imageDetails[].{tags:imageTags,digest:imageDigest,status:imageStatus,size:imageSizeInBytes,pushed:imagePushedAt,lastPull:imageLastRecordedPullTime}' \
  --output table
```

기존 lifecycle policy 확인:

```bash
aws ecr get-lifecycle-policy \
  --repository-name library/kosa-tickets \
  --region ap-northeast-2
```

정책이 없으면 `LifecyclePolicyNotFoundException` 발생 가능.

보수적 archive 정책 예시:

`ecr-lifecycle-archive.json`:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Archive images not pulled in 90 days",
      "selection": {
        "tagStatus": "any",
        "countType": "sinceImagePulled",
        "countUnit": "days",
        "countNumber": 90
      },
      "action": {
        "type": "transition",
        "targetStorageClass": "archive"
      }
    },
    {
      "rulePriority": 2,
      "description": "Expire archived images after 365 days",
      "selection": {
        "tagStatus": "any",
        "storageClass": "archive",
        "countType": "sinceImageTransitioned",
        "countUnit": "days",
        "countNumber": 365
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

주의:

- `sinceImagePulled` 기준은 pull 이력이 없는 image 판단에 주의 필요
- cloud bursting 대상 image가 archive되면 scale-out 시 즉시 pull 불가
- archived image 삭제는 최소 보관 기간/과금 조건 확인 필요
- 운영 적용 전 preview 결과 확인

Lifecycle preview:

```bash
aws ecr start-lifecycle-policy-preview \
  --repository-name library/kosa-tickets \
  --lifecycle-policy-text file://ecr-lifecycle-archive.json \
  --region ap-northeast-2

aws ecr get-lifecycle-policy-preview \
  --repository-name library/kosa-tickets \
  --region ap-northeast-2 \
  --output table
```

정책 적용:

```bash
aws ecr put-lifecycle-policy \
  --repository-name library/kosa-tickets \
  --lifecycle-policy-text file://ecr-lifecycle-archive.json \
  --region ap-northeast-2
```

적용 후 확인:

```bash
aws ecr get-lifecycle-policy \
  --repository-name library/kosa-tickets \
  --region ap-northeast-2

aws ecr describe-images \
  --repository-name library/kosa-tickets \
  --region ap-northeast-2 \
  --query 'imageDetails[].{tags:imageTags,digest:imageDigest,status:imageStatus,size:imageSizeInBytes,pushed:imagePushedAt,lastPull:imageLastRecordedPullTime,transitioned:imageTransitionedAt}' \
  --output table
```

UI 적용 경로:

- AWS Console
- Elastic Container Registry
- Private repositories
- `library/kosa-tickets`
- Lifecycle policies
- Create rule
- Rule action: `Archive` 또는 `Expire`
- Match criteria 확인
- Save 전 preview 확인

S3 Glacier에 image tar를 별도 보관하는 방식:

- 가능은 함
- ECR image를 `docker pull` 또는 `skopeo copy`로 내려받음
- tar/OCI archive 생성
- S3 bucket 업로드
- S3 Lifecycle로 Glacier 전환
- 단점: EKS가 직접 pull 불가, 복구 시 ECR로 다시 push 필요
- 현재 cloud bursting 목적에는 비권장

예시:

```bash
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin 357737841289.dkr.ecr.ap-northeast-2.amazonaws.com

docker pull 357737841289.dkr.ecr.ap-northeast-2.amazonaws.com/library/kosa-tickets:<TAG>
docker save 357737841289.dkr.ecr.ap-northeast-2.amazonaws.com/library/kosa-tickets:<TAG> \
  -o kosa-tickets-<TAG>.tar

aws s3 cp kosa-tickets-<TAG>.tar \
  s3://team2-app-objects-backup/ecr-archive/library/kosa-tickets/<TAG>/kosa-tickets-<TAG>.tar
```

판단:

- 빠른 cloud bursting pull: ECR Standard
- 장기 image 보관: ECR archive
- 감사용 오프라인 사본: S3 Glacier archive tar
- 현재 기본 운영: Harbor -> ECR replication + ECR lifecycle/archive

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

## 6.2 작업 디렉터리와 Secret 파일 준비

`rclone.conf`에는 remote 구조와 endpoint만 둠. Ceph RGW Access Key는 `backup.env`에서 환경변수로
주입함. AWS 인증은 기존 AWS CLI 인증을 우선 사용함.

디렉터리 생성:

```bash
mkdir -p /home/ubuntu/backup-test/logs
cd /home/ubuntu/backup-test
```

파일 배치:

```text
/home/ubuntu/backup-test/
  rclone.conf
  backup.env
  object-backup-copy-only.sh
  logs/
```

권한 설정:

```bash
chmod 600 /home/ubuntu/backup-test/rclone.conf
chmod 600 /home/ubuntu/backup-test/backup.env
```

### 6.2.1 credential 확인

Ceph RGW Access Key/Secret Key 확인:

```bash
radosgw-admin user info --uid=team2-admin
```

확인 기준:

- `keys[].access_key`
- `keys[].secret_key`
- bucket owner와 사용하는 RGW user 일치 여부

bucket owner 확인:

```bash
radosgw-admin bucket stats --bucket team2-bucket | grep -E '"owner"|"num_objects"|"size"'
radosgw-admin bucket stats --bucket team2-photo-bucket | grep -E '"owner"|"num_objects"|"size"'
```

AWS 인증 확인:

```bash
aws sts get-caller-identity
```

현재 bastion 예시:

```json
{
  "UserId": "AIDAVGSWWIKE4ZVGULI65",
  "Account": "357737841289",
  "Arn": "arn:aws:iam::357737841289:user/parkpark131"
}
```

위 명령이 성공하면 AWS S3용 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`를 `backup.env`에 넣지 않음.
이미 bastion 사용자 환경에 AWS CLI credential이 설정된 상태임.

주의:

- AWS CLI 인증이 이미 성공하면 AWS Access Key/Secret Key를 `backup.env`에 중복 저장하지 않음.
- Windows 운영자 PC와 bastion VM의 AWS IAM user는 달라도 됨.
- 백업 실행 기준은 bastion VM의 `aws sts get-caller-identity` 성공 여부임.
- AWS Secret Access Key는 생성 후 다시 조회할 수 없음.
- 인증이 없는 새 서버에서는 IAM Role, AWS profile, backup 전용 Access Key 중 하나를 별도로 구성.
- Ceph RGW Secret Key는 `radosgw-admin user info`로 확인 가능하지만 평문 노출에 주의.
- App/Object bucket은 `team2-admin` key 기준으로 백업.
- Thanos 도입 시 `thanos` user/key와 `thanos-metrics` bucket을 별도 추가.
- 백업 전용 RGW user를 만들 경우 백업 대상 bucket read 권한을 명시적으로 검증.

### 6.2.2 backup.env 작성

`backup.env` 예시:

```bash
# Ceph RGW credential for rclone remote: cephteam2
RCLONE_CONFIG_CEPHTEAM2_ACCESS_KEY_ID="REPLACE_TEAM2_ADMIN_RGW_ACCESS_KEY"
RCLONE_CONFIG_CEPHTEAM2_SECRET_ACCESS_KEY="REPLACE_TEAM2_ADMIN_RGW_SECRET_KEY"

# AWS region for rclone remote: aws-s3 and aws cli
# bastion에서 aws sts get-caller-identity 성공 시 AWS Access Key/Secret Key 생략
AWS_DEFAULT_REGION="ap-northeast-2"

# Slack Incoming Webhook URL
# 생성 시 선택한 Slack 채널에 고정됨. 채널 변경 시 새 Webhook URL 발급.
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/REPLACE/REPLACE/REPLACE"
```

> Slack Webhook URL은 Secret이므로 저장소에 커밋하지 않음. 알림을 쓰지 않으면 `SLACK_WEBHOOK_URL`은
> 비워둘 수 있음. `RCLONE_CONFIG_CEPHTEAM2_*` 환경변수는 `cephteam2` remote의 credential을 주입함.
> rclone 환경변수 매핑 혼선을 줄이기 위해 Ceph remote 이름은 영문/숫자만 사용함.

Thanos 도입 시 추가 예시:

```bash
RCLONE_CONFIG_CEPHTHANOS_ACCESS_KEY_ID="REPLACE_THANOS_RGW_ACCESS_KEY"
RCLONE_CONFIG_CEPHTHANOS_SECRET_ACCESS_KEY="REPLACE_THANOS_RGW_SECRET_KEY"
```

AWS CLI profile을 명시해야 하는 경우:

```bash
AWS_PROFILE="parkpark131"
AWS_DEFAULT_REGION="ap-northeast-2"
```

AWS 인증이 없는 새 서버에서만 추가:

```bash
AWS_ACCESS_KEY_ID="REPLACE_AWS_ACCESS_KEY_ID"
AWS_SECRET_ACCESS_KEY="REPLACE_AWS_SECRET_ACCESS_KEY"
AWS_DEFAULT_REGION="ap-northeast-2"
```

`backup.env` 사용 기준:

- 현재 bastion VM 수동/cron 실행에서는 허용
- AWS 인증은 기존 AWS CLI credential 우선 사용
- `aws sts get-caller-identity` 성공 시 AWS key 환경변수 생략
- 파일 소유자: 백업 실행 사용자
- 파일 권한: `600`
- Git 저장소, 문서, 채팅, 스크린샷 노출 금지
- `set -x` 사용 금지
- 다중 사용자 서버에서는 전용 `backup` 사용자 분리 권장
- 운영 고도화 시 OS Secret 관리, Vault, SSM Parameter Store 같은 외부 비밀 저장소 검토

## 6.3 실행 위치 확인

실행 위치는 아래 조건을 모두 만족하는 곳이어야 함.

1. Ceph RGW 직접 접근 가능: `http://10.10.10.11:7480`
2. AWS S3에 접근 가능: 인터넷 또는 AWS endpoint 경로
3. `rclone`과 AWS 인증 정보가 준비됨

권장 실행 위치:

| 위치                      | 권장도    | 설명                                                                                 |
| :------------------------ | :-------- | :----------------------------------------------------------------------------------- |
| 온프레 bastion VM         | 높음      | 현재 Ceph망 접근 가능, `10.10.10.11:7480` 직접 접근과 AWS S3 업로드를 함께 검증 가능 |
| backup-runner VM          | 향후 권장 | 백업 전용 VM으로 역할 분리, 운영 자동화 개선 대상                                    |
| 온프레 Kubernetes CronJob | 비권장    | 백업 제어 경로가 서비스 런타임 계층에 종속됨                                         |
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

## 6.4 rclone config 예시

`rclone.conf` 예시:

```ini
[cephteam2]
type = s3
provider = Ceph
endpoint = http://10.10.10.11:7480
region = default
acl = private
force_path_style = true

[aws-s3]
type = s3
provider = AWS
env_auth = true
region = ap-northeast-2
acl = private
```

> `10.10.10.11:7480`은 bastion에서 Ceph망으로 직접 접근하는 기본 endpoint임. `172.16.23.60:7480`은
> 신규 백업 경로로 사용하지 않는 deprecated MetalLB RGW bridge endpoint임. Ceph RGW key는
> `rclone.conf`에 넣지 않고 `backup.env`에 둠. AWS key는 bastion의 기존 AWS CLI 인증이 성공하면
> `backup.env`에 넣지 않음. Thanos 도입 시 `[cephthanos]` remote를 같은 방식으로 추가함.

## 6.5 rclone remote 확인과 수동 dry-run

`backup.env`와 `rclone.conf` 작성 후 같은 shell에서 환경변수를 로드함.

```bash
cd /home/ubuntu/backup-test
set -a
. ./backup.env
set +a
```

작업 전 인증 확인:

```bash
# AWS CLI 인증 확인
aws sts get-caller-identity

# AWS S3 backup bucket 접근 확인
aws s3api head-bucket \
  --bucket team2-app-objects-backup \
  --region ap-northeast-2

# Ceph RGW credential 환경변수 로드 확인
[ -n "${RCLONE_CONFIG_CEPHTEAM2_ACCESS_KEY_ID:-}" ] && echo "cephteam2 access key loaded" || echo "missing cephteam2 access key"
[ -n "${RCLONE_CONFIG_CEPHTEAM2_SECRET_ACCESS_KEY:-}" ] && echo "cephteam2 secret key loaded" || echo "missing cephteam2 secret key"

# Ceph RGW remote 접근 확인
rclone lsd cephteam2: --config ./rclone.conf
```

판단 기준:

- `aws sts get-caller-identity` 실패: AWS CLI 인증/profile/환경변수 문제
- `head-bucket` 실패: AWS S3 bucket 권한, bucket 이름, region 문제
- `rclone lsd cephteam2:` 실패: Ceph RGW credential, bucket owner, RGW 권한 문제
- `rclone lsf cephteam2:team2-photo-bucket ... AccessDenied`: AWS가 아니라 Ceph RGW source bucket
  접근 실패
- `backup.env`를 로드하지 않은 새 shell이면 `RCLONE_CONFIG_CEPHTEAM2_*` 환경변수 없음

Ceph RGW remote 확인:

```bash
rclone lsd cephteam2: --config ./rclone.conf
rclone lsf cephteam2:team2-bucket --config ./rclone.conf --recursive | head
rclone size cephteam2:team2-bucket --config ./rclone.conf

rclone lsf cephteam2:team2-photo-bucket --config ./rclone.conf --recursive | head
rclone size cephteam2:team2-photo-bucket --config ./rclone.conf
```

확인 기준:

- `cephteam2` 실패: `RCLONE_CONFIG_CEPHTEAM2_*` 값, `[cephteam2]` section 이름 확인
- `didn't find section in config file`: 명령의 remote 이름과 `rclone.conf` section 이름 불일치
- debug request에 `Authorization` header 없음: rclone credential 환경변수 매핑 실패
- `Config file "/home/ubuntu/.config/rclone/rclone.conf" not found`: `--config ./rclone.conf` 누락

빈 bucket 판단 기준:

```text
rclone lsf ... | head
출력 없음

rclone size ...
Total objects: 0
Total size: 0 B (0 Byte)

rclone copy ... --dry-run --progress
Transferred: 0 B / 0 B
```

권장 확인 순서:

1. `rclone lsf <remote>:<bucket> --config ./rclone.conf --recursive | head`
2. `rclone size <remote>:<bucket> --config ./rclone.conf`
3. `rclone copy ... --config ./rclone.conf --dry-run --progress`
4. 필요 시 Ceph 노드에서 `radosgw-admin bucket stats --bucket <bucket>`

bucket별 확인 명령:

```bash
# App/Object 일반
rclone lsf cephteam2:team2-bucket --config ./rclone.conf --recursive | head
rclone size cephteam2:team2-bucket --config ./rclone.conf

# App/Object 이미지
rclone lsf cephteam2:team2-photo-bucket --config ./rclone.conf --recursive | head
rclone size cephteam2:team2-photo-bucket --config ./rclone.conf

# Thanos 사용 시
rclone lsf cephthanos:thanos-metrics --config ./rclone.conf --recursive | head
rclone size cephthanos:thanos-metrics --config ./rclone.conf
```

`--config ./rclone.conf` 누락 예시:

```text
NOTICE: Config file "/home/ubuntu/.config/rclone/rclone.conf" not found - using defaults
Failed to create file system for "cephteam2:team2-bucket": didn't find section in config file
```

의미:

- 현재 작업 디렉터리의 `./rclone.conf` 미사용
- 기본 경로 `/home/ubuntu/.config/rclone/rclone.conf` 조회
- 기본 config에 `cephteam2` section 없음
- 해결: 모든 rclone 명령에 `--config ./rclone.conf` 추가

Ceph 노드 기준 확인:

```bash
radosgw-admin bucket stats --bucket team2-bucket | grep -E '"num_objects"|"size"'
radosgw-admin bucket stats --bucket team2-photo-bucket | grep -E '"num_objects"|"size"'
radosgw-admin bucket stats --bucket thanos-metrics | grep -E '"num_objects"|"size"'
```

판단:

- `rclone size`의 `Total objects: 0`: 비어 있는 bucket
- `rclone copy --dry-run`의 `Transferred: 0 B / 0 B`: 복사 대상 없음
- `radosgw-admin bucket stats`의 `num_objects: 0`: Ceph RGW 기준 object 없음
- `rclone lsd cephteam2:`에 bucket 이름만 표시: bucket 존재, object 존재 여부는 별도 확인 필요

빈 App/Object bucket이면 테스트 객체를 먼저 업로드함.

```bash
printf 'team2-bucket backup test %s\n' "$(date -Is)" > team2-bucket-backup-test.txt
printf 'team2-photo-bucket backup test %s\n' "$(date -Is)" > team2-photo-bucket-backup-test.txt

rclone copyto ./team2-bucket-backup-test.txt \
  cephteam2:team2-bucket/backup-test/team2-bucket-backup-test.txt \
  --config ./rclone.conf

rclone copyto ./team2-photo-bucket-backup-test.txt \
  cephteam2:team2-photo-bucket/backup-test/team2-photo-bucket-backup-test.txt \
  --config ./rclone.conf

rclone lsf cephteam2:team2-bucket --config ./rclone.conf --recursive | grep '^backup-test/'
rclone lsf cephteam2:team2-photo-bucket --config ./rclone.conf --recursive | grep '^backup-test/'
```

주의:

- 테스트 객체 prefix: `backup-test/`
- 목적: 빈 bucket에서도 dry-run/copy/검증 경로 확인
- 운영 데이터와 구분되는 이름 사용
- 검증 후 삭제 여부 선택

`dry-run`은 실제 복사 전에 어떤 객체가 복사될지 미리 보는 단계임.

- AWS S3에 실제 객체를 만들지 않음
- Ceph RGW 원본도 변경하지 않음
- destination에 없는 객체/변경될 객체 목록을 사전 확인함
- 처음 실행할 때는 반드시 dry-run을 먼저 수행함

App/Object 일반 bucket:

```bash
rclone copy cephteam2:team2-bucket aws-s3:team2-app-objects-backup/team2-bucket \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

App/Object 이미지 bucket:

```bash
rclone copy cephteam2:team2-photo-bucket aws-s3:team2-app-objects-backup/team2-photo-bucket \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

> Thanos 미사용 시 `thanos-metrics`는 제외함. 추후 Thanos 사용 시 `cephthanos` remote와
> `team2-thanos-metrics-backup` bucket을 추가함.

## 6.6 실제 copy-only 실행

`dry-run` 결과가 정상일 때만 실제 copy-only를 실행함.

- Ceph RGW 원본은 유지됨
- AWS S3 destination에 객체가 복사됨
- `rclone copy`는 destination에만 있는 객체를 삭제하지 않음
- 따라서 초기 백업 검증 단계에서는 `sync`, `delete`, `purge`를 사용하지 않음

```bash
rclone copy cephteam2:team2-bucket aws-s3:team2-app-objects-backup/team2-bucket \
  --config ./rclone.conf \
  --progress \
  --checksum

rclone copy cephteam2:team2-photo-bucket aws-s3:team2-app-objects-backup/team2-photo-bucket \
  --config ./rclone.conf \
  --progress \
  --checksum
```

`copy`는 원본에 없는 destination 객체를 삭제하지 않음. 초기 단계에서는 `sync --delete` 성격의 동작을
사용하지 않음.

## 6.7 key 보존 확인

Ceph와 AWS S3에서 같은 key가 유지되는지 확인함.

```bash
rclone lsf cephteam2:team2-bucket --config ./rclone.conf --recursive | head
rclone lsf aws-s3:team2-app-objects-backup/team2-bucket --config ./rclone.conf --recursive | head
aws s3 ls s3://team2-app-objects-backup/team2-bucket/ --recursive --summarize

rclone lsf cephteam2:team2-photo-bucket --config ./rclone.conf --recursive | head
rclone lsf aws-s3:team2-app-objects-backup/team2-photo-bucket --config ./rclone.conf --recursive | head
aws s3 ls s3://team2-app-objects-backup/team2-photo-bucket/ --recursive --summarize
```

확인 기준:

- `Total Objects`: 복사된 object 수
- `Total Size`: 복사된 전체 크기
- App/Object bucket이 원래 비어 있으면 테스트 객체 기준으로 `Total Objects` 증가 확인

테스트 객체 삭제가 필요한 경우:

```bash
rclone deletefile cephteam2:team2-bucket/backup-test/team2-bucket-backup-test.txt \
  --config ./rclone.conf

rclone deletefile cephteam2:team2-photo-bucket/backup-test/team2-photo-bucket-backup-test.txt \
  --config ./rclone.conf

aws s3 rm s3://team2-app-objects-backup/team2-bucket/backup-test/team2-bucket-backup-test.txt
aws s3 rm s3://team2-app-objects-backup/team2-photo-bucket/backup-test/team2-photo-bucket-backup-test.txt
```

> 백업 이력 검증용으로 남길 경우 삭제하지 않음.

## 6.8 Thanos 추가 시 순차 절차

현재 Thanos 미사용 시 이 절차는 건너뜀.

### 6.8.1 Ceph RGW user/bucket 확인

Ceph 노드:

```bash
radosgw-admin user info --uid=thanos
radosgw-admin bucket list --uid=thanos
radosgw-admin bucket stats --bucket thanos-metrics | grep -E '"owner"|"num_objects"|"size"'
```

필요 값:

| 항목            | 값                                           |
| :-------------- | :------------------------------------------- |
| Ceph RGW user   | `thanos`                                     |
| Ceph RGW bucket | `thanos-metrics`                             |
| rclone remote   | `cephthanos`                                 |
| AWS S3 bucket   | `team2-thanos-metrics-backup`                |
| Access Key env  | `RCLONE_CONFIG_CEPHTHANOS_ACCESS_KEY_ID`     |
| Secret Key env  | `RCLONE_CONFIG_CEPHTHANOS_SECRET_ACCESS_KEY` |

### 6.8.2 backup.env 추가

```bash
RCLONE_CONFIG_CEPHTHANOS_ACCESS_KEY_ID="REPLACE_THANOS_RGW_ACCESS_KEY"
RCLONE_CONFIG_CEPHTHANOS_SECRET_ACCESS_KEY="REPLACE_THANOS_RGW_SECRET_KEY"
```

적용:

```bash
cd /home/ubuntu/backup-test
set -a
. ./backup.env
set +a
```

### 6.8.3 rclone.conf 추가

```ini
[cephthanos]
type = s3
provider = Ceph
endpoint = http://10.10.10.11:7480
region = default
acl = private
force_path_style = true
```

### 6.8.4 AWS S3 bucket 준비

```bash
export AWS_REGION=ap-northeast-2

aws s3api create-bucket \
  --bucket team2-thanos-metrics-backup \
  --region ${AWS_REGION} \
  --create-bucket-configuration LocationConstraint=${AWS_REGION}

aws s3api put-bucket-versioning \
  --bucket team2-thanos-metrics-backup \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket team2-thanos-metrics-backup \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### 6.8.5 remote 확인

```bash
rclone lsd cephthanos: --config ./rclone.conf
rclone lsf cephthanos:thanos-metrics --config ./rclone.conf --recursive | head
rclone size cephthanos:thanos-metrics --config ./rclone.conf
```

빈 bucket이면 테스트 객체 업로드:

```bash
printf 'thanos backup test %s\n' "$(date -Is)" > thanos-backup-test.txt

rclone copyto ./thanos-backup-test.txt \
  cephthanos:thanos-metrics/backup-test/thanos-backup-test.txt \
  --config ./rclone.conf

rclone lsf cephthanos:thanos-metrics --config ./rclone.conf --recursive | grep '^backup-test/'
```

### 6.8.6 dry-run

```bash
rclone copy cephthanos:thanos-metrics aws-s3:team2-thanos-metrics-backup \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

### 6.8.7 실제 copy-only

```bash
rclone copy cephthanos:thanos-metrics aws-s3:team2-thanos-metrics-backup \
  --config ./rclone.conf \
  --progress \
  --checksum
```

### 6.8.8 복사 검증

```bash
rclone lsf cephthanos:thanos-metrics --config ./rclone.conf --recursive | head
rclone lsf aws-s3:team2-thanos-metrics-backup --config ./rclone.conf --recursive | head
aws s3 ls s3://team2-thanos-metrics-backup --recursive --summarize
```

테스트 객체 삭제가 필요한 경우:

```bash
rclone deletefile cephthanos:thanos-metrics/backup-test/thanos-backup-test.txt \
  --config ./rclone.conf

aws s3 rm s3://team2-thanos-metrics-backup/backup-test/thanos-backup-test.txt
```

### 6.8.9 Lifecycle 적용

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket team2-thanos-metrics-backup \
  --lifecycle-configuration file://lifecycle-prod.json
```

주의:

- Thanos active bucket 자체를 Glacier로 전환하지 않음
- AWS S3 백업 bucket에만 Lifecycle 적용
- Thanos Compactor 실행 중 운영 bucket in-place 복구 금지
- Glacier 전환 객체는 즉시 조회 불가

## 6.9 AccessDenied 진단

`rclone copy ceph-rgw-<owner>:<bucket> ...`에서 `AccessDenied`가 나오면 네트워크보다 RGW 인증/권한을
먼저 확인함.

확인 순서:

1. `backup.env`의 `RCLONE_CONFIG_CEPHTEAM2_*` 값 확인
2. `set -a; . ./backup.env; set +a` 후 같은 shell에서 rclone 재실행
3. Ceph 노드에서 bucket owner 확인
4. 사용하는 RGW user가 해당 bucket을 list/read 가능한지 확인

Ceph 노드:

```bash
radosgw-admin bucket stats --bucket team2-bucket
radosgw-admin bucket stats --bucket team2-photo-bucket
radosgw-admin user info --uid=team2-admin

# Thanos 사용 시
radosgw-admin bucket stats --bucket thanos-metrics
radosgw-admin user info --uid=thanos
```

bastion:

```bash
cd /home/ubuntu/backup-test
set -a
. ./backup.env
set +a

rclone lsd cephteam2: --config ./rclone.conf
rclone lsf cephteam2:team2-bucket --config ./rclone.conf --recursive | head
rclone lsf cephteam2:team2-photo-bucket --config ./rclone.conf --recursive | head

# Thanos 사용 시
rclone lsd cephthanos: --config ./rclone.conf
rclone lsf cephthanos:thanos-metrics --config ./rclone.conf --recursive | head
```

판단:

- `cephteam2` 전체 실패: `team2-admin` key 오류 또는 list 권한 부족
- `cephthanos` 전체 실패: `thanos` key 오류 또는 list 권한 부족
- 특정 bucket만 실패: bucket owner/정책/권한 불일치
- `team2-bucket`, `team2-photo-bucket` 실패: `team2-admin` user/key 확인
- `thanos-metrics` 실패: `thanos` user/key 확인

---

## 7. bastion VM cron 적용 예시

현재 규모에서는 bastion VM의 OS cron으로 백업을 실행하는 구조가 가장 단순함.

운영 기준:

- 소규모/PoC: cron 사용 가능
- 장기 운영: backup-runner VM + systemd timer 또는 백업 전용 스케줄러 검토
- 현재 문서 기준: bastion VM cron
- 추후 개선 기준: backup-runner VM 이전

🔴 주의:

- Kubernetes CronJob 사용 금지
- 백업 제어 경로와 서비스 런타임 경로 분리
- 현재 실행 위치: bastion VM
- 향후 실행 위치: backup-runner VM
- 기본 RGW endpoint: `http://10.10.10.11:7480`
- Deprecated endpoint: `http://172.16.23.60:7480`
- Secret 포함 파일 저장소 커밋 금지
- 최초 실행 전 반드시 `--dry-run` 검증

## 7.1 백업 스크립트

`object-backup-copy-only.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/home/ubuntu/backup-test"
CONFIG="${WORKDIR}/rclone.conf"
ENV_FILE="${WORKDIR}/backup.env"
LOGDIR="${WORKDIR}/logs"
LOGFILE="${LOGDIR}/object-backup-$(date +%Y%m%d).log"

mkdir -p "${LOGDIR}"

if [ -f "${ENV_FILE}" ]; then
  set -a
  . "${ENV_FILE}"
  set +a
fi

STATUS=0

{
  echo "[START] $(date -Is)"

  echo "[CHECK] RGW endpoint"
  curl -fsI http://10.10.10.11:7480 >/dev/null

  echo "[CHECK] AWS identity"
  aws sts get-caller-identity >/dev/null

  echo "[CHECK] rclone version"
  rclone version

  echo "[COPY] cephteam2:team2-bucket -> aws-s3:team2-app-objects-backup/team2-bucket"
  rclone copy cephteam2:team2-bucket aws-s3:team2-app-objects-backup/team2-bucket \
    --config "${CONFIG}" \
    --checksum \
    --stats 30s

  echo "[VERIFY] s3://team2-app-objects-backup/team2-bucket/"
  aws s3 ls s3://team2-app-objects-backup/team2-bucket/ \
    --recursive \
    --summarize

  echo "[COPY] cephteam2:team2-photo-bucket -> aws-s3:team2-app-objects-backup/team2-photo-bucket"
  rclone copy cephteam2:team2-photo-bucket aws-s3:team2-app-objects-backup/team2-photo-bucket \
    --config "${CONFIG}" \
    --checksum \
    --stats 30s

  echo "[VERIFY] s3://team2-app-objects-backup/team2-photo-bucket/"
  aws s3 ls s3://team2-app-objects-backup/team2-photo-bucket/ \
    --recursive \
    --summarize

  echo "[END] $(date -Is)"
} >> "${LOGFILE}" 2>&1 || STATUS=$?

if [ "${STATUS}" -eq 0 ]; then
  RESULT="SUCCESS"
  MESSAGE="[SUCCESS] object backup command completed on $(hostname) at $(date -Is). S3 summarize was written to log. log=${LOGFILE}"
else
  RESULT="FAILED"
  MESSAGE="[FAILED] object backup command failed on $(hostname) at $(date -Is). Check log. log=${LOGFILE}"
fi

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  curl -fsS -X POST \
    -H "Content-Type: application/json" \
    --data "{\"text\":\"${MESSAGE}\"}" \
    "${SLACK_WEBHOOK_URL}" >/dev/null || true
fi

exit "${STATUS}"
```

Slack 알림 해석:

- `[SUCCESS]`: 스크립트 명령 exit code가 0
- `[SUCCESS]`: `rclone copy`와 `aws s3 ls --summarize` 명령이 실패 없이 종료됨
- `[SUCCESS]`: 로그에 S3 object count/size 출력이 남았다는 의미
- `[SUCCESS]`: 업무적 백업 검증이 자동으로 끝났다는 의미는 아님
- 최종 확인 기준: 로그의 `[VERIFY]` 구간, `Total Objects`, `Total Size`

Thanos 사용 시 아래 복사 줄을 스크립트의 App/Object 복사 다음에 추가함.

```bash
  echo "[COPY] cephthanos:thanos-metrics -> aws-s3:team2-thanos-metrics-backup"
  rclone copy cephthanos:thanos-metrics aws-s3:team2-thanos-metrics-backup \
    --config "${CONFIG}" \
    --checksum \
    --stats 30s

  echo "[VERIFY] s3://team2-thanos-metrics-backup/"
  aws s3 ls s3://team2-thanos-metrics-backup \
    --recursive \
    --summarize
```

스크립트 권한 설정:

```bash
chmod 700 /home/ubuntu/backup-test/object-backup-copy-only.sh
```

## 7.2 수동 실행 검증

Dry-run:

```bash
rclone copy cephteam2:team2-bucket aws-s3:team2-app-objects-backup/team2-bucket \
  --config /home/ubuntu/backup-test/rclone.conf \
  --dry-run \
  --progress

rclone copy cephteam2:team2-photo-bucket aws-s3:team2-app-objects-backup/team2-photo-bucket \
  --config /home/ubuntu/backup-test/rclone.conf \
  --dry-run \
  --progress
```

스크립트 실행:

```bash
/home/ubuntu/backup-test/object-backup-copy-only.sh
tail -n 100 /home/ubuntu/backup-test/logs/object-backup-$(date +%Y%m%d).log
```

## 7.3 cron 등록

테스트 중에는 2분마다 실행함.

```bash
crontab -e
```

테스트용:

```cron
*/2 * * * * /home/ubuntu/backup-test/object-backup-copy-only.sh
```

검증 완료 후 운영용으로 변경함.

운영용 예시:

```cron
0 3 * * 1 /home/ubuntu/backup-test/object-backup-copy-only.sh
```

> `0 3 * * 1`: 매주 월요일 03:00 실행. 일반적으로 사용자 접속이 적은 시간대를 선택함. 백업 주기는
> RPO(Recovery Point Objective)에 맞춰 조정함.

등록 확인:

```bash
crontab -l
```

로그 확인:

```bash
tail -n 100 /home/ubuntu/backup-test/logs/object-backup-$(date +%Y%m%d).log
```

## 7.4 cron 환경 주의

- cron은 로그인 shell 환경을 자동 로드하지 않음
- `aws sts get-caller-identity`가 cron 환경에서도 성공해야 함
- AWS credential은 저장소가 아닌 bastion 사용자 홈, AWS CLI profile, IAM Role, 안전한 비밀 저장소에
  보관
- `aws sts get-caller-identity`가 성공하면 AWS key를 `backup.env`에 중복 저장하지 않음
- `rclone.conf`의 Ceph RGW key 파일 권한 `600` 유지
- `backup.env`의 Slack Webhook URL 파일 권한 `600` 유지
- 장애 확인 기준: log 파일, AWS S3 object count, rclone exit code

## 7.5 알림 선택지

기본 추천: Slack Incoming Webhook

- 장점: SMTP/MTA 설정 불필요
- 장점: `curl`만 있으면 전송 가능
- 단점: Webhook URL을 Secret으로 관리 필요

Mail 참고 선택지:

```bash
sudo apt install -y mailutils
tail -n 80 /home/ubuntu/backup-test/logs/object-backup-$(date +%Y%m%d).log | \
  mail -s "[backup] object backup result" admin@example.com
```

주의:

- `mailutils`만 설치해도 외부 메일 발송이 항상 성공하지 않음
- SMTP relay, SPF/DKIM, 방화벽, 스팸 정책 설정 필요 가능성
- 현재 프로젝트에서는 Slack Webhook 방식이 더 단순함

## 7.6 backup-runner VM 전환 기준

추후 개선 시 bastion에서 backup-runner VM으로 이전함.

전환 조건:

- Ceph망 `10.10.10.0/24` 접근 가능
- AWS S3 outbound 가능
- rclone 설치 완료
- `rclone.conf` 이관 완료
- cron schedule 이관 완료
- bastion cron 비활성화 완료

## 7.7 Deprecated: Kubernetes CronJob

Kubernetes CronJob 방식은 신규 백업 경로로 사용하지 않음.

사유:

- 백업 제어 경로가 서비스 런타임 계층에 종속
- MetalLB/RGW bridge 같은 서비스 노출 계층 경유 가능성
- Secret을 K8s Secret으로 추가 관리해야 하는 부담
- 백업 경로와 서비스 경로 분리 원칙 위반 가능성

---

## 8. 복구 절차

## 8.1 Object bucket 복구 기본 원칙

- 운영 bucket에 바로 덮어쓰지 않음.
- 먼저 test bucket 또는 임시 prefix로 복구함.
- key 구조와 object count/size를 비교함.

예시: AWS S3 backup -> Ceph RGW test bucket

```bash
rclone copy aws-s3:team2-app-objects-backup/team2-bucket cephteam2:team2-bucket-restore-test \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

App/Object 이미지 bucket 복구 예:

```bash
rclone copy aws-s3:team2-app-objects-backup/team2-photo-bucket cephteam2:team2-photo-bucket-restore-test \
  --config ./rclone.conf \
  --dry-run \
  --progress
```

Harbor image 복구 기준:

- S3 object restore 대상 아님
- ECR `library/kosa-tickets:<tag>`에서 pull 가능 여부 확인
- ECR archived image는 Standard로 restore 후 사용
- Harbor로 되돌릴 필요가 있으면 ECR pull 후 Harbor tag/push 수행

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

## 9. Archive 복구 절차

## 9.1 S3 Glacier 객체 복구 절차

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

## 9.2 ECR archive image 복구 절차

ECR archive는 S3 Glacier와 다른 ECR 전용 archive storage class임.

복구 원칙:

- EKS cloud bursting 대상 image는 archive 상태로 두지 않음
- archived image가 필요하면 ECR Standard로 restore 후 pull
- restore 완료 전 Pod image pull 대상 tag로 사용하지 않음
- AWS 기준 ECR archive restore는 보통 20분 이내 완료 기대

상태 확인:

```bash
aws ecr describe-images \
  --repository-name library/kosa-tickets \
  --region ap-northeast-2 \
  --query 'imageDetails[].{tags:imageTags,digest:imageDigest,status:imageStatus,pushed:imagePushedAt,transitioned:imageTransitionedAt}' \
  --output table
```

CLI 복구 예시:

```bash
aws ecr update-image-storage-class \
  --repository-name library/kosa-tickets \
  --image-id imageTag=<TAG> \
  --target-storage-class STANDARD \
  --region ap-northeast-2
```

digest 기준 복구 예시:

```bash
aws ecr update-image-storage-class \
  --repository-name library/kosa-tickets \
  --image-id imageDigest=sha256:<DIGEST> \
  --target-storage-class STANDARD \
  --region ap-northeast-2
```

수동 archive 예시:

```bash
aws ecr update-image-storage-class \
  --repository-name library/kosa-tickets \
  --image-id imageTag=<TAG> \
  --target-storage-class ARCHIVE \
  --region ap-northeast-2
```

UI 복구:

UI 경로:

- AWS Console
- Elastic Container Registry
- Private repositories
- `library/kosa-tickets`
- Images
- archived image 선택
- Restore to standard storage class

주의:

- restore 완료까지 지연 가능
- restore 완료 후 image pull 검증
- restored image는 lifecycle policy 대상이므로 재archive 조건 확인
- burst 직전 필요한 image는 Standard 유지

---

## 10. 검증 체크리스트

| 검증 항목             | 명령/방법                                               | 기대 결과                                             |
| :-------------------- | :------------------------------------------------------ | :---------------------------------------------------- |
| RGW 직접 접근         | `curl -I http://10.10.10.11:7480`                       | `200 OK`, `Ceph Object Gateway`                       |
| Deprecated RGW bridge | `curl -I http://172.16.23.60:7480`                      | 기존 구성 확인 시에만 `200 OK`, `Ceph Object Gateway` |
| Ceph bucket 목록      | `rclone lsd cephteam2:`                                 | 대상 bucket 표시                                      |
| AWS bucket 목록       | `aws s3 ls`                                             | backup bucket 표시                                    |
| Harbor -> ECR mirror  | Harbor Replication execution, `aws ecr describe-images` | ECR repo/tag/digest 표시                              |
| ECR lifecycle preview | `aws ecr get-lifecycle-policy-preview`                  | archive/expire 대상 사전 확인                         |
| Dry-run               | `rclone copy ... --dry-run`                             | 삭제 없이 복사 대상 확인                              |
| Copy-only             | `rclone copy ...`                                       | 원본 유지, destination에 key 생성                     |
| Key 보존              | `rclone lsf ... --recursive`                            | Ceph/AWS key 경로 일치                                |
| AWS 복사량 확인       | `aws s3 ls s3://<bucket> --recursive --summarize`       | Total Objects/Total Size 확인                         |
| Thanos upload         | sidecar log                                             | Thanos 사용 시 block upload 오류 없음                 |
| Thanos Query          | `up{cluster="onprem"}`, `up{cluster="eks"}`             | Thanos 사용 시 양쪽 cluster label 조회                |
| Glacier test          | `head-object`                                           | StorageClass/Restore 상태 확인                        |

---

## 11. 발표용 To-Be 문장

현재 단계:

> 사용자 업로드 객체는 bastion VM에서 Ceph RGW(`10.10.10.11:7480`)에 직접 접근해 AWS S3로 동일 key
> 구조로 복제하는 copy-only 백업을 적용한다. 배포 이미지는 Harbor registry blob을 S3로 중복 백업하지
> 않고, Harbor event-based replication으로 ECR Seoul에 복제해 AWS cloud bursting 시 EKS node가 AWS
> 내부 registry에서 빠르게 pull하도록 구성한다.

향후 단계:

> 검증이 완료되면 DB 메타데이터에 `storage_type`, `bucket`, `object_key`를 관리하도록 확장하고,
> 오래된 객체는 Ceph에서 삭제한 뒤 AWS S3를 직접 조회하는 Tiered Storage 구조로 전환한다. 장기 보관
> 객체 데이터는 S3 Lifecycle을 통해 Glacier로 이동한다. 오래된 container image는 S3 Glacier가 아니라
> ECR Lifecycle을 통해 ECR archive storage class로 전환하고, burst 대상 active image는 ECR
> Standard에 유지한다.

Harbor/ECR 범위 설명:

> Harbor -> ECR replication은 백업이라기보다 AWS cloud bursting의 배포 성능 최적화 경로다. ECR
> 복제본은 image pull 가용성과 속도를 높이지만 Harbor project, user, robot account, replication
> policy 같은 Harbor metadata 전체를 대체하지는 않는다. 따라서 Harbor 설정 백업은 별도 운영 항목으로
> 분리한다.

백업 경로 원칙:

> 백업 제어 경로는 서비스 런타임 경로와 분리한다. K8s/MetalLB에 의존하는 RGW bridge는 deprecated
> 경로로 두고 신규 백업에는 사용하지 않는다. 현재는 Ceph망 접근이 가능한 bastion VM에서 RGW에 직접
> 접근한다. 추후에는 백업 전용 backup-runner VM으로 역할을 분리한다.

DB 범위 설명:

> DB는 현재 PXC 3노드와 Ceph RBD 기반으로 노드/디스크 장애에 대응한다. 다만 이는 논리 삭제나 데이터
> 오염 복구를 위한 백업은 아니므로, 추후 PITR 요구가 생기면 XtraBackup/binlog 기반 DB 백업을 별도
> 도입한다.
