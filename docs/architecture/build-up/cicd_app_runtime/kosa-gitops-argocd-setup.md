# Argo CD GitOps 테스트 구현 과정

대상 저장소: `/home/ubuntu/kosa-gitops`

문서 목적: `/home/ubuntu/kosa-gitops`의 YAML 파일 기준으로 Argo CD GitOps 테스트 과정 정리. Jenkins, Harbor 등 Argo CD 자체 테스트 범위를 벗어나는 개별 서비스 구축/장애 처리 내용 제외.

## 1. 테스트 대상 YAML 구조 확인

관련 디렉토리 구조:

```text
kosa-gitops/
├── bootstrap/
│   └── root-app.yaml
└── apps/
    ├── _applications/
    │   ├── auto-demo.yaml
    │   ├── cert-manager.yaml
    │   ├── cert-manager-issuer.yaml
    │   ├── demo-nginx.yaml
    │   ├── harbor.yaml
    │   ├── jenkins.yaml
    │   ├── monitoring.yaml
    │   ├── redis.yaml
    │   └── ticket-app.yaml
    ├── auto-demo/
    │   └── all.yaml
    ├── cert-manager/
    │   └── cert-manager.yaml
    ├── cert-manager-issuer/
    │   ├── ca-secret.yaml
    │   └── clusterissuer.yaml
    ├── demo-nginx/
    │   └── all.yaml
    ├── monitoring/
    │   ├── application.yaml
    │   └── values.yaml
    ├── redis/
    │   ├── application.yaml
    │   └── values.yaml
    └── ticket-app/
        ├── deployment.yaml
        ├── ingress.yaml
        ├── namespace.yaml
        └── service.yaml
```

확인 명령어:

```bash
# 저장소 디렉토리로 이동
cd /home/ubuntu/kosa-gitops

# 저장소 최상위 구조 확인
ls

# apps 하위 디렉토리 확인
ls apps/

# Argo CD 하위 Application YAML 목록 확인
ls apps/_applications/

# root-app 설정 확인
cat bootstrap/root-app.yaml
```

확인 내용:

- `bootstrap/root-app.yaml`: Argo CD 최상위 Application.
- `root-app`: `apps/_applications/` 경로 참조.
- `apps/_applications/*.yaml`: 하위 Argo CD Application 역할.

## 2. Argo CD Pod 및 서비스 상태 확인

관련 디렉토리 구조:

```text
kosa-gitops/
└── bootstrap/
    └── root-app.yaml
```

확인 명령어:

```bash
# Argo CD 구성 Pod 상태 확인
kubectl get pods -n argocd

# Argo CD Server Service 확인
kubectl -n argocd get svc argocd-server

# Argo CD Application 목록 확인
kubectl -n argocd get app
```

정상 기준:

```text
argocd-application-controller      Running
argocd-applicationset-controller   Running
argocd-dex-server                  Running
argocd-notifications-controller    Running
argocd-redis                       Running
argocd-repo-server                 Running
argocd-server                      Running
```

현재 확인 결과:

```text
argocd-application-controller-0                    1/1 Running
argocd-applicationset-controller-5b654ff98-wxsxf   1/1 Running
argocd-dex-server-694dfd7fc5-722vm                 1/1 Running
argocd-notifications-controller-58c5965756-ppsfp   1/1 Running
argocd-redis-6b6f94d995-gssjp                      1/1 Running
argocd-repo-server-ddfd59675-r9zpn                 1/1 Running
argocd-server-5d99678b59-glbkz                     1/1 Running
```

## 3. Argo CD UI 접속 확인

관련 디렉토리 구조:

```text
kosa-gitops/
└── bootstrap/
    └── root-app.yaml
```

접속 명령어:

```bash
# argocd-server를 8080 포트로 외부 접속 가능하게 포트포워딩
kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8080:443
```

브라우저 접속:

```text
https://<master-node-ip>:8080
```

접속 확인 로그:

```text
Forwarding from 0.0.0.0:8080 -> 8080
Handling connection for 8080
```

초기 admin password 확인:

