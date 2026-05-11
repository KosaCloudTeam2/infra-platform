- 최신 main 받기

```bash
git checkout main
git pull
```

- 작업 브랜치 이동

```bash
git checkout feature-branch
```

- 최신 main 기준으로 rebase 시작

```bash
git rebase main
```

- 충돌 발생 확인

```text
CONFLICT (content): ...
```

- 충돌 파일 열어서 수정
  - `<<<<<<<`
  - `=======`
  - `>>>>>>>` 제거 후 원하는 내용만 남김

- 충돌 해결 파일 staging

```bash
git add .
```

- rebase 계속 진행

```bash
git rebase --continue
```

- vim 뜨면 저장 후 종료

```text
Esc
:wq
Enter
```

- 다음 충돌 나면 반복

```bash
git add .
git rebase --continue
```

- rebase 완료 확인

```text
Successfully rebased and updated ...
```

- 원격 브랜치에 강제 반영

```bash
git push --force-with-lease
```

- push 중 보안 hook 실패 시(dependency 취약점 등)

```bash
uv lock --upgrade-package 취약라이브러리
```

- dependency 파일 갱신 후 commit

```bash
git add .
git commit -m "chore: security dependency update"
```

- 다시 push

```bash
git push --force-with-lease
```

- rebase 중단하고 원복하고 싶을 때

```bash
git rebase --abort
```

- 절대 하면 안 되는 실수
  - rebase 중 충돌 해결 후 `git commit` 직접 실행
  - rebase 끝난 뒤 습관적으로 `git pull`
  - 일반 `git push`만 시도
  - 충돌 마커 남긴 채 add

- merge와 rebase 차이
  - merge 충돌 해결 후:

```bash
git commit
```

- rebase 충돌 해결 후:

```bash
git rebase --continue
```
