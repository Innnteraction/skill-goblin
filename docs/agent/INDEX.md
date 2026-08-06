# Agent 참조 인덱스

`AGENTS.md`는 항상 적용한다. 아래 표에서는 현재 작업과 일치하는 행만 읽고, 연결된 문서를 작업 절차의 정본으로 사용한다.

| 작업 단계 | 참조 대상 | 반드시 얻어야 할 결과 |
| --- | --- | --- |
| Skill 생성·수정 | [Skill 구조](../../README.md#skill-구조), [Git 작업·버전·릴리스](git-workflow-and-releases.md), [Skill 템플릿](../../templates/skill/SKILL.md), [검증 도구](../../scripts/validate-skills.ps1) | 공용 구조와 frontmatter 규격을 지키고 내부 VERSION 값과 검증 명령을 결정한다. |
| 여러 세션 동시 작업 시작 | [Git 작업·버전·릴리스](git-workflow-and-releases.md) | 세션별 작업 브랜치와 sibling worktree를 만들고 기본 checkout의 `main`을 통합 전용으로 보존한다. |
| 반복 작업용 스크립트 추가·수정 | [빠른 시작](../../README.md#빠른-시작), [통합 테스트](../../tests/run-tests.ps1), [줄바꿈 규칙](../../.gitattributes) | PowerShell 기준 구현과 Bash 진입점의 성공·대표 실패 경로를 정한다. |
| 외부 Skill·코드·문구 조사 또는 반입 | [보안과 외부 자료](../../README.md#보안과-외부-자료), [제3자 고지](../../THIRD_PARTY_NOTICES.md), [provenance 템플릿](../../templates/provenance.md) | 해당 revision의 사용 가능 여부와 필요한 출처 기록을 확정한다. |
| 커밋 준비 | [커밋 메시지 작성 Skill](../../skills/write-commit-message/SKILL.md), [공개 저장소 보안 정책](../../SECURITY.md#커밋-전-확인), [민감정보 검사](../../scripts/check-sensitive.ps1) | staged 변경을 검토하고 규약에 맞는 메시지 작성과 보안 검사를 완료한다. |
| 작업 완료와 main 통합 | [Git 작업·버전·릴리스](git-workflow-and-releases.md), [공개 저장소 보안 정책](../../SECURITY.md#커밋-전-확인) | 최신 `main`에 rebase·재검증하고 fast-forward 병합한 뒤 `main`만 push하고 clean worktree를 정리한다. |
| 배포 준비 | [Git 작업·버전·릴리스](git-workflow-and-releases.md), [보안과 외부 자료](../../README.md#보안과-외부-자료), [pre-push hook](../../.githooks/pre-push), [민감정보 검사](../../scripts/check-sensitive.ps1) | 전체 VERSION과 annotated tag를 결정하고 push 범위 전체가 공개 가능한지 확인한다. |
| Agent 지침 추가·수정 | [컨텍스트 유지관리](context-maintenance.md) | 규칙을 상시 지침에 둘지, 선택 참조로 둘지, 제외할지 결정한다. |

표의 문서와 현재 구현이 다르면 실제 코드와 테스트를 먼저 확인한다. 정본을 바꿔야 할 때는 관련 문서와 검증도 같은 작업에서 갱신한다.
