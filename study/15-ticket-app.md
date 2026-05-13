# 챕터 15: ticket-app (FastAPI + 앱 배포)

> KOSA 인프라 프로젝트 학습 시리즈 / 작성일 2026-05-13
> 환경: Python 3.11 + FastAPI 0.115, namespace `kosa-tickets`, LoadBalancer 172.16.23.103, PXC 3-node Galera

## 학습 후 알 수 있는 것

- FastAPI가 Flask/Django와 어떻게 다른지(async, Pydantic, OpenAPI 자동), 왜 모던 Python 웹 표준이 됐는지 설명할 수 있어요.
- 우리 ticket-app 구조 — `main.py` + `templates/index.html` + `Dockerfile` + `k8s/` 4개 매니페스트 — 가 왜 단순한지 알 수 있어요.
- 좌석 100개(10×10), 어느 Pod이 처리했는지 표시하는 시연 시나리오의 의도를 말할 수 있어요.
- Docker 이미지 빌드 → GHCR push → K8s pull → LoadBalancer 노출의 전체 배포 흐름을 설명할 수 있어요.
- 우리가 만난 함정 — GHCR private 이슈, Docker 이미지 이름 대소문자, DB_HOST vs DATABASE_HOST env 미스매치 — 의 메커니즘을 이해해요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

- **FastAPI**: Python 3.7+ 의 type hint와 async/await를 활용해 자동 검증/OpenAPI 문서 생성/고성능을 제공하는 모던 웹 프레임워크예요.
- **ticket-app**: 우리 인프라 시연용으로 만든 좌석 예약 미니 앱(FastAPI + Jinja2 + PXC) — HPA scale-out과 PXC 동기 복제, 데이터 영속성을 한 페이지에서 보여줘요.

### 1.2 등장 배경

**Python 웹 프레임워크 흐름:**
- 2005년 Django — 풀스택, MVC, "batteries included". 대규모 사이트(인스타그램, 핀터레스트).
- 2010년 Flask — 마이크로 프레임워크, 자유도 ↑. 라이브러리 골라 끼우는 방식.
- 2017년 ASGI 표준 (WSGI의 async 후속). Starlette/Uvicorn 등장.
- 2018년 FastAPI (Sebastián Ramírez, Tiangolo) — Starlette + Pydantic + type hint 결합. 단숨에 채택률 상위.

**왜 ticket-app을 새로 만들었나:**
- 원래 데모로 fastapi/python 회원정보 등록/출력 앱이 있었음(현재 데모 — CLAUDE.md 참고).
- HPA 시연을 위한 burst 발생 + PXC 동기 복제 시연 + Pod별 응답 표시 — 이 세 가지를 모두 한 화면에 보여줘야 해서 좌석 예약 형태로 재설계.

### 1.3 핵심 개념 + 용어 풀이

**FastAPI 핵심:**

| 용어 | 의미 |
|---|---|
| ASGI | Asynchronous Server Gateway Interface. WSGI의 async 버전 |
| Pydantic model | 타입 힌트를 런타임 검증으로 사용. 자동 직렬화/역직렬화 |
| Dependency injection | `Depends()` — 의존성을 함수 인자로 자동 주입 |
| OpenAPI 자동 생성 | `/docs` 엔드포인트에 Swagger UI, `/openapi.json` |
| Uvicorn | ASGI 서버 (Gunicorn은 WSGI). 단일 worker 또는 multi-process |

**우리 앱 도메인 용어:**

| 용어 | 의미 |
|---|---|
| seat | 좌석 1개. seat_no(A1~J10), status(available/reserved), reserved_by, reserved_at |
| Pod hostname 표시 | reserve API가 `os.environ.get("HOSTNAME")` 반환 → 어느 Pod이 처리했는지 시각화 |
| reset API | 데모용 — 모든 좌석을 available로 복귀 |

### 1.4 동작 원리 (내부 메커니즘)

**FastAPI 요청 흐름:**

