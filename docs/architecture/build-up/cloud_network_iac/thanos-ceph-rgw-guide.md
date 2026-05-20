# Thanos Ceph RGW 가이드

> Status: Unverified 목적: 온프레미스 Prometheus와 EKS Prometheus를 Thanos로 통합하고, 장기 저장소를
> 온프레 Ceph RGW(S3 호환)로 사용하기 위한 설치 절차를 정리함.

---

## 1. 기준 구조

현재 전제:

- AWS VPC와 온프레미스는 Site-to-Site VPN(IPsec Tunnel)으로 연결됨
- AWS VPC CIDR: `10.20.0.0/16`
- 온프레미스 라우팅 CIDR: `172.16.0.0/12`
- Ceph RGW 실제 endpoint: `http://10.10.10.11:7480`
- Ceph RGW는 Ceph storage network(`10.10.10.0/24`)에 있음
- EKS Pod에서 `10.10.10.11:7480`을 직접 접근하지 않고, 온프레 Kubernetes MetalLB bridge IP를 경유함
- MetalLB IPAddressPool: `172.16.23.50-172.16.23.99`
- 이미 사용 중인 LoadBalancer IP:
  - `172.16.23.50`: HAProxy Ingress
  - `172.16.23.51`: Grafana
  - `172.16.23.55`: ProxySQL bridge
- RGW bridge 권장 IP: `172.16.23.60`

권장 구조:

```text
EKS Prometheus + Thanos Sidecar
  → VPN
  → 172.16.23.60:7480 (MetalLB RGW bridge)
  → 10.10.10.11:7480 (Ceph RGW)

OnPrem Prometheus + Thanos Sidecar
  → 172.16.23.60:7480 또는 10.10.10.11:7480
  → Ceph RGW bucket

OnPrem Thanos Query / StoreGateway / Compactor
  → Ceph RGW bucket
  → Grafana datasource
```

> Thanos Query/StoreGateway/Compactor는 온프레 `monitoring` namespace에 설치하는 것을 기본으로 함.
> EKS는 티켓팅 기간 확장용 클러스터이므로, 통합 조회 계층까지 EKS에 두는 것은 현재 목적과 맞지 않음.

---

## 2. 네임스페이스 기준

현재 온프레 Kubernetes에는 `monitoring`, `metallb-system`, `ceph-csi-rbd` 등이 존재함.

권장:

| 용도                                | Namespace    | 이유                                                |
| :---------------------------------- | :----------- | :-------------------------------------------------- |
| RGW bridge Service                  | `monitoring` | Thanos 전용 접근 경로이므로 관측성 구성과 함께 관리 |
| Thanos Query/StoreGateway/Compactor | `monitoring` | 기존 Prometheus/Grafana와 같은 운영 경계            |
| Prometheus Thanos Secret            | `monitoring` | kube-prometheus-stack과 동일 namespace              |

---

## 3. 사전 확인

### 3.1 Kubernetes context 확인

온프레 context 예시:

```bash
kubectl --context kubernetes-admin@kubernetes get ns
```

EKS context 예시:

```bash
kubectl --context <EKS_CONTEXT> get ns
```

> `kubectl --context ...`는 현재 context를 변경하지 않고 해당 명령 1회만 지정 context로 실행함.

### 3.2 MetalLB Pool 확인

```bash
kubectl --context kubernetes-admin@kubernetes -n metallb-system get ipaddresspool -A
kubectl --context kubernetes-admin@kubernetes -n metallb-system get l2advertisement -A
```

기준 출력:

```text
IPAddressPool: lan-pool
Addresses: 172.16.23.50-172.16.23.99
L2Advertisement: lan-l2adv -> lan-pool
```

### 3.3 RGW 확인

Ceph 노드에서:

```bash
curl -I http://10.10.10.11:7480
```

정상 예:

```text
HTTP/1.1 200 OK
Server: Ceph Object Gateway
```

---

## 4. RGW bridge Service 생성

EKS에서 Ceph storage network(`10.10.10.0/24`)를 직접 라우팅하지 않고, 온프레 Kubernetes의 MetalLB
IP(`172.16.23.60`)를 RGW 접속점으로 사용함.

### 4.1 EndpointSlice 방식(권장)

