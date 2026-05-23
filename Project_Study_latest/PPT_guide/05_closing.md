# Closing — 공동

- 슬라이드: 28~29 (총 2장)
- 발표 시간: 약 2분 + Q&A 5분
- 톤: 라이트 (회고) + 다크 (Thanks)
- 역할: 솔직한 회고 + Q&A 안내

## 핵심 메시지

"오늘 발표한 건 burst 시나리오의 기반(온프레+VPN)까지. 실제 burst 자동화는 다음 단계."

## 누가 발표?

- 회고 (28): 발표자 A 또는 팀 대표 1인
- Thanks/Q&A (29): 전원 또는 발표자 A

---

## 28. 회고 + 한계 [라이트 ⭐]

### 한 메시지
잘된 것 3 / 아쉬운 것 3 / 다음에 다르게 할 것 3 — 솔직함이 가장 강력

### 들어갈 내용 (3분할 카드, 라이트 톤)

**잘된 것 3가지**:
1. **온프레 HA 완성** — pfSense·K8s API·Edge L7·MetalLB 4계층 모두 검증
2. **이중 TLS 보안** — DMZ ↔ Internal 신뢰 경계 분리, 자체 CA 자동 회전
3. **GitOps end-to-end** — 코드 push → 4분 후 Pod rollout 검증

**아쉬운 것 3가지**:
1. **AWS Phase 3~5 미구현** — RDS replication, EKS Karpenter burst, multi-cluster ArgoCD
2. **sys1 단일 노드 SPoF** — 모든 시스템 컴포넌트(ArgoCD, Harbor, Jenkins, 모니터링)가 한 노드에
3. **Ceph HDD 한계** — RBD seq 35MB/s, SSD WAL/DB 분리 못함

**다음에 다르게 할 것 3가지**:
1. **SSD WAL/DB 분리** — 노드당 100GB SSD 6장 (30만원) → 성능 4~8배
2. **multi-cluster ArgoCD 등록** — 온프레 + EKS 동시 배포 가능
3. **CloudWatch + Lambda 자동 burst trigger** — 부하 임계 시 EKS scale-out 자동화

### 발표 멘트
"솔직하게 회고합니다. 잘된 것 3가지 — 온프레 HA를 4 계층 모두 검증했고, 이중 TLS로 신뢰 경계를 분리했고, GitOps로 코드 push 후 4분 만에 운영 배포되는 걸 end-to-end 검증했습니다. 아쉬운 것 3가지 — AWS Phase 3~5는 미구현이고, 시스템 컴포넌트가 sys1 한 노드에 몰려있어 SPoF고, Ceph는 HDD 한계로 성능이 부족합니다. 다음에 다르게 한다면 SSD WAL/DB 분리부터 시작해서 multi-cluster ArgoCD와 CloudWatch 자동 트리거까지 가고 싶습니다. 30만원 정도면 가장 큰 병목인 스토리지 성능을 4~8배 개선할 수 있습니다."

### 디자인 노트 (라이트 톤)
- 흰색 배경, 네이비 텍스트
- 3개 카드 가로 또는 세로 배열
- 각 카드 좌측 4px 액센트 바 (잘된 = 초록 / 아쉬운 = amber / 다음 = 블루)
- "솔직함의 흰 종이 톤" — 일부러 라이트로 분위기 전환

---

## 29. Thanks · Q&A [다크] · 표지와 통일

### 한 메시지
질문 받습니다 — 발표 마무리

### 들어갈 내용
- 큰 영문 헤더: `THANK YOU` 또는 `Q&A`
- 한 줄 마무리: "오늘 발표한 건 burst 시나리오의 기반까지. 실제 burst 자동화는 다음 단계입니다."
- 팀원 4인 + 담당 파트 (표지와 동일)
- (선택) GitHub repo URL · 연락처
- 표지와 시각적 통일 (좌측 큰 블루 바, 큰 영문 타이포)

### 발표 멘트
"여기까지 발표였습니다. 오늘 다룬 내용은 burst 시나리오의 기반 — 온프레 인프라, 데이터 layer, CI/CD, 보안, AWS VPN까지였습니다. 실제 burst 자동화 — RDS replication, multi-cluster ArgoCD, Karpenter 자동 트리거 — 는 다음 단계 과제입니다. 질문 받겠습니다."

---

## Q&A 대비 — 자주 받을 만한 질문

### Q1. "왜 GitHub Actions 안 쓰고 Jenkins?"
→ Part 3 슬라이드 17 그대로 답변. 자체 K8s 인프라 + private 네트워크 일관성.

### Q2. "Karpenter 실제 동작 시연 가능?"
→ "아직 미구현입니다. 다음 단계 과제입니다." 솔직 인정.

### Q3. "Ceph 35MB/s면 PXC가 운영 가능한 수준인가?"
→ "현재 ticket-app 데모 트래픽은 충분합니다. 실 운영 트래픽 (수천 TPS)에는 SSD WAL/DB 분리가 필수입니다."

### Q4. "VPN 끊기면 어떻게 되나?"
→ "현재는 미구축이라 영향 없습니다. Phase 3 이후 RDS replication 끊김 → stale 데이터, 복구 후 자동 catch-up. Phase 4 이후 EKS Pod이 온프레 PXC 접근 불가 → 트래픽 처리 불가."

### Q5. "sys1 죽으면 어떻게 되나?"
→ "ArgoCD, Harbor, Jenkins, 모니터링 모두 down → CI/CD 정지, 관측 불가. 즉시 영향: 신규 배포 중단. 진행 중인 트래픽은 영향 없음. 해결: sys2 노드 추가 + HA 가능한 컴포넌트(ArgoCD, Prometheus)는 replica."

### Q6. "비용 분석 더 자세히?"
→ "현재 AWS Phase 1-2 운영 시 월 $130 (NAT GW $64 + EC2 $15 + NLB $16 + VPN $36). Phase 4 burst 시 EKS 노드 t3.medium × 4 × 30분 × 30회/월 ≈ $25 추가. 평시엔 NAT GW만 살아있고 EKS는 0 노드라 추가 비용 없음."

### Q7. "Pretendard 폰트는 어떻게?"
→ "Google Fonts에 있고 무료입니다. https://github.com/orioncactus/pretendard 에서 다운로드해서 PC에 설치하면 됩니다."

### Q8. "데모 영상 있나?"
→ (있다면 보여주기, 없다면) "데모 영상은 별도 준비 못 했지만, kosa-tickets Build #4 캡처가 슬라이드 20에 있습니다."

---

## 발표 종료 후 체크리스트

- [ ] 모든 슬라이드가 다크 톤 일관성 (라이트 포인트 3장 제외)
- [ ] 페이지 번호 X / 29 모두 표시
- [ ] 우상단 곡선 장식 통일
- [ ] 한국어 폰트 정상 (Pretendard 또는 시스템 폴백)
- [ ] 영문 폰트 Poppins 정상
- [ ] 4 발표자 분담 시간 균등 (각 6~7분)
- [ ] 바톤 넘기기 멘트 자연스러운지 리허설
- [ ] Q&A 대비 자주 받을 질문 답변 준비