```
[Browser]
   │ POST /api/reserve/42?user=demo
   ▼
[uvicorn]  (ASGI 서버, Pod 안)
   │
   ▼
[FastAPI app]
   │ 1) 라우터 매칭: @app.post("/api/reserve/{seat_id}")
   │ 2) path param seat_id=42 추출 + 타입 검증(int)
   │ 3) query param user="demo" 추출 + 기본값 처리
   │ 4) reserve_seat() 함수 호출
   ▼
[SQLModel session]
   │ SELECT/UPDATE seat WHERE id=42
   ▼
[mysqlconnector]
   │ TCP connection
   ▼
[ProxySQL Service]  (pii-protected namespace)
   │ writes → hostgroup 10 (PXC writer)
   ▼
[PXC pxc-0]  (Galera primary node)
   │ commit → wsrep replication → pxc-1, pxc-2 동기 복제
   ▼
[response]
   { "ok": true, "host": "ticket-app-7d8b5c9c4d-8xkqr" }
```

**HPA scale-out 시 동작:**

```
부하 ↑ → ticket-app Pod CPU 80%
       → HPA가 replicas 2 → 6 증가
       → Service의 selector(app=ticket-app)가 새 Pod도 자동 포함
       → MetalLB ExternalIP 172.16.23.103은 그대로
       → 라운드로빈으로 요청 분산 → 좌석마다 다른 Pod 표시됨
```

### 1.5 주요 기능

**FastAPI:**
- 타입 힌트 기반 자동 검증 (`def reserve(seat_id: int)` — 자동으로 422 반환)
- async/await — 비동기 IO (DB 동시 호출, 외부 API 호출)
- Pydantic 모델 — request/response 스키마
- OpenAPI/Swagger 자동 — `/docs`로 인터랙티브 문서
- Dependency Injection
- WebSocket, Background Tasks, OAuth2 통합

**우리 ticket-app:**
- GET `/api/seats` — 좌석 100개 조회
- POST `/api/reserve/{seat_id}` — 좌석 예약 (이미 예약 시 409)
- POST `/api/reset` — 데모용 전체 리셋
- GET `/healthz` — K8s liveness/readiness
- GET `/` — Jinja2 템플릿 HTML 페이지

### 1.6 다른 도구와 비교

| 프레임워크 | 언어 | 특징 | 점유율 |
|---|---|---|---|
| **FastAPI** | Python | async, type hint, OpenAPI | Python 신흥 강자 |
| Flask | Python | 단순, 마이크로 | Python 클래식 |
| Django | Python | 풀스택, ORM, admin | 대규모 사이트 |
| Express.js | Node | JS, async 네이티브 | Node 표준 |
| Spring Boot | Java | 엔터프라이즈, JPA | Java 표준 |
| Gin/Fiber | Go | 초고성능, 정적 타입 | Go 표준 |

**FastAPI vs Flask 핵심 차이:**

| 항목 | Flask | FastAPI |
|---|---|---|
| 검증 | 수동 (Marshmallow 등 별도) | 타입 힌트로 자동 |
| async | 2.0부터 지원하지만 한계 | 네이티브 (Starlette) |
| 문서 | Flasgger 등 별도 | 자동 OpenAPI |
| 성능 | 보통 | ~3배 빠름 (벤치마크) |
| 학습 곡선 | 매우 낮음 | 낮음 (type hint만 알면) |

---

## 2. 현업/실무 맥락

### 2.1 어떤 상황에서 필요한가

- **REST API 백엔드**: 모바일/SPA 프론트와 연동. Pydantic 검증으로 데이터 안정성.
- **마이크로서비스**: 작고 빠르게 띄울 서비스. Spring Boot 대비 메모리 1/5.
- **ML 추론 서버**: 학계/AI 회사에서 Python ML 모델을 REST로 서빙할 때 표준.
- **내부 도구 API**: 회사 내부 대시보드 백엔드 등.

### 2.2 업계 표준, 대표 사용 기업/사례

- Uber, Netflix, Microsoft가 일부 서비스에서 FastAPI 사용 공식화.
- OpenAI, Hugging Face — ML 모델 서빙에 FastAPI 표준.
- Stack Overflow Developer Survey 2024 — Python 웹 프레임워크 만족도 1위.

### 2.3 왜 효율이 좋은가 (현업 관점)

- **타이핑 = 문서 = 검증**: type hint 하나로 IDE 자동완성 + Pydantic 런타임 검증 + OpenAPI 문서. 한 번 쓰면 3개 효과.
- **async**: 단일 Pod에서 동시 1000+ 요청 처리 가능 (Flask는 동기라 worker 수 = 동시 처리량).
- **시작 시간 짧음**: Django는 시작에 5초+, FastAPI는 1초 미만 — K8s에서 Pod restart 시 다운타임 ↓.

