# 🔧 CI/CD 파트 — README

> 이 폴더는 **Jenkins + Harbor + ArgoCD + GitOps** 결정과 trade-off를 다룸.

---

## 📚 문서 목록

| # | 문서 | 핵심 토픽 |
|---|---|---|
| 01 | `01-jenkins-vs-github-actions.md` | ⭐ Jenkins vs GHA 깊이 비교 (8 차원) |
| 02 | `02-jenkins-trigger-modes.md` | SCM Polling vs Webhook vs Self-hosted runner |
| 03 | `03-jenkins-build-tools.md` | Kaniko vs Docker vs Buildah |
| 04 | `04-harbor-registry.md` | Harbor + Ceph RGW 백엔드 |
| 05 | `05-argocd-gitops.md` | App-of-Apps 패턴 |
| 06 | `06-pipeline-flow.md` | E2E 흐름 (push → deploy) |

---

## 🎯 CI/CD 담당이 마스터해야 할 6가지

1. **왜 Jenkins (GHA 안 쓰고)?** → 01
2. **왜 SCM Polling (Webhook 안 쓰고)?** → 02
3. **왜 Kaniko (Docker 안 쓰고)?** → 03
4. **Harbor 왜 자체 호스팅?** → 04
5. **App-of-Apps 패턴이 뭔지?** → 05
6. **commit 1번에 deploy까지 어떻게 흐르나?** → 06

---

## 🤝 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 데이터 | Harbor → Ceph RGW backend |
| 🏛️ 아키텍처 | Jenkins/Harbor/ArgoCD가 sys1에 배치 |
| 🔒 보안 | Jenkins credentials, K8s RBAC, image scan |

---

## 🧪 자가 테스트

```
□ git push 후 새 image가 production Pod에 뜨기까지 N초?
□ ArgoCD가 OutOfSync인데 Healthy면 무슨 의미?
□ Kaniko는 왜 root 안 써도 image build 가능?
□ Harbor Trivy 스캔 false positive 어떻게 처리?
□ Jenkins agent Pod이 Pending이면 어디부터?
□ ArgoCD가 helm chart에 보낸 values를 실제 cluster가 안 받으면 (sync 안 됨)?
```
