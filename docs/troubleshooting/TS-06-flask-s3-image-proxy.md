# TS-06 flask-s3-image-proxy

- Status: **Resolved**
- Date: 2026-05-15

## 증상

- S3 업로드는 성공하지만 웹에서 이미지가 보이지 않음
- 브라우저에서 presigned URL 접근 시 timeout 발생

## 원인

- Ceph RGW는 외부 인터넷/클라이언트 직접 접근이 차단된 네트워크에 위치함
- 기존 구조는 브라우저가 presigned URL로 RGW에 직접 접속해야 했음

## 해결

- `FlaskApp/application.py`를 presigned URL 노출 방식에서 Flask 프록시 방식으로 변경
- `/photo/<employee_id>` 라우트가 서버에서 S3 객체를 읽어 클라이언트에 전달하도록 수정
- 템플릿 표시 경로를 `employee.photo_url`로 통일

## 검증

- `/add` 저장 후 목록/상세 화면에서 이미지 표시 확인
- Flask 서버 로그에서 `S3 proxy read failed` 오류가 없는지 확인
