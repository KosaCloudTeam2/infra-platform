# DB 및 Ceph Runbook

Percona XtraDB Cluster, ProxySQL, Ceph RGW 백업 검증 절차

---

## 1. 구성 목표

- AWS RDS 없이 EC2 기반 Percona XtraDB Cluster 3노드 구성
- 애플리케이션은 ProxySQL을 통해서만 DB 접근
- DB/ProxySQL EC2는 Private Data Subnet에만 배치하고 Public IP를 부여하지 않음
- Percona XtraBackup 결과를 Ceph RGW에 저장
- 장애 발생 시 ProxySQL backend 상태와 PXC 클러스터 상태를 기준으로 복구
- PXC는 Galera/wsrep 기반이지만 MVP 운영 정책은 active-active write가 아니라 Single Writer로 제한
- 온프레미스 스토리지는 Proxmox 기반 Ceph를 사용하되, AWS 앱과 DB 백업은 RGW의 S3 호환 API로만 연동

---

## 2. 책임 경계

| 작업                    | 주 담당                                | 설명                                                     |
| :---------------------- | :------------------------------------- | :------------------------------------------------------- |
| DB용 EC2 Terraform 골격 | Cloud/Network/IaC                      | Data Private Subnet, SG, SSM Role, EC2 생성              |
| PXC 설치/클러스터 구성  | DB/Storage                             | DB 패키지, Galera 설정, 계정/권한                        |
| ProxySQL 구성           | DB/Storage                             | hostgroup, query rule, backend health                    |
| 앱-DB 연결              | CI/CD/App Runtime + DB/Storage         | Kubernetes Secret/환경변수와 ProxySQL endpoint 접속 검증 |
| DB 포트 정책            | Cloud/Network/IaC + DB/Storage         | `6033`, `3306`, `4567/4568/4444`, `6032` 허용 범위 리뷰  |
| Proxmox/Ceph 운영 경계  | DB/Storage + Observability/Integration | Proxmox 관리 UI 비공개, RGW endpoint 접근 경로 결정      |

---

## 3. 상태 확인

### PXC 클러스터

PXC는 Galera 계열 동기식 복제를 사용하므로 여러 노드에 쓰기가 가능한 multi-primary 구조를 지원함.
하지만 MVP에서는 쓰기 충돌과 장애 분석 복잡도를 줄이기 위해 ProxySQL 기준 Single Writer로 운영함.
별도의 Galera Cluster를 추가로 구축하지 않으며, PXC 패키지 안의 Galera/wsrep 기능을 사용함.

`garbd`는 Galera Arbitrator Daemon으로 데이터를 저장하지 않는 quorum 보조 구성원임. 현재 PXC 3노드
기준에서는 필수 아님. 2노드 제약이 생기는 경우에만 향후 논의함.

```sql
SHOW STATUS LIKE 'wsrep_cluster_status';
SHOW STATUS LIKE 'wsrep_cluster_size';
SHOW STATUS LIKE 'wsrep_local_state_comment';
```

정상 기준

- `wsrep_cluster_status = Primary`
- `wsrep_cluster_size = 3`
- `wsrep_local_state_comment = Synced`

### ProxySQL

```sql
SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers;
SELECT * FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 10;
```

확인 기준

- Writer 노드가 정상 hostgroup에 존재함
- 장애 노드는 `SHUNNED` 또는 제외 상태로 전환 가능함

---

## 4. 백업 절차

백업 기준:

- MVP RPO: 1일 이내 복구 지점 확보
- MVP RTO: 발표 시연 기준 1시간 이내 복구 절차 설명 가능
- 보관 기준: 로컬 임시 백업 최근 3일, Ceph RGW 최근 7일 이상
- 중요 백업: 발표 안정화 이후 AWS S3 2차 복제 검토
- 검증 기준: 파일 크기, 체크섬, bucket 목록, 복구 리허설 중 최소 1개 확인

1. 백업 대상 PXC 노드 상태 확인
2. Percona XtraBackup 실행
3. 백업 파일 압축 및 체크섬 생성
4. Ceph RGW bucket 업로드
5. 업로드 파일 목록과 체크섬 확인

예시 흐름

