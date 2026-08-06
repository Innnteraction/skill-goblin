# Git 작업, Skill 버전과 릴리스

`main`은 통합 가능한 상태로 유지하고 작업·내부 버전·전체 배포 버전을 서로 다른 생명주기로 관리한다.

## 작업 시작

모든 변경은 `feat/<slug>`, `fix/<slug>`, `chore/<slug>` 작업 브랜치에서 수행한다. 기본 checkout의 `main`에는 직접 커밋하지 않는다.

`scripts/setup`은 `merge.ff=only`, `pull.ff=only`, `push.default=nothing`을 저장소 local config에 적용한다. 인자 없는 `git push`에 의존하지 말고 공개할 때는 remote와 `main`을 명시한다.

단일 세션에서는 기본 checkout에서 최신 `main`을 기준으로 작업 브랜치를 만든다. 두 세션 이상이 동시에 작업하면 기본 checkout은 통합 전용으로 남기고 세션마다 sibling worktree를 만든다.

```text
../skill-goblin-worktrees/<task>
```

새 worktree는 최신 local `main`에서 명시적인 새 브랜치와 함께 만든다.

```bash
git worktree add ../skill-goblin-worktrees/<task> -b feat/<slug> main
```

경로 또는 브랜치가 이미 존재하면 `--force`나 `-B`로 덮어쓰지 말고 기존 worktree와 작업 상태를 확인한다. 한 브랜치를 둘 이상의 worktree에서 checkout하지 않는다.

## Skill 내부 버전

각 `skills/<name>/VERSION`은 설치 산출물의 revision을 나타내는 점 없는 양의 정수다.

- 새 Skill은 `1`로 시작한다.
- `SKILL.md`, `references/`, `scripts/`, `assets/` 등 Skill 디렉터리의 설치 산출물이 바뀌면 해당 통합 작업에서 VERSION을 정확히 1 올린다.
- 한 작업에서 같은 Skill의 파일을 여러 개 또는 여러 commit으로 바꿔도 한 번만 올린다.
- 여러 Skill을 바꾸면 각 Skill의 VERSION을 올린다.
- 저장소 공용 문서나 도구만 바뀌면 Skill VERSION은 바꾸지 않는다.
- 과거 VERSION을 다시 사용하거나 배포 뒤 숫자를 낮추지 않는다.

VERSION 변경 누락은 검증기가 자동 판별하지 못하므로 staged diff에서 해당 Skill의 이전 값과 직접 대조한다.

## 완료와 main 통합

1. 작업 브랜치에서 관련 검사, 전체 Skill 검증, 민감정보 검사를 실행한다.
2. 공개할 파일만 stage하고 staged diff 전체를 직접 읽은 뒤 커밋한다.
3. 원격 `main`을 fetch하고 기본 checkout의 local `main`을 `origin/main`에 fast-forward한다.
4. 작업 worktree에서 작업 브랜치를 최신 local `main`에 rebase한다. 충돌을 해결하면 검사를 다시 실행한다.
5. 기본 checkout의 clean `main`에서 `git merge --ff-only <branch>`를 실행한다. fast-forward할 수 없으면 병합 commit을 만들지 말고 rebase 상태를 다시 확인한다.
6. `main`과 `origin/main`의 차이, commit과 working tree를 확인한 뒤 `git push origin main`을 실행한다.
7. 원격 `main`이 같은 commit인지 확인한 후 clean linked worktree를 `git worktree remove <path>`로 제거하고 병합된 local 작업 브랜치를 `git branch -d <branch>`로 삭제한다.

여러 작업은 한 번에 하나씩 위 순서로 통합한다. 먼저 병합된 작업 때문에 `main`이 바뀌면 다음 작업 브랜치를 다시 rebase하고 검증한다. 작업 브랜치 push, PR, squash merge는 사용자가 명시적으로 요청할 때만 사용한다.

## 전체 배포 버전

루트 `VERSION`은 `X.Y.Z` 형식으로 마지막으로 배포된 전체 버전을 기록한다. 일상적인 main 통합에서는 바꾸지 않고 명시적인 배포 작업에서만 갱신한다.

최신 annotated tag 이후 누적 변경의 가장 높은 수준을 한 번 적용한다.

| 변경 | 다음 버전 |
| --- | --- |
| 공용 Skill 계약이나 설치·배포 방식의 비호환 변경 | `X+1.0.0` |
| 하나 이상의 새 Skill 추가 | `X.Y+1.0` |
| 기존 Skill 수정, 호환 가능한 설치기·검증기·공용 문서 변경 | `X.Y.Z+1` |

높은 수준의 변경은 낮은 수준의 변경을 포함한다. 여러 Skill이 추가되어도 한 배포에서는 minor를 한 번만 올린다. 다음 배포 후보는 최신 배포 tag 이후 누적 변경만으로 판단한다.

## 배포

1. 최신 배포 tag와 루트 VERSION이 일치하는지 확인한다.
2. 최신 tag 이후 변경을 검토해 새 버전을 결정한다.
3. 루트 VERSION과 README의 설치 tag 예시를 새 버전으로 갱신한다.
4. 전체 테스트, Skill 검증, 민감정보 검사와 공개 diff 검토를 완료한다.
5. release commit을 만든 뒤 같은 commit에 이동하지 않는 annotated `vX.Y.Z` tag를 만든다.
6. `main`을 먼저 push하고 원격 commit을 확인한 다음 tag를 push한다.

이미 공개한 VERSION이나 tag는 수정하거나 강제로 이동하지 않는다. 잘못된 배포는 다음 patch 버전으로 고친다.
