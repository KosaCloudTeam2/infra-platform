# API 명세 — kosa-day FastAPI

> Base URL: `https://api.kosa-day.example.com`
> 인증: JWT Bearer Token (회원 API)
> 작성: 2026-05-12

---

## 목차

1. [개요](#1-개요)
2. [공통 규칙](#2-공통-규칙)
3. [인증 API](#3-인증-api)
4. [회원 API (PII)](#4-회원-api-pii)
5. [상품 API](#5-상품-api)
6. [주문 API](#6-주문-api)
7. [리뷰 API](#7-리뷰-api)
8. [관리자 API](#8-관리자-api)
9. [헬스체크 & 메트릭](#9-헬스체크--메트릭)
10. [에러 코드 일람](#10-에러-코드-일람)

---

## 1. 개요

### 서비스 분리

| Deployment | Namespace | 접근 가능 API | DB 접근 |
|---|---|---|---|
| `members-svc` | `pii-protected` | `/auth/*`, `/members/*` | Onprem Percona 직접 |
| `app-svc` | `app-public` | `/products/*`, `/orders/*`, `/reviews/*` | ProxySQL 경유 (Read 분기) |
| `admin-svc` | `app-public` | `/admin/*` | ProxySQL 경유 (Read는 AWS Replica) |

> **NetworkPolicy**: `members-svc` Pod은 AWS로 outgoing 트래픽 차단.

### Tech Stack
- FastAPI 0.110+
- Python 3.11
- SQLAlchemy 2.0 + asyncmy/aiomysql
- Pydantic v2
- python-jose (JWT)
- boto3 (Ceph RGW)
- redis-py (세션)

---

## 2. 공통 규칙

### Request Headers
```
Content-Type: application/json
Authorization: Bearer <jwt_access_token>  (회원 API)
X-Request-Id: <uuid>                       (추적용, 선택)
```

### Response 구조

#### 성공
```json
{
  "data": { ... },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2026-05-12T10:00:00Z"
  }
}
```

#### 에러
```json
{
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "이메일 또는 비밀번호가 잘못되었습니다",
    "details": null
  },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2026-05-12T10:00:00Z"
  }
}
```

### Pagination
```
GET /products?page=1&size=20&sort=price&order=desc
```

응답:
```json
{
  "data": [ ... ],
  "pagination": {
    "page": 1,
    "size": 20,
    "total": 150,
    "total_pages": 8
  }
}
```

### Rate Limiting
- 비로그인: 100 req/min per IP
- 로그인: 500 req/min per user
- 관리자: 무제한

Headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1715500800
```

---

## 3. 인증 API

### 3.1 회원가입

```
POST /auth/signup
```

**Request**:
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "name": "홍길동",
  "phone": "010-1234-5678",
  "address": "서울시 강남구 ..."
}
```

**Response 201**:
```json
{
  "data": {
    "id": 1001,
    "email": "user@example.com",
    "name": "홍길동",
    "created_at": "2026-05-12T10:00:00Z"
  }
}
```

**검증**:
- email: 이메일 형식 + 중복 체크
- password: 8자 이상, 영문/숫자/특수문자 조합
- phone: 한국 번호 형식 (선택)

**DB 작업**: `INSERT INTO members ...` (Percona Writer)

---

### 3.2 로그인

```
POST /auth/login
```

**Request**:
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}
```

**Response 200**:
```json
{
  "data": {
    "access_token": "eyJhbGc...",
    "refresh_token": "eyJhbGc...",
    "token_type": "Bearer",
    "expires_in": 900
  }
}
```

**Token 페이로드**:
```json
{
  "sub": "1001",
  "email": "user@example.com",
  "role": "member",
  "iat": 1715500000,
  "exp": 1715500900
}
```

**부수 효과**:
- Redis에 refresh_token 저장 (revocation 위해)
- `login_history` INSERT (IP, UA 기록)

---

### 3.3 토큰 갱신

```
POST /auth/refresh
```

**Request**:
```json
{
  "refresh_token": "eyJhbGc..."
}
```

**Response 200**: 새 access_token + refresh_token

---

### 3.4 로그아웃

```
POST /auth/logout
```

**Headers**: Authorization 필수

**Response 204**: No Content

**부수 효과**: Redis에서 해당 user의 모든 refresh_token 삭제

---

## 4. 회원 API (PII)

> **중요**: 이 API들은 `members-svc` Deployment만 처리. AWS Burst 모드에서도 트래픽이 **온프레로만** 라우팅됨 (NetworkPolicy + Ingress 룰).

### 4.1 내 정보 조회

```
GET /members/me
```

**Headers**: Authorization 필수

**Response 200**:
```json
{
  "data": {
    "id": 1001,
    "email": "user@example.com",
    "name": "홍길동",
    "phone": "010-1234-5678",
    "address": "서울시 강남구 ...",
    "profile_image_url": "https://cdn.kosa-day.example.com/profiles/abc.jpg",
    "role": "member",
    "created_at": "2024-01-15T10:00:00Z"
  }
}
```

---

### 4.2 내 정보 수정

```
PATCH /members/me
```

**Request** (부분 업데이트):
```json
{
  "name": "홍길순",
  "phone": "010-9999-9999"
}
```

**Response 200**: 업데이트된 정보

---

### 4.3 프로필 이미지 업로드

```
POST /members/me/profile-image
Content-Type: multipart/form-data
```

**Request**: file (이미지)

**Response 200**:
```json
{
  "data": {
    "profile_image_url": "https://cdn.kosa-day.example.com/profiles/xyz789.jpg",
    "rgw_object_key": "profiles/1001/xyz789.jpg"
  }
}
```

**서버 작업**:
1. 이미지 검증 (size < 5MB, MIME type)
2. Ceph RGW에 PUT (`s3.put_object(Bucket, Key, Body)`)
3. `profile_images` INSERT
4. CloudFront 캐시 무효화 (선택)

---

### 4.4 비밀번호 변경

```
POST /members/me/password
```

**Request**:
```json
{
  "current_password": "OldPass123!",
  "new_password": "NewPass456!"
}
```

**Response 204**

---

### 4.5 회원 탈퇴

```
DELETE /members/me
```

**Headers**: Authorization 필수
**Body** (이중 확인):
```json
{
  "password": "Pass123!"
}
```

**Response 204**

**부수 효과**:
- `members.status = 'inactive'` (soft delete)
- PII 데이터 90일 후 익명화 처리 (cron job 별도)
- 모든 refresh_token revoke

---

## 5. 상품 API

> 이 API들은 `app-svc`가 처리. ProxySQL 경유. 이벤트 시 Read 트래픽이 AWS RDS Replica로 분기.

### 5.1 상품 목록

```
GET /products
GET /products?category=books&page=1&size=20&sort=price&order=asc
GET /products?is_kosa_day=true
GET /products?search=kubernetes (FULLTEXT 검색)
```

**Response 200**:
```json
{
  "data": [
    {
      "id": 101,
      "name": "도커 완전 정복",
      "description": "컨테이너 입문서",
      "price": 35000,
      "stock": 100,
      "image_url": "https://cdn.kosa-day.example.com/products/101.jpg",
      "category": {
        "id": 1,
        "name": "도서"
      },
      "is_kosa_day_special": false,
      "average_rating": 4.5,
      "review_count": 23
    }
  ],
  "pagination": {
    "page": 1,
    "size": 20,
    "total": 150
  }
}
```

**캐싱**: Redis에 5분 TTL (`products:list:{hash_of_params}`)

---

### 5.2 상품 상세

```
GET /products/{id}
```

**Response 200**: 단일 상품 객체 + 최근 리뷰 5개

**부수 효과**: `view_count` 증가 (Redis로 비동기 처리 후 1분마다 DB sync)

---

### 5.3 kosa-day 특별 상품

```
GET /products/kosa-day
```

전용 엔드포인트 (이벤트 페이지용):
- `is_kosa_day_special = TRUE AND status = 'available'`
- 응답에 이벤트 메타 추가 (남은 시간, 한정 수량 등)

---

## 6. 주문 API

### 6.1 주문 생성

```
POST /orders
```

**Headers**: Authorization 필수

**Request**:
```json
{
  "items": [
    {"product_id": 101, "quantity": 2},
    {"product_id": 105, "quantity": 1}
  ],
  "shipping_address": "서울시 강남구 ...",
  "shipping_phone": "010-1234-5678",
  "payment_method": "card"
}
```

**Response 201**:
```json
{
  "data": {
    "id": 50001,
    "total_amount": 84000,
    "status": "pending",
    "items": [ ... ],
    "created_at": "2026-05-12T10:00:00Z"
  }
}
```

**서버 작업** (트랜잭션):
1. 재고 확인 + 차감 (Percona)
2. `orders` + `order_items` INSERT
3. Redis 카트 정리

**주의**: 이 트랜잭션은 반드시 Writer hostgroup으로 라우팅 (ProxySQL Rule)

---

### 6.2 내 주문 목록

```
GET /orders/my
GET /orders/my?status=paid&page=1
```

**Response**: 주문 목록 + pagination

**ProxySQL 라우팅**: SELECT → Reader hostgroup (Onprem 또는 AWS)

---

### 6.3 주문 상세

```
GET /orders/{id}
```

**권한**: 본인 주문만 (admin은 모두)

---

### 6.4 주문 취소

```
POST /orders/{id}/cancel
```

**조건**: status = `pending` 또는 `paid` (배송 전만)

**서버 작업** (트랜잭션):
1. `orders.status = 'cancelled'`
2. 재고 복구
3. 결제 환불 처리 (별도 PG사 연동, 본 프로젝트는 mock)

---

## 7. 리뷰 API

### 7.1 상품 리뷰 목록

```
GET /products/{id}/reviews?page=1&sort=helpful
```

**Response**: 리뷰 목록 (member name은 마스킹: "홍**")

---

### 7.2 리뷰 작성

```
POST /products/{id}/reviews
```

**Request**:
```json
{
  "rating": 5,
  "title": "정말 좋아요",
  "content": "..."
}
```

**조건**: 해당 상품을 구매한 회원만 작성 가능 (서버에서 검증)

---

### 7.3 리뷰 좋아요

```
POST /reviews/{id}/helpful
```

**부수 효과**: `helpful_count` 증가 (Redis 카운터 → 1분 sync)

---

## 8. 관리자 API

> 모든 API는 `role = 'admin'` 검증 필수.
> 통계/분석 쿼리는 **AWS RDS Replica로 라우팅** (ProxySQL Rule).

### 8.1 회원 검색

```
GET /admin/members?email=user@&page=1
```

> ⚠️ 회원 검색은 **Onprem만** (PII 보호).
> Network 레벨: members-svc를 통해서만 호출 가능.

---

### 8.2 주문 통계

```
GET /admin/stats/orders?period=last_7_days
```

**Response**:
```json
{
  "data": {
    "total_orders": 1250,
    "total_revenue": 45000000,
    "by_status": {
      "paid": 800,
      "shipped": 400,
      "delivered": 30,
      "cancelled": 20
    },
    "top_products": [...]
  }
}
```

**ProxySQL 라우팅**: 무거운 GROUP BY 쿼리 → AWS RDS Replica

---

### 8.3 매출 대시보드용 데이터

```
GET /admin/dashboard
```

**Response**: 종합 메트릭 (오늘 주문, 매출, 활성 회원 등)

**ProxySQL Rule**:
```sql
-- /admin/dashboard 호출 시 사용하는 쿼리들은 AWS로
-- 예시 패턴
^SELECT.*FROM v_orders_safe.*GROUP BY → AWS hostgroup 30
```

---

### 8.4 kosa-day 이벤트 활성화 (수동 트리거)

```
POST /admin/kosa-day/activate
```

**Body**:
```json
{
  "duration_hours": 24
}
```

**서버 작업**:
1. `products.is_kosa_day_special = TRUE` 상품 활성화
2. Lambda 트리거 (Route 53 weight 변경) — 수동 데모용
3. Slack/SNS 알림

---

### 8.5 kosa-day 이벤트 종료

```
POST /admin/kosa-day/end
```

이벤트 즉시 종료.

---

## 9. 헬스체크 & 메트릭

### 9.1 Liveness Probe

```
GET /healthz
```

**Response 200**: `{"status": "ok"}`

K8s liveness probe에서 사용. 단순히 프로세스 살아있는지만.

---

### 9.2 Readiness Probe

```
GET /readyz
```

**Response 200**: 모든 의존성 OK
**Response 503**: 일부 의존성 실패

**체크 항목**:
- DB 연결 (ProxySQL ping)
- Redis 연결
- Ceph RGW (옵션, 너무 무거우면 제외)

---

### 9.3 Prometheus Metrics

```
GET /metrics
```

`prometheus_client`로 노출:
```
# HELP http_requests_total Total HTTP requests
http_requests_total{method="GET",endpoint="/products",status="200"} 12345

# HELP http_request_duration_seconds Request latency
http_request_duration_seconds_bucket{le="0.05"} 100
http_request_duration_seconds_bucket{le="0.1"} 250
...

# Custom metrics
kosa_orders_created_total 250
kosa_active_sessions 35
kosa_db_connection_pool_size{hostgroup="10"} 100
```

---

## 10. 에러 코드 일람

| HTTP | code | 설명 |
|---|---|---|
| 400 | `INVALID_REQUEST` | 요청 body/query 오류 |
| 400 | `VALIDATION_ERROR` | 필드 검증 실패 |
| 401 | `UNAUTHENTICATED` | 토큰 없음 |
| 401 | `INVALID_CREDENTIALS` | 로그인 실패 |
| 401 | `TOKEN_EXPIRED` | 토큰 만료 |
| 403 | `FORBIDDEN` | 권한 부족 |
| 404 | `NOT_FOUND` | 리소스 없음 |
| 409 | `CONFLICT` | 중복 (예: email) |
| 409 | `OUT_OF_STOCK` | 재고 부족 |
| 429 | `RATE_LIMITED` | rate limit 초과 |
| 500 | `INTERNAL_ERROR` | 서버 에러 |
| 503 | `SERVICE_UNAVAILABLE` | DB/외부 시스템 장애 |

---

## 부록: FastAPI 골격 코드 예시

### 메인 앱 (`app/main.py`)

```python
from fastapi import FastAPI
from contextlib import asynccontextmanager
from prometheus_client import make_asgi_app

from app.config import settings
from app.database import init_db, close_db
from app.auth.routes import router as auth_router
from app.members.routes import router as members_router
from app.products.routes import router as products_router
from app.orders.routes import router as orders_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield
    await close_db()

app = FastAPI(
    title="kosa-day API",
    version="1.0.0",
    lifespan=lifespan,
)

# Prometheus
app.mount("/metrics", make_asgi_app())

# Routers
app.include_router(auth_router, prefix="/auth", tags=["auth"])
app.include_router(members_router, prefix="/members", tags=["members"])
app.include_router(products_router, prefix="/products", tags=["products"])
app.include_router(orders_router, prefix="/orders", tags=["orders"])

@app.get("/healthz")
async def healthz():
    return {"status": "ok"}

@app.get("/readyz")
async def readyz():
    # DB ping + Redis ping
    ...
```

### DB 연결 (ProxySQL)

```python
# app/database.py
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# ProxySQL endpoint (K8s Service)
DATABASE_URL = "mysql+aiomysql://kosa_app:password@proxysql.kosa-day.svc.cluster.local:6033/kosa_day"

engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,
    max_overflow=40,
    pool_pre_ping=True,
    pool_recycle=3600,
)

AsyncSessionLocal = sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
```

---

## 변경 이력

| 일자 | 내용 |
|---|---|
| 2026-05-12 | 초안 작성 |
