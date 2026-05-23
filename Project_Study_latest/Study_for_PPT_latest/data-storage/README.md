# 💾 데이터/스토리지 파트 — README

> 이 폴더는 **Ceph + PXC + Redis + RDS** 등 모든 데이터/스토리지 결정을 다룸. 데이터 담당이 deep-dive, 다른 파트도 참조.

---

## 📚 문서 목록

| # | 문서 | 핵심 토픽 |
|---|---|---|
| 01 | `01-ceph-why.md` | 🌟 **왜 Ceph인가?** (대안: NFS/GlusterFS/MinIO/raw NVMe) |
| 02 | `02-network-10g-decision.md` | 🌟 **왜 10G 광케이블?** (대 1G, 비용/효율) |
| 03 | `03-storage-types.md` | RBD vs CephFS vs RGW — 언제 무엇? |
| 04 | `04-s3-comparison.md` | Ceph RGW vs AWS S3 — 비용/효율 비교 |
| 05 | `05-pxc-redis.md` | Percona XtraDB Cluster + Redis Sentinel |
| 06 | `06-rds-replication.md` | PXC binlog → AWS RDS external replica |

---

## 🎯 데이터 담당이 마스터해야 할 6가지

1. **왜 Ceph + 별도 클러스터?** → 01
2. **왜 10G 광케이블?** → 02
3. **3-replica vs Erasure Coding 언제 골라야?** → 03
4. **Ceph RGW가 AWS S3와 어떻게 호환되나?** → 04
5. **PXC operator로 한 이유? bitnami helm 안 쓴 이유?** → 05
6. **RDS external replica가 native replica와 어떻게 다른가?** → 06

---

## 🤝 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 아키텍처 | Ceph 토폴로지가 K8s/Network 설계에 영향 (`architecture/01`) |
| 🔧 CI/CD | Harbor backend Ceph RGW (`cicd/03-harbor-registry.md`) |
| 🔒 보안 | DB 데이터 보호, 백업 암호화, replication 인증 (`security/08-backup-dr-policy.md`) |

---

## 🧪 자가 테스트

```
□ Ceph mon 1대 죽으면? 2대 죽으면?
□ OSD 1개 죽으면 데이터 영향?
□ 왜 BlueStore? FileStore와 차이?
□ Ceph RGW down 시 Harbor 영향?
□ PXC node 1대 죽으면? 2대 죽으면?
□ Redis Sentinel quorum 깨지면?
□ RDS replica가 1시간 lag면 EKS Pod 영향?
```
