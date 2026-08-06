# skill-goblin

Codex와 Claude Code에서 함께 사용할 개인용 Agent Skill을 로컬에서 만들고, 검증하고, 설치하는 저장소다. `skills/`를 공용 원본으로 유지하고 도구별 개인 Skill 경로에는 검증된 복사본을 배포한다.

문서와 Skill 본문은 한국어를 기본으로 작성하며, Skill 이름과 코드 식별자는 검색성과 호환성을 위해 영어를 사용한다. 클라우드 Skill, GitHub Actions, 외부 서비스 연동은 다루지 않는다.

현재 다음 Skill을 제공한다.

| Skill | 용도 | 명시 호출 |
| --- | --- | --- |
| `write-commit-message` | 프로젝트 규약과 변경 의도를 반영해 커밋 메시지를 작성·수정·검토한다. | `$write-commit-message` |
| `polish-korean` | 의미와 필자의 목소리를 보존하면서 한국어 문서를 자연스럽고 명료하게 윤문한다. | `$polish-korean` |
| `reverse-engineer-service` | 코드·설정·인프라·런타임 증거를 대조해 서비스 구조와 대표 시나리오를 재구성한다. | `$reverse-engineer-service` |
| `write-diataxis-docs` | 검증된 자료를 독자의 목적에 맞는 튜토리얼·방법 안내서·참조·설명 문서로 작성·재구성·검토한다. | `$write-diataxis-docs` |

한국어 문서를 보수적으로 윤문하려면 다음처럼 호출한다.

```text
$polish-korean 강도: 보수
이 문서를 수치와 고유명사를 유지하면서 자연스럽게 윤문해줘:

[본문]
```

처음 접하는 서비스의 주문 생성 흐름을 분석하려면 다음처럼 호출한다.

```text
$reverse-engineer-service 이 저장소가 제공하는 가치와 전체 구조에서 시작해 주문 생성의 성공 경로와 비동기 실패 경로를 추적해줘.
```

역공학 결과를 운영자를 위한 방법 안내서로 바꾸려면 다음처럼 호출한다.

```text
$write-diataxis-docs docs/reverse-engineering의 근거를 사용해 실패한 주문 처리만 안전하게 재실행하는 방법 안내서를 작성해줘.
```

`reverse-engineer-service`는 대상 저장소의 코드를 실행하지 않는 정적 분석기로 엔트리포인트와 읽을 범위를 먼저 추출한다. Python은 표준 AST만으로 동작한다. JavaScript/TypeScript의 의미 기반 trace에는 대상 저장소의 `typescript` 또는 명시적인 TypeScript Compiler API 경로가 필요하다. Compiler API가 없고 대상 저장소에 `dependency-cruiser`가 있으면 module-only trace로 축소하며, 둘 다 없으면 패키지를 자동 설치하지 않고 manifest 탐색까지만 수행한다.

## 지원 범위

- 로컬 Codex CLI·IDE·데스크톱 환경에서 발견되는 개인 Skill
- 로컬 Claude Code에서 발견되는 개인 Skill
- PowerShell 기준 구현과 동일한 핵심 동작을 제공하는 Bash 진입점
- MIT 공개 저장소에 맞춘 외부 자료 출처 관리와 민감정보 차단

필요한 도구는 Git과 PowerShell 5.1 이상 또는 PowerShell 7이다. Bash 진입점도 내부적으로 `pwsh` 또는 `powershell.exe`를 사용한다. Gitleaks는 선택 사항이지만 설치되어 있으면 hook과 수동 검사에서 추가 탐지 계층으로 자동 사용된다.

## 빠른 시작

```powershell
git clone https://github.com/Innnteraction/skill-goblin.git
Set-Location skill-goblin
./scripts/setup.ps1
./scripts/new-skill.ps1 -Name summarize-changes -Description "Git 변경 사항을 요약한다. 변경 검토나 커밋 준비를 요청할 때 사용한다."
./scripts/validate-skills.ps1
./scripts/install-skills.ps1 -Target All -Name summarize-changes
```

