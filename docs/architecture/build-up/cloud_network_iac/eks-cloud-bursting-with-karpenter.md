# EKS Cloud Bursting (Karpenter 포함) A to Z

> Status: Unverified

> 목적: **예측 불가 트래픽 급증**까지 대응하기 위해 EventBridge Scheduler + Lambda(예약 사전 확장) +
> Karpenter(실시간 Pending Pod 대응) 조합을 구현함.
>
> 분류: **선택 확장(고도화)**

---

## 1. 이 방식이 필요한 경우

아래 조건이면 without-karpenter보다 with-karpenter가 유리함.

- 이벤트 시간대 외에도 급격한 트래픽 변동이 자주 발생
- 예약한 노드 용량을 초과하는 Pending Pod가 반복 발생
- Spot 우선 비용 최적화 + 불가 시 On-Demand fallback이 필요

---

## 2. 아키텍처

```mermaid
flowchart LR
    A[EventBridge Scheduler] --> B[Lambda: baseline MNG pre-scale]
    B --> C[EKS Managed Node Group(On-Demand baseline)]
    D[App Traffic Spike] --> E[Pending Pods]
    E --> F[Karpenter]
    F --> G[EC2 Nodes Spot 우선 / On-Demand fallback]
    G --> H[Pod Scheduling]
```

핵심:

- **예약형 피크**: Lambda가 MNG를 사전 확장(30분 전)
- **예측 불가 초과분**: Karpenter가 Spot 우선으로 노드 추가
- **Spot 불가 시**: 동일 NodePool에서 On-Demand로 fallback

---

## 3. 실행 위치와 사전 설치

## 3.1 실행 위치

- 권장: AWS CloudShell
- 대안: 로컬(Windows/Linux/macOS)

## 3.2 필수 도구

- AWS CLI v2
- kubectl
- eksctl
- Helm
- jq

## 3.3 설치 방법

### CloudShell

```bash
aws --version
kubectl version --client
eksctl version || true
helm version || true
jq --version
```

`eksctl`, `helm`이 없으면 설치:

```bash
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Windows

```powershell
winget install --id Amazon.AWSCLI -e
winget install --id Kubernetes.kubectl -e
choco install eksctl -y
choco install kubernetes-helm -y
```

---

## 4. IAM/OIDC 및 권한 준비

## 4.1 클러스터 OIDC 연결

```bash
export CLUSTER_NAME=ticket-burst-eks
export AWS_REGION=ap-northeast-2

eksctl utils associate-iam-oidc-provider \
  --cluster ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --approve
```

## 4.2 Karpenter Controller 권한

- Karpenter 공식 가이드 기준 IAM 정책/역할 생성 절차를 사용
- Controller는 IRSA(ServiceAccount 연동 IAM Role)로 AWS API 접근

> 참고: Karpenter 버전에 따라 정책 템플릿/설치 값이 달라질 수 있으므로 적용 시점의 공식 문서 버전을
> 반드시 확인함.

---

## 5. EKS baseline (MNG)

Karpenter만으로 시작하지 않고, 안정적 베이스라인 MNG를 유지함.

```bash
eksctl create cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --version 1.34 \
  --nodegroup-name base-ng \
  --node-type m6i.large \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 10 \
  --managed

aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
kubectl get nodes
```

---

## 6. Karpenter 설치

```bash
export KARPENTER_NAMESPACE=kube-system
# 예: 1.8.0 (적용 시점 최신 안정 버전으로 교체)
export KARPENTER_VERSION=1.8.0

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version ${KARPENTER_VERSION} \
  --namespace ${KARPENTER_NAMESPACE} \
  --create-namespace \
  --set settings.clusterName=${CLUSTER_NAME} \
  --set settings.interruptionQueue=${CLUSTER_NAME}-karpenter-interruption \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi
```

확인:

```bash
kubectl get pods -n kube-system | grep karpenter
```

---

## 7. EC2NodeClass + NodePool (Spot 우선, On-Demand fallback)

## 7.1 EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: ticket-nodeclass
spec:
  amiFamily: AL2023
  role: KarpenterNodeRole-ticket-burst-eks
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ticket-burst-eks
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ticket-burst-eks
```

## 7.2 NodePool

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ticket-burst
spec:
  template:
    metadata:
      labels:
        workload: ticketing
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: ticket-nodeclass
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["large", "xlarge", "2xlarge"]
  limits:
    cpu: "400"
    memory: 800Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 10m
```

적용:

```bash
kubectl apply -f ec2nodeclass.yaml
kubectl apply -f nodepool.yaml
kubectl get nodepool
```

> 위 설정은 Spot을 우선 시도하고, Spot 가용성 부족 시 On-Demand로 폴백될 수 있도록 구성한 패턴임.

---

## 8. 앱 배포 가드레일

예측 불가 피크에서 안정성을 높이기 위해 아래를 함께 적용함.

- Deployment resources requests/limits 명확화
- PodDisruptionBudget(PDB)
- topologySpreadConstraints
- readiness/startup probe

예시(PDB):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ticket-api-pdb
spec:
  minAvailable: 80%
  selector:
    matchLabels:
      app: ticket-api
```

---

## 9. EventBridge + Lambda (예약 사전 확장)

Karpenter와 별도로 baseline MNG를 사전 확장해 콜드 스타트를 줄임.

- 30분 전: `base-ng desired/min 상향`
- 종료 후: `base-ng desired/min 하향`

Lambda는 without-karpenter 문서의 `update_nodegroup_config` 코드를 재사용 가능.

예시 입력(Scale-out):

```json
{
  "clusterName": "ticket-burst-eks",
  "nodegroupName": "base-ng",
  "minSize": 8,
  "maxSize": 20,
  "desiredSize": 12
}
```

예시 입력(Scale-in):

```json
{
  "clusterName": "ticket-burst-eks",
  "nodegroupName": "base-ng",
  "minSize": 2,
  "maxSize": 10,
  "desiredSize": 2
}
```

---

## 10. 검증 절차

1. 예약 시간 전/후 Scheduler 실행 확인
2. Lambda 로그 확인
3. 노드 증가 확인

```bash
kubectl get nodes -L karpenter.sh/capacity-type
kubectl get pods -A | grep Pending
```

4. Spot 불가 상황 시 On-Demand 노드 생성 여부 확인
5. p95 latency, 5xx, Pending 지속시간 관측

---

## 11. 장애/비용 가드레일

- NodePool `limits`로 과증설 제한
- CloudWatch 예산/알람 설정
- 핵심 서비스는 PDB + On-Demand baseline 유지
- Spot 인터럽트 대비 재시도/큐 설계

---

## 12. 운영 권장 초기값

- baseline MNG: on-demand 2~4대 상시
- 이벤트 30분 전: baseline 8~12대로 사전 증설
- Karpenter NodePool: spot/on-demand 혼합 + 다양한 인스턴스 허용
- 이벤트 종료 후: baseline 원복 + Karpenter consolidation으로 정리

---

## 13. 언제 이 구성이 과한가

아래 조건이면 without-karpenter 문서가 더 단순하고 적합함.

- 피크 규모/시간이 항상 일정함
- 노드 타입 다양화/Spot 최적화 필요가 낮음
- 운영 복잡도 최소화가 최우선임