`ceph-rgw-bridge.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ceph-rgw-bridge
  namespace: monitoring
  annotations:
    metallb.io/loadBalancerIPs: 172.16.23.60
spec:
  type: LoadBalancer
  ports:
    - name: rgw
      port: 7480
      targetPort: 7480
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: ceph-rgw-bridge-1
  namespace: monitoring
  labels:
    kubernetes.io/service-name: ceph-rgw-bridge
addressType: IPv4
ports:
  - name: rgw
    protocol: TCP
    port: 7480
endpoints:
  - addresses:
      - "10.10.10.11"
```

적용:

```bash
kubectl --context kubernetes-admin@kubernetes apply -f ceph-rgw-bridge.yaml
```

확인:

```bash
kubectl --context kubernetes-admin@kubernetes -n monitoring get svc ceph-rgw-bridge
kubectl --context kubernetes-admin@kubernetes -n monitoring get endpointslice -l kubernetes.io/service-name=ceph-rgw-bridge
```

정상 기대값:

```text
ceph-rgw-bridge   LoadBalancer   ...   172.16.23.60   7480/TCP
```

### 4.2 Endpoints 방식(구버전 호환)

EndpointSlice가 동작하지 않는 경우에만 사용함.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ceph-rgw-bridge
  namespace: monitoring
  annotations:
    metallb.io/loadBalancerIPs: 172.16.23.60
spec:
  type: LoadBalancer
  ports:
    - name: rgw
      port: 7480
      targetPort: 7480
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: ceph-rgw-bridge
  namespace: monitoring
subsets:
  - addresses:
      - ip: 10.10.10.11
    ports:
      - name: rgw
        port: 7480
        protocol: TCP
```

> Kubernetes `Endpoints` API는 최신 버전에서 deprecated 방향이므로 신규 문서는 EndpointSlice를 우선
> 사용함.

### 4.3 bridge 접근 테스트

온프레 bastion에서:

```bash
curl -I http://172.16.23.60:7480
```

EKS Pod에서:

```bash
kubectl --context <EKS_CONTEXT> run netshoot-rgw --rm -it \
  --image=nicolaka/netshoot \
  --restart=Never -- bash
```

Pod 안에서:

```bash
nc -vz 172.16.23.60 7480
curl -I http://172.16.23.60:7480
```

---

## 5. Thanos용 RGW bucket/user 준비

Bucket 예시:

```text
thanos-metrics
```

### 5.1 기존 RGW key가 있는 경우

기존 Access Key/Secret Key로 bucket 접근이 가능한지 확인함.

```bash
export AWS_ACCESS_KEY_ID=<ACCESS_KEY>
export AWS_SECRET_ACCESS_KEY=<SECRET_KEY>
export AWS_DEFAULT_REGION=default

aws s3 ls --endpoint-url http://172.16.23.60:7480
```

bucket이 없으면 생성:

```bash
aws s3 mb s3://thanos-metrics \
  --endpoint-url http://172.16.23.60:7480 \
  --region default
```

### 5.2 기존 RGW key가 없는 경우

Ceph 노드에서 Thanos 전용 RGW user를 생성함.

```bash
radosgw-admin user create \
  --uid=thanos \
  --display-name="Thanos Metrics"
```

출력의 `access_key`, `secret_key`를 안전한 비밀 저장소에 보관함.

이후 bucket 생성:

```bash
export AWS_ACCESS_KEY_ID=<THANOS_ACCESS_KEY>
export AWS_SECRET_ACCESS_KEY=<THANOS_SECRET_KEY>
export AWS_DEFAULT_REGION=default

aws s3 mb s3://thanos-metrics \
  --endpoint-url http://172.16.23.60:7480 \
  --region default
```

> Access Key/Secret Key를 저장소, 문서, 채팅에 평문으로 남기지 않음.

---

## 6. Thanos objstore Secret 생성

`objstore.yml`:

```yaml
type: S3
config:
  bucket: thanos-metrics
  endpoint: 172.16.23.60:7480
  access_key: <ACCESS_KEY>
  secret_key: <SECRET_KEY>
  insecure: true
  bucket_lookup_type: path
```

옵션 설명:

| 항목                       | 의미                                      |
| :------------------------- | :---------------------------------------- |
| `endpoint`                 | MetalLB RGW bridge 주소                   |
| `insecure: true`           | HTTP endpoint 사용                        |
| `bucket_lookup_type: path` | S3 호환 스토리지에서 path-style 접근 사용 |

Secret 생성은 온프레와 EKS 양쪽 `monitoring` namespace에서 수행함.

온프레:

```bash
kubectl --context kubernetes-admin@kubernetes -n monitoring create secret generic thanos-objstore \
  --from-file=objstore.yml=./objstore.yml