`setup`은 현재 저장소에만 다음 Git 설정과 hook 경로를 적용하며 전역 설정은 바꾸지 않는다. 이 저장소는 개인용이므로 `user.name=Innnteraction`, `user.email=innnteractive@gmail.com`을 사용한다. 포크에서 다른 identity를 사용할 경우 `scripts/setup.ps1`의 값을 먼저 변경해야 한다.

Bash에서는 같은 PowerShell 코어를 호출하는 진입점을 사용한다.

```bash
git clone https://github.com/Innnteraction/skill-goblin.git
cd skill-goblin
./scripts/setup.sh
./scripts/new-skill.sh --name summarize-changes --description "Git 변경 사항을 요약한다. 변경 검토나 커밋 준비를 요청할 때 사용한다."
./scripts/validate-skills.sh
./scripts/install-skills.sh --target all --name summarize-changes
```

## GitHub에서 설치

재현 가능한 설치에는 `v0.1.0` 태그를 사용한다. `main`은 다음 릴리스 전 변경을 평가하려는 경우에만 태그 자리에 사용한다.

Codex에서는 `$skill-installer`에 GitHub의 Skill 경로와 설치 목적지를 함께 전달한다. 전역 설치 요청은 다음과 같다.

```text
$skill-installer Install https://github.com/Innnteraction/skill-goblin/tree/v0.1.0/skills/write-commit-message into $HOME/.agents/skills.
```

특정 프로젝트에만 설치하려면 해당 저장소의 절대 경로 아래 `.agents/skills`를 목적지로 지정한다.

```text
$skill-installer Install https://github.com/Innnteraction/skill-goblin/tree/v0.1.0/skills/write-commit-message into <project>/.agents/skills.
```

Claude Code의 standalone Skill은 저장소를 clone한 뒤 공용 설치 스크립트로 복사한다. GitHub marketplace나 plugin manifest는 사용하지 않는다.

```powershell
git clone --branch v0.1.0 https://github.com/Innnteraction/skill-goblin.git
Set-Location skill-goblin
./scripts/install-skills.ps1 -Target Claude -Name write-commit-message
./scripts/install-skills.ps1 -Target Claude -Scope Project -ProjectPath <project> -Name write-commit-message
```

```bash
git clone --branch v0.1.0 https://github.com/Innnteraction/skill-goblin.git
cd skill-goblin
./scripts/install-skills.sh --target claude --name write-commit-message
./scripts/install-skills.sh --target claude --scope project --project-path <project> --name write-commit-message
```

Codex도 clone한 저장소에서 같은 스크립트를 사용할 수 있다. `--target codex` 또는 `-Target Codex`를 선택하면 된다. 설치 후 새 Skill은 다음 Agent 대화부터 사용할 수 있다.

## 기본 사용 흐름

1. **Create** — 템플릿에서 `skills/<skill-name>/SKILL.md`와 필요한 보조 디렉터리를 만든다.
2. **Validate** — 구조, frontmatter, 이름, 참조 경로, 길이와 민감정보를 검사한다.
3. **Install** — 검증된 Skill을 Codex·Claude Code 개인 경로로 복사한다.
4. **Use** — Codex에서는 `$skill-name`, Claude Code에서는 `/skill-name`으로 명시적으로 호출하거나 설명과 일치하는 작업에서 자동 선택되게 한다.
5. **Update** — 공용 원본만 수정하고 다시 검증·설치한다. 설치된 복사본은 직접 편집하지 않는다.

## 주요 명령