```bash
# Argo CD 초기 admin 비밀번호 조회
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

확인 내용:

- Argo CD UI 접속 성공.
- `root-app` 카드 확인.
- Application 상태 화면 진입 가능.

## 4. root-app 적용 및 App-of-Apps 동작 확인

관련 디렉토리 구조:

```text
kosa-gitops/
├── bootstrap/
│   └── root-app.yaml
└── apps/
    └── _applications/
        ├── auto-demo.yaml
        ├── cert-manager.yaml
        ├── cert-manager-issuer.yaml
        ├── demo-nginx.yaml
        ├── monitoring.yaml
        ├── redis.yaml
        └── ticket-app.yaml
```

적용 및 확인 명령어:

```bash
# root-app Application 생성
kubectl apply -f /home/ubuntu/kosa-gitops/bootstrap/root-app.yaml

# root-app 상태 확인
kubectl -n argocd get app root-app

# root-app 상세 이벤트 및 sync 상태 확인
kubectl -n argocd describe app root-app

# root-app이 생성한 하위 Application 목록 확인
kubectl -n argocd get app
```

확인 내용:

- `root-app`의 `apps/_applications/` 경로 읽기 확인.
- 하위 Application의 Argo CD 생성 확인.
- 핵심 기준: 전체 앱 Healthy 여부가 아닌, Git repo 읽기 및 Application 리소스 생성 여부 확인.

## 5. Argo CD Refresh 및 Sync 테스트

관련 디렉토리 구조:

```text
kosa-gitops/
└── apps/
    └── _applications/
        ├── auto-demo.yaml
        ├── cert-manager.yaml
        ├── cert-manager-issuer.yaml
        ├── demo-nginx.yaml
        ├── monitoring.yaml
        ├── redis.yaml
        └── ticket-app.yaml
```

테스트 명령어:

```bash
# root-app이 Git repo 상태를 다시 읽도록 hard refresh 수행
kubectl -n argocd annotate app root-app argocd.argoproj.io/refresh=hard --overwrite

# root-app 수동 sync 실행
kubectl -n argocd patch app root-app --type=merge -p '{"operation":{"sync":{}}}'

# 전체 Application 상태 확인
kubectl -n argocd get app

# Application 상태 변화 실시간 확인
kubectl -n argocd get app -w
```

개별 Application sync 예시:

```bash
# demo-nginx Application 수동 sync
kubectl -n argocd patch app demo-nginx --type=merge -p '{"operation":{"sync":{}}}'

# auto-demo Application 수동 sync
kubectl -n argocd patch app auto-demo --type=merge -p '{"operation":{"sync":{}}}'
```

확인 내용:

- Argo CD의 Git 변경사항 감지 확인.
- `OutOfSync` 상태의 수동 sync 반영 확인.
- `root-app` sync를 통한 하위 Application 변경사항 관리 확인.

## 6. Git 변경사항 반영 테스트

관련 디렉토리 구조:

```text
kosa-gitops/
└── apps/
    ├── _applications/
    │   ├── demo-nginx.yaml
    │   └── auto-demo.yaml
    ├── demo-nginx/
    │   └── all.yaml
    └── auto-demo/
        └── all.yaml
```

Git 반영 명령어:

```bash
# 저장소 디렉토리로 이동
cd /home/ubuntu/kosa-gitops

# 변경 파일 확인
git status

# 변경한 Application YAML stage
git add apps/_applications/<app>.yaml

# 변경사항 commit
git commit -m "<commit message>"

# 원격 저장소로 push
git push
```

Argo CD 반영 확인:

```bash
# root-app hard refresh로 Git 변경사항 즉시 감지
kubectl -n argocd annotate app root-app argocd.argoproj.io/refresh=hard --overwrite

# 전체 Application 상태 확인
kubectl -n argocd get app

# 변경한 Application 상태 확인
kubectl -n argocd get app <app-name>

# 변경한 Application 상세 확인
kubectl -n argocd describe app <app-name>
```

확인 내용:

- Git push 이후 Argo CD의 변경사항 인식 확인.
- hard refresh를 통한 즉시 갱신 가능 여부 확인.
- Git repository의 desired state 역할 확인.

## 7. selfHeal 및 prune 동작 확인

관련 디렉토리 구조:

```text
kosa-gitops/
└── apps/
    ├── _applications/
    │   ├── demo-nginx.yaml
    │   └── auto-demo.yaml
    ├── demo-nginx/
    │   └── all.yaml
    └── auto-demo/
        └── all.yaml
```

selfHeal 테스트 예시:

```bash
# 클러스터 리소스를 수동 변경해서 Git 상태와 차이를 만듦
kubectl scale deployment -n demo <deployment-name> --replicas=0