```

EKS:

```bash
kubectl --context <EKS_CONTEXT> create namespace monitoring --dry-run=client -o yaml | \
  kubectl --context <EKS_CONTEXT> apply -f -

kubectl --context <EKS_CONTEXT> -n monitoring create secret generic thanos-objstore \
  --from-file=objstore.yml=./objstore.yml
```

Secret 재생성 시:

```bash
kubectl --context <CONTEXT> -n monitoring delete secret thanos-objstore
kubectl --context <CONTEXT> -n monitoring create secret generic thanos-objstore \
  --from-file=objstore.yml=./objstore.yml
```

---

## 7. EKS Prometheus 설치 + Thanos Sidecar

EKS에 Prometheus가 없다면 `kube-prometheus-stack`부터 설치함.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

`values-eks-prometheus.yaml`:

```yaml
prometheus:
  prometheusSpec:
    retention: 6h
    externalLabels:
      cluster: eks
      region: ap-northeast-2
    thanos:
      objectStorageConfig:
        existingSecret:
          name: thanos-objstore
          key: objstore.yml
```

설치:

```bash
helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack \
  --kube-context <EKS_CONTEXT> \
  -n monitoring --create-namespace \
  -f values-eks-prometheus.yaml
```

확인:

```bash
kubectl --context <EKS_CONTEXT> -n monitoring get pods
kubectl --context <EKS_CONTEXT> -n monitoring logs prometheus-kube-prom-kube-prometheus-prometheus-0 -c thanos-sidecar
```

> 실제 Pod 이름은 Helm release 이름과 chart 버전에 따라 달라질 수 있음.
> `kubectl -n monitoring get pods | grep prometheus`로 확인함.

---

## 8. 온프레 Prometheus에 Thanos Sidecar 추가

온프레에는 이미 `monitoring` namespace와 kube-prometheus-stack이 존재함.

기존 release 이름 확인:

```bash
helm --kube-context kubernetes-admin@kubernetes -n monitoring list
```

`values-onprem-prometheus.yaml`:

```yaml
prometheus:
  prometheusSpec:
    retention: 6h
    externalLabels:
      cluster: onprem
      region: kosa-onprem
    thanos:
      objectStorageConfig:
        existingSecret:
          name: thanos-objstore
          key: objstore.yml
```

업그레이드 예시:

```bash
helm upgrade <ONPREM_KUBE_PROM_RELEASE> prometheus-community/kube-prometheus-stack \
  --kube-context kubernetes-admin@kubernetes \
  -n monitoring \
  -f values-onprem-prometheus.yaml
```

주의:

- `externalLabels.cluster`는 EKS와 온프레가 달라야 함.
- Thanos sidecar object storage를 켜면 Prometheus block 업로드가 주기적으로 발생함.
- 장기 저장 compaction은 Thanos Compactor가 담당함.

---

## 9. 온프레 Thanos Query/StoreGateway/Compactor 설치

Thanos 통합 조회 계층은 온프레 `monitoring` namespace에 설치함.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

`values-thanos.yaml` 예시:

```yaml
existingObjstoreSecret: thanos-objstore

query:
  enabled: true

storegateway:
  enabled: true

compactor:
  enabled: true
  retentionResolutionRaw: 7d
  retentionResolution5m: 30d
  retentionResolution1h: 90d

bucketweb:
  enabled: true

receive:
  enabled: false

ruler:
  enabled: false
```

설치:

```bash
helm upgrade --install thanos bitnami/thanos \
  --kube-context kubernetes-admin@kubernetes \
  -n monitoring \
  -f values-thanos.yaml
```

> Bitnami Thanos chart의 values 키는 chart 버전에 따라 달라질 수 있음. 적용 전
> `helm show values bitnami/thanos | less`로 `existingObjstoreSecret`, `objstoreConfig`, `query`,
> `storegateway`, `compactor` 키를 확인함.

---

## 10. Thanos Query와 Sidecar 연결

### 10.1 같은 클러스터 온프레 sidecar 연결

kube-prometheus-stack이 Thanos discovery Service를 만들었는지 확인:

```bash
kubectl --context kubernetes-admin@kubernetes -n monitoring get svc | grep -i thanos
kubectl --context kubernetes-admin@kubernetes -n monitoring get svc | grep -i prometheus
```

같은 클러스터의 sidecar는 DNS discovery로 연결할 수 있음.

예시:

```yaml
query:
  stores:
    - dnssrv+_grpc._tcp.<ONPREM_THANOS_DISCOVERY_SERVICE>.monitoring.svc.cluster.local