| 목적 | PowerShell | Bash |
| --- | --- | --- |
| 저장소 로컬 Git 설정과 hook 활성화 | `./scripts/setup.ps1` | `./scripts/setup.sh` |
| Skill 골격 생성 | `./scripts/new-skill.ps1 -Name <name> -Description <text>` | `./scripts/new-skill.sh --name <name> --description <text>` |
| 전체 Skill 검증 | `./scripts/validate-skills.ps1` | `./scripts/validate-skills.sh` |
| 특정 Skill 설치 | `./scripts/install-skills.ps1 -Target All -Name <name>` | `./scripts/install-skills.sh --target all --name <name>` |
| 전체 Skill 설치 | `./scripts/install-skills.ps1 -Target All` | `./scripts/install-skills.sh --target all` |
| 프로젝트에 특정 Skill 설치 | `./scripts/install-skills.ps1 -Target All -Scope Project -ProjectPath <project> -Name <name>` | `./scripts/install-skills.sh --target all --scope project --project-path <project> --name <name>` |
| staged 민감정보 검사 | `./scripts/check-sensitive.ps1 -Staged` | `./scripts/check-sensitive.sh -Staged` |
| 전체 민감정보 검사 | `./scripts/check-sensitive.ps1 -All` | `./scripts/check-sensitive.sh -All` |

`new-skill`에는 필요할 때만 `-WithReferences`, `-WithScripts`, `-WithAssets`를 추가한다. Bash에서는 각각 `--with-references`, `--with-scripts`, `--with-assets`를 사용한다.

## Skill 구조

```text
skills/
└── <skill-name>/
    ├── SKILL.md          필수: name, description과 핵심 지침
    ├── references/       선택: 필요할 때만 읽는 상세 자료와 provenance
    ├── scripts/          선택: 반복 가능하고 결정적인 작업
    └── assets/           선택: 템플릿과 출력 재료
```

- 이름은 64자 이하의 kebab-case를 사용한다.
- `SKILL.md`의 YAML frontmatter에는 공통 호환성을 위해 `name`과 `description`만 둔다.
- 본문은 500줄 미만을 권장하며 내부 경로는 운영체제와 관계없이 `/`로 표기한다.
- 설명은 Skill의 용도와 호출 시점을 구체적으로 적어 Codex와 Claude Code가 올바르게 선택할 수 있게 한다.
- 외부 MIT Skill을 실질적으로 변형한 경우 `references/provenance.md`와 루트의 제3자 고지를 함께 갱신한다.