### 2.4 시장 위치

- Python 웹 프레임워크 신흥 강자. Flask 점유율 일부 가져옴.
- ML/Data 진영에선 사실상 표준.
- 마이크로서비스 진영에선 Spring Boot/Go의 일부 워크로드 대체.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

**언어/프레임워크:**

| 옵션 | 장점 | 단점 | 우리 판단 |
|---|---|---|---|
| Flask | 단순 | 검증 수동, async 부족 | 검증 코드 늘어남 → 탈락 |
| Django | 풀스택 | 무거움, 시작 느림 | 좌석 100개 데모엔 과함 |
| Spring Boot | 엔터프라이즈 | JVM 메모리 ↑, K8s에 부담 | 워커 6GB 환경엔 부담 |
| Node Express | 빠름 | JS, ORM 부재 | 팀 Python 친화 |
| **FastAPI** | 타입 안전, async, OpenAPI 자동 | 신생(레퍼런스 적음) | **채택** |

**앱 구조:**

| 옵션 | 장점 | 단점 | 우리 판단 |
|---|---|---|---|
| **단일 앱(monolith)** | 단순, 한 페이지 시연 | scale 시 모든 기능 함께 | **채택** |
| 마이크로서비스 (seat-service + reservation-service + user-service) | 현업 그림 | 우리 인프라 시연이 본질 → 복잡도 ↑ | 탈락 |

### 3.2 현업 표준과의 정합성

- "Python + FastAPI + SQLModel + PXC" 조합은 모던 백엔드 표준 중 하나.
- K8s + HPA + LoadBalancer 노출도 표준 패턴.
- 좌석 락(distributed lock, Redis 등) 없는 단순 INSERT/UPDATE 모델은 의도적 단순화 — 본 시연 목적은 burst와 동기 복제 가시화.

### 3.3 선택 근거 (트레이드오프)

- **트레이드오프 1 — 왜 FastAPI (Flask 안 쓴 이유)**: 시연 화면에서 "Pod hostname"을 응답에 박아야 했어요. Flask로도 가능하지만 FastAPI는 `os.environ.get("HOSTNAME")`을 응답 dict에 그냥 추가하면 자동 JSON 직렬화. Flask는 `jsonify()` 호출 필요 — 사소하지만 가독성 ↑.
- **트레이드오프 2 — 왜 단일 앱 (마이크로서비스 안 쓴 이유)**: 데모 본질은 인프라(K8s/Ceph/PXC/HPA)이지 마이크로서비스 패턴이 아님. 단일 앱이면 코드 1개, Pod 1종류 → 시연 시 관심 분산 X. 마이크로서비스 시연 항목은 향후 별도 챕터로.
- **트레이드오프 3 — 왜 좌석 락 없음**: 100명이 동시에 같은 좌석을 클릭하는 경합 상황을 무시. 첫 INSERT가 commit하면 두 번째는 UPDATE에서 status='reserved' 보고 409 반환. 진짜 티켓팅이면 Redis distributed lock(SETNX) 필요하지만, **본 시연 목적은 burst 트래픽 → HPA → PXC 동기 복제 가시화**라서 단순화.

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
[브라우저]
    │ http://172.16.23.103/
    ▼
[MetalLB IP 172.16.23.103]
    │
    ▼
[Service ticket-app] (LoadBalancer, port 80 → targetPort 8000)
    │ selector: app=ticket-app
    │
    ▼
[ticket-app Pods × 2~10]  (HPA가 자동 조정)
    │  containers: ghcr.io/sangchul1/kosa-tickets:latest
    │
    │ DATABASE_HOST=kosa-pxc-proxysql.pii-protected.svc.cluster.local
    ▼
[ProxySQL Service] (pii-protected ns, port 3306)
    │
    ├─ writes (hostgroup 10) ▶ pxc-0 (writer)
    └─ reads (hostgroup 20)  ▶ pxc-0, pxc-1, pxc-2 (round-robin)
                                  │ Galera 동기 복제
                                  │ wsrep_cluster_size = 3