```

### 10.2 EKS sidecar 연결 선택지

EKS는 burst용 클러스터이므로 실시간 sidecar gRPC까지 항상 연결할지 선택해야 함.

| 방식                  | 장점                        | 단점                                        |
| :-------------------- | :-------------------------- | :------------------------------------------ |
| StoreGateway 중심     | gRPC 외부 노출 불필요, 단순 | block 업로드 주기만큼 최신 데이터 지연 가능 |
| EKS sidecar gRPC 노출 | 최신 메트릭 조회 가능       | EKS sidecar `10901` 노출/보안/라우팅 필요   |

초기 권장:

- 1단계: StoreGateway 중심으로 RGW에 업로드된 block 조회
- 2단계: 필요 시 EKS sidecar gRPC를 내부 LoadBalancer/VPN 경로로 연결

---

## 11. Grafana 연동

온프레 Grafana가 이미 `monitoring` namespace에 존재함.

Thanos Query Service 확인:

```bash
kubectl --context kubernetes-admin@kubernetes -n monitoring get svc | grep thanos-query
```

Grafana datasource:

```text
Type: Prometheus
URL: http://thanos-query.monitoring.svc.cluster.local:9090
```

검증 PromQL:

```promql
up
up{cluster="onprem"}
up{cluster="eks"}
```

---

## 12. 검증 체크리스트

### 12.1 RGW bridge

```bash
curl -I http://172.16.23.60:7480
```

EKS Pod:

```bash
kubectl --context <EKS_CONTEXT> run netshoot-rgw --rm -it \
  --image=nicolaka/netshoot \
  --restart=Never -- bash

curl -I http://172.16.23.60:7480
```

### 12.2 S3 bucket

```bash
AWS_ACCESS_KEY_ID=<ACCESS_KEY> \
AWS_SECRET_ACCESS_KEY=<SECRET_KEY> \
AWS_DEFAULT_REGION=default \
aws s3 ls s3://thanos-metrics --endpoint-url http://172.16.23.60:7480
```

### 12.3 Sidecar 로그

```bash
kubectl --context <CONTEXT> -n monitoring logs <PROMETHEUS_POD> -c thanos-sidecar
```

### 12.4 RGW object 업로드 확인

```bash
AWS_ACCESS_KEY_ID=<ACCESS_KEY> \
AWS_SECRET_ACCESS_KEY=<SECRET_KEY> \
AWS_DEFAULT_REGION=default \
aws s3 ls s3://thanos-metrics --endpoint-url http://172.16.23.60:7480 --recursive
```

### 12.5 Thanos Query

```bash
kubectl --context kubernetes-admin@kubernetes -n monitoring port-forward svc/thanos-query 9090:9090
```

브라우저:

```text
http://localhost:9090
```

쿼리:

```promql
up{cluster="onprem"}
up{cluster="eks"}
```

---

## 13. 장애 포인트

| 증상                                      | 가능 원인                                       | 확인                                    |
| :---------------------------------------- | :---------------------------------------------- | :-------------------------------------- |
| EKS Pod에서 `172.16.23.60:7480` 접속 실패 | VPN route, pfSense, MetalLB, EndpointSlice 문제 | `curl`, `kubectl get svc/endpointslice` |
| 온프레에서는 되는데 EKS에서 실패          | AWS route table 또는 pfSense IPsec rule 문제    | EKS netshoot, route table 확인          |
| `AccessDenied`                            | RGW key 권한 문제                               | RGW user/key 확인                       |
| `NoSuchBucket`                            | bucket 미생성                                   | `aws s3 mb`                             |
| Thanos sidecar 업로드 실패                | Secret 형식/endpoint/bucket 문제                | sidecar log                             |
| Thanos Query에서 EKS 지표 안 보임         | block 업로드 지연 또는 sidecar/store 연결 누락  | RGW object list, Query stores 확인      |

---

## 14. 보안 주의

- RGW Access Key/Secret Key는 저장소에 커밋하지 않음.
- `objstore.yml`은 로컬 작업 후 삭제하거나 안전한 비밀 저장소에 보관함.
- `thanos-objstore` Secret은 필요한 namespace에만 생성함.
- RGW bridge는 인터넷에 노출하지 않고 VPN으로 접근 가능한 `172.16.23.60`만 사용함.
- `10.10.10.0/24` Ceph storage network를 AWS에 직접 라우팅하지 않음.
