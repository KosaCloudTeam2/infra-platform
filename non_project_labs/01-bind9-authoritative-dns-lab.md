# 01. BIND9 권한 DNS 실습 (프로젝트 무관)

> 상태: Unverified 범위: **현재 프로젝트 아키텍처와 무관한 학습용 실습**

## 0) 목적

이 문서는 **권한 DNS(Authoritative DNS)** 서버를 온프레미스(On-Premises) 가상머신(VM)으로 직접
운영해보는 학습 실습이다.

핵심 목표:

- VM 2대에 BIND9 설치
- 도메인 존(Zone) 파일 작성
- 네임서버(NS) 위임 및 IP 등록(필요 시 Glue Record)
- `dig`/`nslookup` 검증

---

## 1) 먼저 알아둘 점 (중요)

1. BIND9는 **이름 해석(DNS)** 을 담당한다. 애플리케이션 트래픽의 직접 접속 경로(공인 진입점)는
   별도로 필요하다.

2. 온프레미스에 **공인 IP(Public IP)** 가 없으면, 인터넷에서 해당 DNS 서버를 직접 조회하기 어렵다.

3. 따라서 “가비아 -> 온프레 BIND9 직접 위임”을 하려면 보통 아래 중 하나가 필요하다.
   - 공인 IP를 가진 DNS 서버
   - 공인 IP를 가진 릴레이(Proxy/Relay)
   - 클라우드/IDC에 공개 DNS 노드 운영

---

## 2) 실습 토폴로지

예시:

- `ns1.lab.example.com` -> `203.0.113.10`
- `ns2.lab.example.com` -> `203.0.113.11`
- 존(Zone): `lab.example.com`
- 테스트 레코드:
  - `@` A -> `203.0.113.20`
  - `app` A -> `203.0.113.21`

> 위 값은 예시다. 실제 도메인/IP로 치환해서 사용.

---

## 3) VM 준비

OS 권장: Ubuntu 22.04+

필수 VM:

- DNS VM #1 (`ns1`)
- DNS VM #2 (`ns2`)

필수 포트:

- UDP 53
- TCP 53
- (관리용) TCP 22

---

## 4) BIND9 설치

각 VM에서:

```bash
sudo apt update
sudo apt install -y bind9 bind9utils dnsutils
```

서비스 확인:

```bash
sudo systemctl enable named
sudo systemctl status named --no-pager
```

---

## 5) 기본 보안 설정 (권한 DNS 전용)

파일: `/etc/bind/named.conf.options`

핵심 포인트:

- 재귀 질의(Recursive Query) 비활성화
- 외부 질의 허용 범위 최소화
- 리스닝 주소 명시

예시:

```conf
options {
    directory "/var/cache/bind";

    recursion no;
    allow-recursion { none; };

    allow-query { any; };

    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;
};
```

---

## 6) 존 파일 설정

### 6.1 zone 선언

파일: `/etc/bind/named.conf.local`

```conf
zone "lab.example.com" IN {
    type master;
    file "/etc/bind/zones/db.lab.example.com";
};
```

디렉터리 생성:

```bash
sudo mkdir -p /etc/bind/zones
```

### 6.2 zone 파일 작성

파일: `/etc/bind/zones/db.lab.example.com`

```dns
$TTL 300
@   IN SOA ns1.lab.example.com. admin.lab.example.com. (
        2026051801 ; Serial
        3600       ; Refresh
        900        ; Retry
        1209600    ; Expire
        300 )      ; Minimum

    IN NS  ns1.lab.example.com.
    IN NS  ns2.lab.example.com.

ns1 IN A   203.0.113.10
ns2 IN A   203.0.113.11
@   IN A   203.0.113.20
app IN A   203.0.113.21
```

문법 검사:

```bash
sudo named-checkconf
sudo named-checkzone lab.example.com /etc/bind/zones/db.lab.example.com
```

재기동:

```bash
sudo systemctl restart named
sudo systemctl status named --no-pager
```

---

## 7) 등록기관(가비아)에서 NS 위임

1. 도메인 관리에서 네임서버(NS) 설정 진입
2. `ns1.lab.example.com`, `ns2.lab.example.com` 등록
3. 해당 NS 호스트명에 대한 IP 등록(필요 시 Glue Record)
4. 저장 후 전파 대기

> 상위 존에서 하위 존 네임서버 호스트를 같은 도메인 하위로 둘 때 Glue Record가 필요할 수 있다.

---

## 8) DNS 서버 주소 세팅(클라이언트/검증 노드)

Linux 임시 테스트:

```bash
dig @203.0.113.10 lab.example.com NS
dig @203.0.113.10 app.lab.example.com A
```

Windows 테스트:

```powershell
nslookup app.lab.example.com 203.0.113.10
```

권한 응답 확인(aa flag):

```bash
dig @203.0.113.10 app.lab.example.com A +norecurse
```

---

## 9) 공인 IP 없는 환경에서의 현실적인 대안

공인 IP가 없는 온프레 DNS를 인터넷에 직접 공개하기 어렵다면:

1. Route53 Public Hosted Zone 유지(권장)
2. 내부 전용 DNS는 BIND9로 학습/운영
3. 외부 공개는 클라우드 공개 DNS/릴레이 사용

즉, **BIND9 자체는 학습/내부 운영에 유용하지만, 공인 진입점 문제를 자동 해결하지는 않는다.**

---

## 10) 자주 발생하는 문제

1. `SERVFAIL`
   - zone 문법 오류, SOA/NS 오타, named 미기동 확인

2. `NXDOMAIN`
   - 레코드 미존재, 위임 미완료, 캐시 전파 지연 확인

3. 외부에서 조회 불가
   - UDP/TCP 53 방화벽, 공인 라우팅, NS/Glue 설정 확인

4. 변경 반영 지연
   - TTL/캐시 특성상 수분~수시간(경우에 따라 24h+) 대기 필요

---

## 11) 체크리스트

- [ ] ns1/ns2 VM 준비 및 포트 오픈
- [ ] bind9 설치/기동 확인
- [ ] recursion 비활성화 확인
- [ ] zone 선언 및 파일 검증 통과
- [ ] 가비아 NS 위임/Glue 설정 반영
- [ ] `dig`/`nslookup` 권한 응답 확인

---

## 12) 범위 고지

이 문서는 **현재 팀 인프라 프로젝트의 표준 경로(Route53 + WireGuard Relay/BGP 분기)와 별개인 학습
실습 문서**다.
