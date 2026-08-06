# skill-goblin

Codex와 Claude Code에서 함께 사용할 개인용 Agent Skill을 로컬에서 만들고 검증하고 설치하기 위한 저장소다. 문서와 Skill 본문은 한국어를 기본으로 하며, Skill 이름과 스크립트 식별자는 검색성과 호환성을 위해 영어 kebab-case를 사용한다.

클라우드 Skill, GitHub Actions, 외부 서비스 연동은 이 저장소의 범위에 포함하지 않는다.

## 빠른 시작

PowerShell:

```powershell
./scripts/setup.ps1
./scripts/new-skill.ps1 -Name summarize-changes -Description "Git 변경 사항을 요약한다. 변경 검토나 커밋 준비를 요청할 때 사용한다."
./scripts/validate-skills.ps1
./scripts/install-skills.ps1 -Target All -Name summarize-changes
```

Bash 진입점은 `pwsh` 또는 `powershell.exe`가 설치된 환경에서 같은 PowerShell 코어를 실행한다.

```bash
./scripts/setup.sh
./scripts/new-skill.sh --name summarize-changes --description "Git 변경 사항을 요약한다. 변경 검토나 커밋 준비를 요청할 때 사용한다."
./scripts/validate-skills.sh
./scripts/install-skills.sh --target all --name summarize-changes
```

`setup`은 현재 저장소의 로컬 Git 설정만 변경한다. 전역 Git 설정은 변경하지 않는다.

## 저장소 구조

```text
skills/                    공용 Skill 원본
templates/skill/           새 Skill의 최소 템플릿
templates/provenance.md    MIT 파생 Skill의 출처 기록 템플릿
scripts/                   생성, 검증, 설치, 보안 검사 도구
.githooks/                 추적되는 pre-commit/pre-push hook
AGENTS.md                  Codex와 Agent가 따를 공통 규칙
CLAUDE.md                  Claude Code에서 공통 규칙을 연결
docs/agent/                작업 단계별 Agent 참조 인덱스와 유지관리 기준
```

각 Skill은 `skills/<skill-name>/SKILL.md`를 진입점으로 사용한다. `SKILL.md`의 YAML frontmatter에는 공통 호환성을 위해 `name`과 `description`만 둔다. 자세한 자료는 `references/`, 반복 가능한 코드는 `scripts/`, 출력에 쓰는 재료는 `assets/`에 필요한 경우에만 추가한다.

## Agent 지침 사용

[AGENTS.md](AGENTS.md)에는 모든 작업에서 필요한 구현 원칙과 저장소 고유 원칙만 둔다. 프로젝트 구조나 전체 명령처럼 탐색 가능한 정보와 단계별 체크리스트는 반복하지 않는다.

외부 자료 반입, Skill 수정, 스크립트 작성, 커밋·푸시 준비처럼 특정 단계에 들어가면 [Agent 참조 인덱스](docs/agent/INDEX.md)에서 현재 작업과 일치하는 행만 읽는다. Agent 지침을 추가하거나 정리할 때는 [컨텍스트 유지관리 기준](docs/agent/context-maintenance.md)을 적용한다.

## Skill 설치

설치 스크립트는 심볼릭 링크 대신 검증된 복사본을 만든다.

- Codex: `$CODEX_HOME/skills`, `CODEX_HOME`이 없으면 `~/.codex/skills`
- Claude Code: `$CLAUDE_HOME/skills`, `CLAUDE_HOME`이 없으면 `~/.claude/skills`

대상에 같은 내용이 있으면 건너뛴다. 다른 내용이 있으면 기본적으로 중단하며, 의도적으로 교체할 때만 `-Force` 또는 `--force`를 사용한다.

## Git 운영

- `main`은 안정 상태로 유지한다.
- 작업 브랜치는 `feat/*`, `fix/*`, `chore/*`를 짧게 사용한다.
- 병합 시 squash를 기본으로 한다.
- 커밋 제목은 한국어 또는 영어를 사용할 수 있으며 Conventional Commits를 강제하지 않는다.

## 외부 Skill과 라이선스

외부 자료를 반입하기 전에 해당 revision의 MIT 라이선스를 직접 확인한다. 실질적으로 복사하거나 변형한 Skill은 `references/provenance.md`를 만들고, 루트 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에도 원본 URL, commit/tag, 저작자, 라이선스, 사용 범위와 변경 내용을 기록한다.

라이선스가 없거나 MIT 호환 여부가 불명확한 자료는 코드나 문구를 반입하지 않는다. 아이디어만 참고한 경우에도 판단 근거와 출처를 기록한다.

## 공개 전 보안 확인

Git hook은 staged 파일과 push 대상 commit에서 위험 파일명과 알려진 secret 패턴을 검사한다. Gitleaks가 설치되어 있으면 추가 검사를 실행하며, 자동 설치하거나 네트워크에 접근하지 않는다.

```powershell
./scripts/check-sensitive.ps1 -Staged
./scripts/check-sensitive.ps1 -All
```

정규식 검사는 회사 기밀이나 개인정보의 의미를 완전히 판별할 수 없다. 공개 전에는 [SECURITY.md](SECURITY.md)의 사람 검토 항목도 반드시 확인한다.

## 개발 검증

```powershell
./tests/run-tests.ps1
./scripts/validate-skills.ps1
./scripts/check-sensitive.ps1 -All
git diff --check
```

## 라이선스

이 저장소는 [MIT License](LICENSE)를 사용한다.