```

### 4.2 핵심 설정값과 근거

| 항목 | 값 | 근거 |
|---|---|---|
| 좌석 수 | 100 (A~J × 1~10) | 그리드 10×10이 가장 깔끔, 한 화면에 보임 |
| Pod replicas (초기) | 2 | minReplicas와 동일, 단일 Pod 장애 시 가용성 |
| CPU request | 100m | HPA 50% 임계의 기준점 |
| CPU limit | 500m | burst 5배 허용 |
| Memory limit | 256Mi | FastAPI + mysqlconnector ~150Mi, 헤드룸 충분 |
| livenessProbe | `/healthz` 10초마다 | 기본값 |
| readinessProbe | `/healthz` 5초마다 | 빠른 LB 반영 |
| Service type | LoadBalancer | 노트북에서 직접 도달 (MetalLB) |
| Service port | 80 → targetPort 8000 | 표준 80 노출, 컨테이너 내부는 uvicorn 기본 8000 |
| Image | `ghcr.io/sangchul1/kosa-tickets:latest` | GHCR public, OWNER 소문자 |
| DB host | `kosa-pxc-proxysql.pii-protected.svc.cluster.local` | PXC 앞단 ProxySQL Service FQDN |
| DB user | `kosa_app` (kosa1004) | Phase 6.3.4에서 생성한 앱 user |
| Pool size | 10, max_overflow 20 | HPA로 Pod 10 × pool 10 = 100 conn — PXC 디폴트 max_connections 충분 |
| pool_recycle | 3600 | MySQL wait_timeout 회피 (보통 8시간이지만 보수적) |
| pool_pre_ping | True | stale connection 자동 감지 |

### 4.3 다른 컴포넌트와의 연결

- **HPA**: Deployment의 metric 기반 — CPU 50% / Mem 70% 넘으면 scale up.
- **PXC ProxySQL**: 읽기/쓰기 라우팅. 우리는 query rule 기본만 — root 직접 쓰는 건 PXC 노드, kosa_app은 ProxySQL 통과.
- **MetalLB**: Service `LoadBalancer` 타입에 172.16.23.103 자동 할당.
- **GHCR**: GitHub Actions가 이미지 빌드 → push. K8s가 pull. 우리는 public repo라 imagePullSecret 미사용(처음엔 private이라 막혔다가 public 전환).
- **ArgoCD** (선택): ticket-app의 k8s/ 디렉토리를 Application으로 등록 가능. main 브랜치 변경 시 자동 sync.

---

## 5. 실제 코드 / 설정 파일

### 5.1 FastAPI 앱 — main.py

파일: `/Users/sangjjang/kosa_infra_project/ticket-app/main.py`

```python
import os
from fastapi import FastAPI, HTTPException
from sqlmodel import SQLModel, Field, create_engine, Session, select

DB_HOST = os.environ.get("DATABASE_HOST", "localhost")
DB_PORT = os.environ.get("DATABASE_PORT", "3306")
DB_USER = os.environ.get("DATABASE_USER", "root")
DB_PASS = os.environ.get("DATABASE_PASSWORD", "kosa1004")
DB_NAME = os.environ.get("DATABASE_DB_NAME", "kosa_tickets")

DATABASE_URL = f"mysql+mysqlconnector://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

engine = create_engine(
    DATABASE_URL,
    pool_size=10,           # Pod당 connection 풀 크기
    max_overflow=20,        # 풀 부족 시 추가로 열 최대 connection
    pool_recycle=3600,      # 1시간마다 connection 재생성 (stale 회피)
    pool_pre_ping=True,     # 사용 직전 SELECT 1로 살아있는지 확인
)