```bash
xtrabackup --backup --stream=xbstream --user="$BACKUP_USER" --password="$BACKUP_PASSWORD" \
  | gzip > full-backup.xbstream.gz

sha256sum full-backup.xbstream.gz > full-backup.sha256

aws --endpoint-url "$CEPH_RGW_ENDPOINT" s3 cp full-backup.xbstream.gz \
  "s3://pxc-backup/cloud-infra-dev/$(date +%F)/full-backup.xbstream.gz"

aws --endpoint-url "$CEPH_RGW_ENDPOINT" s3 cp full-backup.sha256 \
  "s3://pxc-backup/cloud-infra-dev/$(date +%F)/full-backup.sha256"
```

복구 검증 기준:

- 체크섬 파일로 백업 무결성 확인
- 임시 복구 노드 또는 로컬 테스트 환경에서 복구 절차 1회 리허설
- 복구 리허설이 어렵다면 백업 목록, 체크섬, 복구 명령을 발표 캡처로 확보
- Proxmox VM 백업은 PXC 논리 백업 대체 수단으로 설명하지 않음

---

## 5. 장애 시나리오

### PXC 노드 1대 장애

1. 장애 노드 중지
2. ProxySQL backend 상태 확인
3. 앱 DB 요청 정상 여부 확인
4. 남은 PXC 노드에서 `wsrep_cluster_size` 확인
5. 장애 노드 재기동 후 `Synced` 상태 복귀 확인

### ProxySQL 장애

- MVP에서 ProxySQL 1대만 구성한 경우 DB 접근 단일 장애점(SPoF)이 됨
- 안정성 보완 구성은 ProxySQL 2대 + Internal NLB
- Terraform 전환값은 `proxysql_count = 2`, `enable_proxysql_internal_nlb = true`
- 이중화 구성에서는 앱 `DB_HOST`를 개별 ProxySQL private IP가 아니라 Internal NLB DNS로 설정함
- 두 ProxySQL 인스턴스의 `mysql_servers`, `mysql_users`, `mysql_query_rules` 설정이 일치해야 함
- Internal NLB Health Check는 TCP 연결만 확인하므로 PXC backend 라우팅 정상 여부는 ProxySQL Admin
  쿼리로 별도 확인함
- 발표 시 MVP 한계와 보완안을 명확히 설명함

확인 명령

```sql
SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers;
SELECT username, active FROM runtime_mysql_users;
SELECT rule_id, active, match_pattern, destination_hostgroup FROM runtime_mysql_query_rules;
```

### Ceph RGW 장애

- 앱 파일 업로드 또는 백업 업로드 실패 여부 확인
- 백업은 로컬 임시 저장 후 RGW 복구 뒤 재업로드
- 중요 백업은 AWS S3 2차 복제 고려

### Proxmox 또는 온프레미스 장애

- Proxmox 관리 UI 장애와 Ceph RGW 장애를 구분함
- Proxmox VM 백업은 PXC 논리 백업을 대체하지 않음
- Ceph RGW가 중단되면 DB 백업 산출물은 임시 로컬 경로에 보관한 뒤 복구 후 재업로드함
- Proxmox/Ceph 관리망 장애는 AWS burst 앱 실행에는 직접 영향을 주지 않아야 함
- AWS 앱이 Ceph RGW에 파일 업로드를 직접 수행하는 경우, RGW 장애 시 앱 기능 저하 범위를 별도로
  기록함

---

## 6. 발표 시연 체크리스트

- [ ] 앱이 ProxySQL endpoint로 DB에 접근함
- [ ] DB EC2와 ProxySQL EC2에 Public IP가 없음
- [ ] DB 관련 포트가 인터넷에 열려 있지 않음
- [ ] PXC 클러스터 상태가 `Primary`, `Synced`임
- [ ] Percona XtraBackup 산출물이 생성됨
- [ ] Ceph RGW bucket에 백업 파일과 체크섬이 존재함
- [ ] Proxmox 관리 UI가 인터넷에 공개되어 있지 않음
- [ ] AWS에서 사용하는 온프레미스 endpoint가 Ceph RGW로 제한되어 있음
- [ ] PXC 노드 1대 장애 시 앱 요청이 유지되거나 장애 범위가 설명 가능함
- [ ] ProxySQL 1대 구성의 한계와 2대 + Internal NLB 확장안을 설명함
