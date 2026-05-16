# network arch

> Status: Proposed

## 결론

- AWS NLB 와 On-Prem 중간의 VPN 터널을 명확히 잡아야 함
- Calico = Pod 네트워크/CNI + NetworkPolicy 담당
- MetalLB = 온프레미스 K8s에서 LoadBalancer IP 할당 담당
- Ingress는 HAProxy Ingress 추천
  - 전단에 HAProxy
  - Ingress도 HAProxy
  - 구조 이해/운영 일관성 좋음

## 추천 구조

```text
User
 -> AWS NLB
 -> EC2 HAProxy x2 + Keepalived
 -> VPN Tunnel
 -> On-Prem HAProxy
 -> MetalLB IP
 -> HAProxy Ingress Controller
 -> K8s Service
 -> Pod
```

## VPN 추천

- 가장 확실한:
  - AWS Site-to-Site VPN
- 테스트/실습:
  - WireGuard
- pfSense 사용 중이면 pfSense 전용으로:
  - IPsec Site-to-Site VPN

## Calico 정리

- K8s Pod 간 통신을 위해 CNI 필요
- Calico는 그 CNI 중 하나
- 역할:
  - Pod IP 할당
  - Pod 간 라우팅
  - NetworkPolicy 적용
- 단 Calico가 유일한 선택지는 아님
  - Flannel
  - Cilium
  - Weave Net 등도 가능

## Ingress 추천

| 선택지              | 추천도 | 이유                    |
| ------------------- | -----: | ----------------------- |
| **HAProxy Ingress** |   높음 | 현재 구조와 궁합 좋음   |
| NGINX Ingress       |   높음 | 자료 많고 범용적        |
| Traefik             |   중간 | 자동화/동적 라우팅 강함 |
| Envoy/Gateway API   |   고급 | 러닝커브 큼             |

- 학습/포트폴리오 목적
  - HAProxy Ingress
- 작업 자료/트러블슈팅 편의
  - NGINX Ingress
- 현재 설계 기준
  - HAProxy Ingress가 가장 자연스러움

## 설정 포인트

```text
HAProxy
 -> Ingress Controller
 -> Service
 -> Pod
```

- Calico는 그 아래에서 Pod 네트워크를 구성하는 기반 계층