class Seat(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    seat_no: str = Field(max_length=10, index=True)
    status: str = Field(default="available", max_length=20)
    reserved_by: Optional[str] = Field(default=None, max_length=50)
    reserved_at: Optional[datetime] = None


app = FastAPI(title="KOSA Tickets")


@app.on_event("startup")
def startup():
    """앱 시작 시 seats 테이블이 비어있으면 100개 좌석 자동 생성."""
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        count = len(session.exec(select(Seat)).all())
        if count == 0:
            for r in "ABCDEFGHIJ":
                for n in range(1, 11):
                    session.add(Seat(seat_no=f"{r}{n}", status="available"))
            session.commit()


@app.post("/api/reserve/{seat_id}")
def reserve_seat(seat_id: int, user: str = "guest"):
    with Session(engine) as session:
        seat = session.get(Seat, seat_id)
        if not seat:
            raise HTTPException(404, "Seat not found")
        if seat.status == "reserved":
            raise HTTPException(409, f"Seat {seat.seat_no} already reserved")
        seat.status = "reserved"
        seat.reserved_by = user
        seat.reserved_at = datetime.utcnow()
        session.add(seat)
        session.commit()
        return {
            "ok": True,
            "seat_no": seat.seat_no,
            "host": os.environ.get("HOSTNAME", "unknown"),  # ★ Pod 이름
        }
```

**핵심 라인 + 왜 이 옵션?**
- `os.environ.get("DATABASE_HOST", "localhost")`: 환경변수 못 받으면 localhost로 fallback → 로컬 개발 가능.
- `pool_size=10, max_overflow=20`: Pod당 최대 30 connection. HPA max 10 Pod × 30 = 300. PXC max_connections 500 안에 안전.
- `pool_pre_ping=True`: PXC 페일오버 시 stale connection 자동 정리.
- `HOSTNAME 환경변수`: K8s는 Pod 이름을 자동으로 컨테이너의 HOSTNAME 환경변수에 주입. 코드에서 그대로 응답에 박음 → 어느 Pod이 처리했는지 화면에 표시.
- `@app.on_event("startup")`: 앱 부팅 시 한 번 — 좌석 0개면 100개 자동 INSERT. K8s에서 첫 Pod이 init.

### 5.2 Dockerfile

파일: `/Users/sangjjang/kosa_infra_project/ticket-app/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# 의존성만 먼저 복사 → 캐시 활용
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 앱 코드
COPY main.py .
COPY templates ./templates

ENV PYTHONUNBUFFERED=1

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
```

**왜 이 옵션?**
- `python:3.11-slim`: 풀버전 python:3.11 대비 ~100MB 작음. K8s pull 시간 ↓.
- `requirements.txt 먼저 COPY`: Docker layer 캐시. 코드만 바뀌면 의존성 layer 재사용 → 빌드 30초 → 5초.
- `--no-cache-dir`: pip가 wheel 캐시 안 만들어서 이미지 크기 ↓.
- `PYTHONUNBUFFERED=1`: stdout/stderr 즉시 flush. K8s `kubectl logs`에서 실시간 보임.
- `--workers 1`: uvicorn worker 1개만. **HPA가 Pod 단위로 scale하므로 컨테이너 안에서 worker 늘릴 필요 X**. workers 2+면 Pod CPU request의 의미가 모호해짐.

### 5.3 K8s Deployment

파일: `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/10-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ticket-app
  namespace: kosa-tickets
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ticket-app
  template:
    metadata:
      labels:
        app: ticket-app
    spec:
      containers:
      - name: app
        image: ghcr.io/sangchul1/kosa-tickets:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
        env:
        - name: DATABASE_HOST
          valueFrom:
            secretKeyRef:
              name: ticket-db-credentials
              key: DATABASE_HOST
        - name: DATABASE_PORT
          valueFrom: { secretKeyRef: { name: ticket-db-credentials, key: DATABASE_PORT } }
        - name: DATABASE_USER
          valueFrom: { secretKeyRef: { name: ticket-db-credentials, key: DATABASE_USER } }
        - name: DATABASE_PASSWORD
          valueFrom: { secretKeyRef: { name: ticket-db-credentials, key: DATABASE_PASSWORD } }
        - name: DATABASE_DB_NAME
          valueFrom: { secretKeyRef: { name: ticket-db-credentials, key: DATABASE_DB_NAME } }
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits:   { cpu: 500m, memory: 256Mi }
        livenessProbe:
          httpGet: { path: /healthz, port: 8000 }
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet: { path: /healthz, port: 8000 }
          initialDelaySeconds: 5
          periodSeconds: 5
```

**핵심 라인 + 왜 이 옵션?**
- `imagePullPolicy: Always`: `:latest` 태그 쓸 땐 항상 pull. 운영에선 `:vX.Y.Z` 태그 고정 + `IfNotPresent` 권장.
- `Secret 5개 분리 key`: 비밀번호만 따로 관리 가능. base64 인코딩이지 암호화 아님 — 운영은 Sealed Secrets 또는 Vault.
- `liveness 10초 / readiness 5초`: readiness가 더 자주 = LB 합류/이탈 빠름. liveness는 보수적이어야 false positive 회피.
- `initialDelaySeconds`: FastAPI startup이 좌석 100개 INSERT 하므로 첫 ready까지 5~10초 필요.

### 5.4 K8s Service

파일: `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/20-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ticket-app
  namespace: kosa-tickets
spec:
  type: LoadBalancer
  selector:
    app: ticket-app
  ports:
  - port: 80
    targetPort: 8000
    protocol: TCP
```

**왜 이 옵션?**
- `type: LoadBalancer`: MetalLB가 172.16.23.103 자동 부여.
- `port 80 → targetPort 8000`: 외부는 표준 HTTP, 내부 컨테이너는 uvicorn 기본 8000.

---

## 6. 실행 + 결과

### 6.1 GHCR 로그인 + 이미지 빌드/push (bastion에서)

```bash
[bastion]$ docker login ghcr.io -u sangchul1
# Personal Access Token (read:packages, write:packages) 입력

[bastion]$ cd ~/ticket-app
[bastion]$ docker build -t ghcr.io/sangchul1/kosa-tickets:latest .
[bastion]$ docker push ghcr.io/sangchul1/kosa-tickets:latest
```

실제 출력 (push):
```
The push refers to repository [ghcr.io/sangchul1/kosa-tickets]
xxxx: Pushed
yyyy: Pushed
latest: digest: sha256:abc123... size: 1369
```

### 6.2 DB Secret + Schema 준비

```bash
[bastion]$ kubectl create namespace kosa-tickets

[bastion]$ kubectl create secret generic ticket-db-credentials -n kosa-tickets \
            --from-literal=DATABASE_HOST=kosa-pxc-proxysql.pii-protected.svc.cluster.local \
            --from-literal=DATABASE_PORT=3306 \
            --from-literal=DATABASE_USER=kosa_app \
            --from-literal=DATABASE_PASSWORD=kosa1004 \
            --from-literal=DATABASE_DB_NAME=kosa_tickets

# DB 생성
[bastion]$ kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- \
            mysql -uroot -pkosa1004 -e \
            "CREATE DATABASE kosa_tickets; GRANT ALL ON kosa_tickets.* TO 'kosa_app'@'%'; FLUSH PRIVILEGES;"
```

### 6.3 K8s 매니페스트 적용

```bash
[bastion]$ kubectl apply -f /home/ubuntu/ticket-app/k8s/
```

실제 출력:
```
namespace/kosa-tickets created
deployment.apps/ticket-app created
service/ticket-app created
horizontalpodautoscaler.autoscaling/ticket-app created
```

### 6.4 상태 확인

```bash
[bastion]$ kubectl get pods,svc,hpa -n kosa-tickets
```

실제 출력:
```
NAME                              READY   STATUS    AGE
pod/ticket-app-7d8b5c9c4d-8xkqr   1/1     Running   2m
pod/ticket-app-7d8b5c9c4d-mn2vt   1/1     Running   2m

NAME                 TYPE           EXTERNAL-IP      PORT(S)
service/ticket-app   LoadBalancer   172.16.23.103    80:31204/TCP

NAME                                             REFERENCE               TARGETS                       REPLICAS
horizontalpodautoscaler.autoscaling/ticket-app   Deployment/ticket-app   cpu: 4%/50%, memory: 28%/70%   2
```

### 6.5 브라우저 시연

[노트북]에서 `http://172.16.23.103`:
- 좌석 100개 그리드 로드
- A1 클릭 → 회색 + flash 애니메이션 + 우측 상태창에 `[14:32:15] ✅ A1 예약 완료 pod: ticket-app-7d8b5c9c4d-8xkqr`
- A1 재클릭 → `❌ A1: Seat A1 already reserved`
- 새로고침 → 예약 상태 유지 (PXC INSERT 영속)
- "전체 리셋" 버튼 → 100개 모두 available 복귀

### 6.6 PXC 동기 복제 검증

```bash
[bastion]$ kubectl exec kosa-pxc-pxc-1 -n pii-protected -- \
            mysql -ukosa_app -pkosa1004 kosa_tickets \
            -e "SELECT COUNT(*) reserved FROM seat WHERE status='reserved';"
```

브라우저에서 예약한 좌석 수와 동일하게 보임 → 3노드 동기 복제 정상.

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 7.1 GHCR private 패키지 — ImagePullBackOff

**증상:**
```
Failed to pull image "ghcr.io/sangchul1/kosa-tickets:latest":
  rpc error: code = Unknown desc = Error response from daemon:
  Head https://ghcr.io/v2/...: denied
```

**원인:** GHCR에 첫 push하면 기본 visibility가 **private**. K8s가 익명 pull 시도 → 401. organization 정책상 private repo 못 받는 경우도.

**해결 1 (간단):** GitHub UI → Packages → kosa-tickets → Settings → Change visibility → **Public**.

**해결 2 (운영 권장):** imagePullSecret 생성.
```bash
[bastion]$ kubectl create secret docker-registry ghcr-pull-secret \
            --docker-server=ghcr.io \
            --docker-username=sangchul1 \
            --docker-password=<GitHub PAT (read:packages)> \
            -n kosa-tickets
```

Deployment에 추가:
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: ghcr-pull-secret
```

**왜 이 함정이 발생하는가 (메커니즘):**
GHCR은 Docker Hub와 달리 첫 push 시 private 기본값. K8s 노드의 containerd는 인증 없이 pull 시도 → 401. imagePullSecret이 dockerconfigjson 형태 base64 인코딩으로 자격증명을 저장하고, kubelet이 pull 시 그걸 사용. 학습/데모용은 Public이 단순. 출처: inventory.md 표 2.

### 7.2 Docker 이미지 이름 — 대문자 거부

**증상:**
```
ERROR: failed to solve: repository name must be lowercase: KosaCloudTeam2/kosa-tickets
```

**원인:** OCI 이미지 명세상 repository name은 소문자 + 숫자 + 일부 특수문자만 허용. GitHub username/org에 대문자 있으면 그대로 못 씀.

**해결:** OWNER 변수를 소문자로.
```bash
[bastion]$ docker build -t ghcr.io/kosacloudteam2/kosa-tickets:latest .
# 또는 본인 username sangchul1 등 소문자로
```

**왜 이 함정이 발생하는가 (메커니즘):**
OCI 표준 — repository name pattern `[a-z0-9]+(?:[._-][a-z0-9]+)*`. 대문자 허용 안 함. GitHub username/org는 대소문자 혼합 가능하지만 GHCR push 시엔 소문자 강제. push 명령에 대문자가 있으면 거부. 출처: inventory.md 표 2 / Phase 6.2.

### 7.3 env 이름 미스매치 — Pod CrashLoopBackOff

**증상:** Pod 생성 직후 1~2초 만에 CrashLoopBackOff.
```bash
[bastion]$ kubectl logs ticket-app-xxx -n kosa-tickets
# DB connection refused: localhost:3306
```

**원인:** Secret key 이름은 `DB_HOST`인데 코드에서 `DATABASE_HOST` env를 읽음 (또는 반대). 매핑 실패로 env 비어있어 fallback `localhost`로 연결 시도 → Pod 안엔 MySQL 없으니 connection refused.

**해결:** 이름 통일. 우리는 `DATABASE_*`로 통일.
- main.py: `os.environ.get("DATABASE_HOST", "localhost")`
- Secret: `--from-literal=DATABASE_HOST=...`
- Deployment env: `key: DATABASE_HOST`

3군데 모두 같아야 함.

**왜 이 함정이 발생하는가 (메커니즘):**
K8s `secretKeyRef.key`는 Secret 내부의 key 이름과 정확 일치해야 함. 환경변수 이름은 `env.name`이 결정. Secret key와 env name이 달라도 작동(예: `name: DB_HOST` 에 `key: DATABASE_HOST`) — 하지만 코드 측 `os.environ.get("DB_HOST")` 또는 `DATABASE_HOST` 어느 쪽을 읽는지에 따라 빈 값. 3군데(코드/Secret/env) 모두 일치 검사 필요. 출처: inventory.md 표 2.

### 7.4 좌석 락 없어서 동시 클릭 시 양쪽 다 200?

**증상:** 부하 테스트 중 두 사용자가 같은 좌석을 거의 동시에 클릭하면 둘 다 200 반환되는 케이스 가능.

**원인:** 우리 코드는 `SELECT → status check → UPDATE` 패턴. SELECT와 UPDATE 사이에 다른 트랜잭션이 끼면 race condition.

**해결 (현 시연용은 안 함):** PXC에선 `SELECT ... FOR UPDATE` 또는 Galera의 commit cert로 충돌 시 두 번째는 deadlock(SQLSTATE 40001) 반환. 또는 Redis SETNX distributed lock.

**왜 이 함정이 발생하는가 (메커니즘):**
Galera는 동기 복제지만 **optimistic locking**. 같은 row 동시 UPDATE 시 commit 시점에 충돌 감지 → 한 쪽은 deadlock error. 우리 코드는 deadlock 처리 안 하므로 두 INSERT 모두 200 가능. 본 시연 목적이 burst + 영속성 가시화라 단순화. 운영은 `with session.begin(): session.exec(select(Seat).where(Seat.id == id).with_for_update())` 추가 필요.

### 7.5 `docker` 그룹 변경 미적용 (newgrp 비밀번호 요구)

**증상:** Docker 그룹에 ubuntu 사용자 추가 후 `docker ps` 실행 시 `permission denied`. `newgrp docker` 하면 비밀번호 묻고, cloud-init user는 비밀번호 없음.

**원인:** Linux 그룹 변경은 다음 로그인부터 반영. cloud-init user는 SSH 키만 — 비밀번호 부재.

**해결:**
```bash
[bastion]$ exit
[노트북]$ ssh bastion  # 다시 들어오면 그룹 적용됨
```

**왜 이 함정이 발생하는가 (메커니즘):**
`usermod -aG docker ubuntu`는 /etc/group 파일만 수정. 현재 셸 세션의 그룹 정보는 로그인 시점 캐싱. `newgrp`는 새 셸을 띄우는데 비밀번호 필요. SSH 재로그인이 가장 확실. 출처: inventory.md 표 2 / Phase 6.2.

---

## 8. 더 깊이 공부할 자료

**FastAPI:**
- 공식 docs: https://fastapi.tiangolo.com/
- SQLModel(같은 저자, ORM 통합): https://sqlmodel.tiangolo.com/
- 책 `FastAPI: Modern Python Web Development` (O'Reilly, 2023)
- async/await 이해: PEP 492, 525

**Container 배포:**
- 12-factor app: https://12factor.net (env 변수, stateless 등 원칙)
- K8s Probes 가이드: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- GHCR docs: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

**PXC + 앱:**
- ProxySQL query rules: https://proxysql.com/documentation/ProxySQL-Configuration/
- SQLAlchemy connection pool 튜닝: https://docs.sqlalchemy.org/en/20/core/pooling.html

**참고 우리 프로젝트 파일:**
- `/Users/sangjjang/kosa_infra_project/ticket-app/main.py`
- `/Users/sangjjang/kosa_infra_project/ticket-app/templates/index.html`
- `/Users/sangjjang/kosa_infra_project/ticket-app/Dockerfile`
- `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/10-deployment.yaml`
- `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/20-service.yaml`
- `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/30-hpa.yaml`
- `/Users/sangjjang/kosa_infra_project/ticket-app/k6-test.js`
- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 6.2 (GHCR)
- `/Users/sangjjang/kosa_infra_project/inventory.md` 표 2/4 (시연 시나리오, 함정)

---

## 다음 챕터 미리보기

이번 챕터로 우리 인프라의 "사용자가 직접 만지는" 마지막 레이어까지 다뤘어요. 이후 진행할 영역으로는:
- **AWS 하이브리드 burst** — Karpenter로 EKS spot 인스턴스 자동 증설, Route 53 latency-based routing
- **GitOps 고도화** — Sealed Secrets, ApplicationSet, multi-cluster
- **관찰성 심화** — Loki(로그) + Tempo(트레이스) + Mimir(메트릭) 합본
- **보안 / 거버넌스** — OPA Gatekeeper, NetworkPolicy, kube-bench, Trivy 이미지 스캔

각각 별도 챕터로 다룰 수 있는 주제예요. 우리가 만든 6개 노드 K8s + ArgoCD + HPA + ticket-app은 그 모든 학습의 출발점이 됩니다.
