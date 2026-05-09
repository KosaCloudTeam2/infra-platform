# 02 DB / Storage Implementation

담당: 팀원 3

## 1. 목표

EC2 기반 Percona XtraDB Cluster(PXC), ProxySQL, Percona XtraBackup, Ceph RGW 백업 흐름을 구현함. DB
관련 온프레미스 네트워크 기준을 함께 정리하고, 앱은 PXC 노드가 아니라 ProxySQL endpoint로만 DB에
접근하도록 구성함.

## 2. 사전 조건

- Cloud/Network/IaC 담당자로부터 PXC/ProxySQL EC2 private IP와 SSM 접속 방식 인계
- PXC SG, ProxySQL SG가 내부망 기준으로 제한되어 있음
- Ceph RGW endpoint, bucket, access key 전달 방식 확정
- DB 비밀번호와 Ceph key는 저장소에 기록하지 않음

## 3. 구현 순서

1. DB 관련 온프레미스 네트워크 정책(pfSense/VLAN/라우팅/방화벽) 확인
2. PXC 노드 3대 접속 가능 여부 확인
3. PXC 설치 및 Galera cluster bootstrap
4. `wsrep_cluster_status`, `wsrep_cluster_size` 확인
5. 앱 전용 DB와 계정 생성
6. ProxySQL 설치 및 Writer/Reader hostgroup 구성
7. ProxySQL user, backend server, query rule 저장
8. Observability 담당자에게 ProxySQL endpoint와 DB 접속 Secret 전달 방식 인계
9. XtraBackup 백업 파일 생성
10. 체크섬 생성 후 Ceph RGW 업로드
11. 장애/복구 Runbook에 실제 명령과 결과 반영

## 4. PXC 확인 명령

```sql
SHOW STATUS LIKE 'wsrep_cluster_status';
SHOW STATUS LIKE 'wsrep_cluster_size';
SHOW STATUS LIKE 'wsrep_local_state_comment';
```

완료 기준:

- `wsrep_cluster_status = Primary`
- `wsrep_cluster_size = 3`
- 각 노드 `wsrep_local_state_comment = Synced`

## 5. ProxySQL 구현 기준

- 앱 접속 포트는 `6033`
- Admin 포트 `6032`는 SSM/Bastion 경유로만 접근
- Writer hostgroup과 Reader hostgroup을 분리
- 설정 변경 후 runtime과 disk에 모두 저장

```sql
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
```

## 6. 백업 검증

```powershell
# 실제 명령은 설치 경로와 백업 정책 확정 후 Runbook에 기록
xtrabackup --backup --target-dir=<backup_dir>
Get-FileHash <backup_file>
```

Ceph RGW 업로드 후 확인 항목:

- 백업 파일명
- 체크섬 파일
- 업로드 bucket 경로
- 업로드 시각
- 복구 리허설 가능 여부

## 7. 장애 시나리오

- PXC 노드 1대 중지 후 cluster size 변화 확인
- ProxySQL backend status에서 장애 노드 제외 여부 확인
- ProxySQL 1대 장애 시 앱 DB 접속이 중단되는 한계 기록
- 이중화 적용 시 Internal NLB Target Group healthy 상태 확인

## 8. 산출물

- PXC 상태 확인 결과
- ProxySQL backend/user/query rule 요약
- 앱 DB 접속 Secret 이름 또는 전달 방식
- XtraBackup 산출물 경로
- Ceph RGW 업로드 경로와 체크섬
- DB 장애/복구 Runbook 업데이트

## 9. 주의 사항

- PXC는 Single Writer 운영 기준을 우선함
- ProxySQL 1대는 MVP 기준이며 운영 권장 구성이 아님
- Ceph는 주 DB 디스크가 아니라 백업/객체 저장소 용도로 설명함
- DB 비밀번호, Ceph access key, secret key는 문서와 Terraform state에 남기지 않음