공식 규격은 [Codex Build skills](https://learn.chatgpt.com/docs/build-skills)와 [Claude Code Skills](https://code.claude.com/docs/en/skills)에서 확인할 수 있다. 이 저장소는 두 도구가 공통으로 해석할 수 있는 최소 frontmatter만 기본 제공한다.

## 설치와 동기화

| 대상 | `User` 범위 | `Project` 범위 |
| --- | --- | --- |
| Codex | `$HOME/.agents/skills/<skill-name>` | `<project>/.agents/skills/<skill-name>` |
| Claude Code | `~/.claude/skills/<skill-name>` 또는 `CLAUDE_HOME/skills/<skill-name>` | `<project>/.claude/skills/<skill-name>` |

Windows에서 `$HOME`이 비어 있으면 사용자 프로필 디렉터리를 사용한다. Codex의 이전 설치 위치였던 `$CODEX_HOME/skills` 또는 `~/.codex/skills`는 더 이상 설치 대상으로 사용하지 않으며 기존 복사본을 자동 삭제하지 않는다. 필요한 Skill이 새 경로에 정상 설치됐는지 확인한 뒤 이전 복사본을 별도로 정리한다.

설치 스크립트는 심볼릭 링크 대신 검증된 복사본을 만든다.

- 대상에 같은 내용이 있으면 `[same]`으로 건너뛴다.
- 다른 내용이 있으면 기본적으로 중단하고 충돌 경로를 보고한다.
- 의도적으로 교체할 때만 `-Force` 또는 `--force`를 사용한다.
- `-Target Codex`, `Claude`, `All` 중 하나로 설치 대상을 선택한다.
- 설치 범위의 기본값은 기존 동작과 같은 `User`다.
- `Project` 범위에서는 존재하는 디렉터리를 `-ProjectPath` 또는 `--project-path`로 반드시 지정한다.

## 버전과 릴리스

이 저장소는 초기 단계에서 약식 [Semantic Versioning 2.0.0](https://semver.org/) 정책을 사용한다.

- `0.y.0`: 새 Skill 추가, 기존 Skill의 동작 변경, 설치 계약 변경
- `0.y.z`: 호환 가능한 수정과 문서 보완
- `1.0.0`: Skill 이름·호출 방식·설치 경로를 안정된 계약으로 선언하는 첫 버전

릴리스는 이동하지 않는 annotated `vX.Y.Z` [Git 태그](https://git-scm.com/docs/git-tag)로 표시한다. 공개한 태그는 수정하거나 강제로 옮기지 않으며, 문제는 다음 patch 버전으로 고친다. `main`은 최신 평가용이고 버전 태그는 재현 가능한 설치용이다.

## 보안과 외부 자료

`.githooks/pre-commit`은 staged 상태를, `.githooks/pre-push`는 push 대상 commit을 검사한다. 내장 검사는 위험 파일명과 알려진 secret 패턴을 실제 값 없이 보고하고, Gitleaks가 있으면 redaction을 적용한 추가 검사를 실행한다.

```powershell
./scripts/check-sensitive.ps1 -Staged
./scripts/check-sensitive.ps1 -All
```

자동 검사는 회사 기밀, 개인정보, 실제 업무 데이터의 의미를 완전히 판별할 수 없다. 공개 전에는 [SECURITY.md](SECURITY.md)의 사람 검토 절차에 따라 파일 목록과 diff를 직접 확인한다.

외부 Skill의 코드나 문구를 반입하려면 확인한 revision에서 MIT 라이선스임을 검증한다. 실질적으로 복사하거나 변형했다면 원저작권 고지를 보존하고 [provenance 템플릿](templates/provenance.md)과 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 출처·revision·사용 범위·변경 내용을 기록한다. 라이선스가 없거나 불명확한 자료는 반입하지 않는다.

## 개발과 유지관리

전체 회귀 검증은 임시 Git 저장소와 임시 HOME을 사용하므로 개인 Skill 설치 경로를 수정하지 않는다.

```powershell
./tests/run-tests.ps1
./scripts/validate-skills.ps1
./scripts/check-sensitive.ps1 -All
git diff --check
```

Git 운영은 `main`을 안정 상태로 유지하고 `feat/*`, `fix/*`, `chore/*` 작업 브랜치를 짧게 사용한 뒤 squash 병합하는 방식을 기본으로 한다. 커밋 메시지는 [커밋 메시지 작성 Skill](skills/write-commit-message/SKILL.md)의 확장 타입 접두사를 사용하고 제목은 한국어 또는 영어를 허용한다. Conventional Commits 자체를 엄격히 강제하거나 별도 hook으로 검사하지는 않는다.

Agent가 항상 따라야 할 원칙은 [AGENTS.md](AGENTS.md)에 간결하게 유지한다. 특정 작업에서만 필요한 상세 절차는 [Agent 참조 인덱스](docs/agent/INDEX.md)로 연결하고, 규칙을 추가하거나 정리할 때는 [컨텍스트 유지관리 기준](docs/agent/context-maintenance.md)을 적용한다.

## 문서 지도

| 문서 | 역할 |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Codex와 Agent가 항상 적용할 구현·저장소 원칙 |
| [CLAUDE.md](CLAUDE.md) | Claude Code에서 공통 지침으로 연결하는 진입점 |
| [Agent 참조 인덱스](docs/agent/INDEX.md) | 작업 단계에 따라 선택적으로 읽을 정본 문서 안내 |
| [SECURITY.md](SECURITY.md) | 반입 금지 정보, 공개 전 사람 검토, 유출 대응 |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | 외부 Skill과 아이디어 수준 참고 자료의 출처 기록 |

## 라이선스

이 저장소의 독자적인 코드와 문서는 [MIT License](LICENSE)를 사용한다. 외부 자료는 각 출처에 기록된 라이선스와 고지 조건을 별도로 따른다.
