# MkDocs Guide

Markdown 문서를 웹 사이트 형태로 확인하기 위한 MkDocs 사용 절차

---

## 1. 목적

MkDocs는 `docs/` 아래 Markdown 문서를 웹 문서 사이트로 확인하기 위한 선택 도구임. 문서 파일을
이동하지 않고 `mkdocs.yml`의 navigation으로 현재 읽기 순서를 표현함.

발표 PDF는 기존 Marp 절차를 계속 사용함.

## 2. 설치

프로젝트 dev 의존성에 MkDocs와 Material 테마가 포함되어 있으므로 저장소 초기화 후 아래 명령으로
설치함.

```powershell
uv sync --group dev
```

`Unrecognised theme name: 'material'` 오류가 나오면 `mkdocs-material`이 현재 uv 환경에 설치되지 않은
상태임. 이 경우 `uv sync --group dev`를 다시 실행하고 새 터미널에서 확인함.

## 3. 로컬 미리보기

기본 `8000` 포트 충돌을 피하기 위해 `8010` 포트를 사용함.

```powershell
uv run mkdocs serve -a 127.0.0.1:8010
```

브라우저에서 확인:

```text
http://127.0.0.1:8010
```

## 4. 정적 사이트 빌드

정적 사이트 빌드는 GitHub Pages 또는 별도 호스팅을 적용할 때만 수행함. 평소 문서 확인은 `serve`만
사용함.

```powershell
uv run mkdocs build
```

주의:

- `site/` 출력물은 커밋하지 않음
- 원본 Markdown은 계속 `docs/` 아래에서 관리함
- 문서 위치를 대규모 이동하기보다 `mkdocs.yml`의 `nav`를 먼저 조정함