# Argo CD가 차이를 감지했는지 확인
kubectl -n argocd get app demo-nginx

# selfHeal 이후 Pod 상태 확인
kubectl get pods -n demo
```

prune 확인용 상태 조회:

```bash
# demo-nginx Application sync/prune 상태 확인
kubectl -n argocd get app demo-nginx

# demo-nginx 상세 상태와 이벤트 확인
kubectl -n argocd describe app demo-nginx

# demo namespace 리소스 확인
kubectl get all -n demo
```

확인 내용:

- Git 정의 상태와 클러스터 상태 차이 감지 확인.
- `selfHeal: true` Application의 Git 상태 복구 동작 확인.
- `prune: true` Application의 Git 삭제 리소스 클러스터 정리 동작 확인.

## 8. 최종 점검

관련 디렉토리 구조:

```text
kosa-gitops/
├── bootstrap/
│   └── root-app.yaml
└── apps/
    ├── _applications/
    │   ├── auto-demo.yaml
    │   ├── cert-manager.yaml
    │   ├── cert-manager-issuer.yaml
    │   ├── demo-nginx.yaml
    │   ├── monitoring.yaml
    │   ├── redis.yaml
    │   └── ticket-app.yaml
    ├── auto-demo/
    │   └── all.yaml
    ├── cert-manager/
    │   └── cert-manager.yaml
    ├── cert-manager-issuer/
    │   ├── ca-secret.yaml
    │   └── clusterissuer.yaml
    ├── demo-nginx/
    │   └── all.yaml
    ├── monitoring/
    │   ├── application.yaml
    │   └── values.yaml
    ├── redis/
    │   ├── application.yaml
    │   └── values.yaml
    └── ticket-app/
        ├── deployment.yaml
        ├── ingress.yaml
        ├── namespace.yaml
        └── service.yaml
```

점검 명령어:

```bash
# 전체 Argo CD Application 상태 확인
kubectl -n argocd get app

# Argo CD 구성 Pod 상태 확인
kubectl get pods -n argocd

# Running/Completed가 아닌 Pod만 확인
kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed" {print}'

# 전체 Service 확인
kubectl get svc -A

# 전체 Ingress 확인
kubectl get ingress -A
```

## 9. 제외한 내용

제외 기준: Argo CD 테스트 흐름과 직접 관련이 낮은 항목 제외.

제외 항목:

- Jenkins 설치, Jenkins chart 수정, Jenkins admin 계정 확인.
- Harbor 설치, Harbor S3 backend, Docker push 테스트.
- Ceph RGW bucket 생성 및 S3 access key 관련 명령.
- HAProxy 외부 라우팅 수정.
- Proxmox VM 재기동, worker 노드 장애 테스트.
- Redis/PXC/Monitoring의 개별 장애 복구 상세.
- VolumeAttachment finalizer 강제 삭제 상세.
- 특정 서비스 비밀번호, Secret, Access Key 값.

## 10. 핵심 요약

관련 디렉토리 구조:

```text
kosa-gitops/
├── bootstrap/
│   └── root-app.yaml
└── apps/
    ├── _applications/
    │   ├── auto-demo.yaml
    │   ├── cert-manager.yaml
    │   ├── cert-manager-issuer.yaml
    │   ├── demo-nginx.yaml
    │   ├── monitoring.yaml
    │   ├── redis.yaml
    │   └── ticket-app.yaml
    ├── auto-demo/
    ├── cert-manager/
    ├── cert-manager-issuer/
    ├── demo-nginx/
    ├── monitoring/
    ├── redis/
    └── ticket-app/
```

정리:

- `bootstrap/root-app.yaml`로 Argo CD App-of-Apps 구조 구성.
- `root-app`은 `apps/_applications/` 경로를 바라보며 하위 Application 관리.
- Argo CD UI 접속은 `argocd-server` port-forward로 확인.
- `kubectl apply`, `annotate refresh`, `patch sync` 명령으로 root-app 적용과 동기화 테스트.
- Git push 후 Argo CD의 변경사항 감지 여부 확인.
- `selfHeal`과 `prune` 설정으로 Git desired state 기반 복구/정리 동작 검증.
- 최종적으로 Argo CD 구성 Pod가 모두 `Running` 상태인 것을 확인.
