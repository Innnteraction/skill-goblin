# Third-Party Notices

현재 외부 Skill의 코드나 실질적 문구를 포함하지 않는다.

외부 MIT Skill을 복사하거나 변형할 때 아래 형식으로 항목을 추가하고 원본의 저작권 및 라이선스 고지를 보존한다.

```text
## <upstream skill name>

- Source: <repository URL>
- Revision: <commit SHA or tag>
- Author/Copyright: <upstream notice>
- License: MIT (<license URL at the recorded revision>)
- Used in: skills/<skill-name>/
- Scope: <copied, transformed, or referenced parts>
- Changes: <summary of the rewrite or adaptation>
```

## 아이디어 수준 참고 자료

### Diátaxis 문서 설계

- Sources:
  - https://diataxis.fr/
  - https://diataxis.fr/compass/
  - https://diataxis.fr/quality/
  - https://www.gov.uk/service-manual/user-research/start-by-learning-user-needs
  - https://docs.oasis-open.org/dita/v1.0/langspec/audience.html
  - https://developers.google.com/tech-writing/one/audience
  - https://doi.org/10.1023/A:1011143116306
  - https://doi.org/10.1207/s15516709cog0702_3
  - https://doi.org/10.1007/s10648-007-9054-3
  - https://research.ibm.com/publications/how-do-designers-and-user-experience-professionals-actually-perceive-and-use-personas
  - https://www.w3.org/TR/2021/WD-personalization-semantics-content-1.0-20210812/
  - https://github.com/joshuadavidthomas/agent-skills/tree/main/skills/diataxis
- Checked: 2026-08-07
- License decision: Diátaxis 공식 자료와 공개 Skill의 CC BY-SA 4.0 기반 설명, GOV.UK·Google의 사용자·독자 지침, OASIS DITA와 W3C의 audience·personalization 메타데이터, 적응형 하이퍼미디어·공통 기반과 구조 매핑·전문성 역전 연구, IBM의 페르소나 운용 연구를 외부 코드·Skill 문구의 반입 대상으로 사용하지 않고 개념과 검증 관점만 참고함
- Scope: `skills/write-diataxis-docs/`의 문서 계약, 유형 선택, 유형 간 내용 분리, 근거 검증, 역할 기반 독자 프로필, 공통 기반, 주제별 지식 상태, 개념 연결, 적응 결정과 독자 경험 검토 설계
- Included material: 원문의 문구·템플릿·도표나 메타데이터 형식을 복사하거나 번역하지 않고 이 저장소의 역공학 evidence 계약과 소프트웨어·제품 문서 요구에 맞춰 독자적으로 작성

### 서비스 아키텍처 재구성 및 코드 탐색

- Sources:
  - https://github.com/lmammino/c4-codebase-architecture-skill
  - https://github.com/CodeBoarding/CodeBoarding
  - https://github.com/tecture-io/tecture
  - https://github.com/OpenBMB/RepoAgent
  - https://aider.chat/docs/repomap.html
  - https://sourcegraph.com/docs/cody/core-concepts/code-graph
  - https://backstage.io/docs/next/features/software-catalog/system-model/
  - https://insights.sei.cmu.edu/documents/688/2002_005_001_14060.pdf
  - https://c4model.com/introduction
  - https://docs.arc42.org/section-6/
  - https://www.uber.com/us/en/blog/distributed-tracing/
  - https://www.uber.com/en-SE/blog/crisp-critical-path-analysis-for-microservice-architectures/
  - https://opentelemetry.io/docs/concepts/signals/
  - https://aws.amazon.com/blogs/migration-and-modernization/aws-transform-comprehensive-codebase-analysis-for-modernization/
  - https://docs.github.com/en/copilot/tutorials/explore-a-codebase
- Checked: 2026-08-06
- License decision: 외부 코드나 Skill 문구를 반입하지 않고 아키텍처 view, 증거 계층, repository map, 인간 검토, 정적·런타임 대조 개념만 참고함. RepoAgent 등 MIT가 아닌 구현은 반입 대상으로 사용하지 않음
- Scope: `skills/reverse-engineer-service/`의 목적 중심 인터뷰, intended/implemented/observed 구분, bounded graph 탐색, C4 구조와 런타임 시나리오, evidence ledger 설계
- Included material: 원본 코드·프롬프트·도표·실질적 문구를 복사하지 않고 이 저장소의 요구사항에 맞춰 독자적으로 작성

### 정적 분석 도구와 언어 API

- Sources:
  - https://www.typescriptlang.org/docs/handbook/modules/reference
  - https://github.com/sverweij/dependency-cruiser
  - https://github.com/ast-grep/ast-grep
  - https://docs.python.org/3/library/ast.html
  - https://jedi.readthedocs.io/en/stable/docs/features.html
- Checked: 2026-08-06
- License decision: 공개 API와 도구 capability를 확인하는 용도로만 참고하고 외부 구현 코드는 복사하지 않음. TypeScript Compiler API와 Python 표준 AST는 대상 저장소를 실행하지 않는 분석 backend로 호출함
- Scope: JS/TS module resolution·symbol·call 후보, Python AST 기반 import·symbol·decorator·call 추출, 선택 도구의 존재 여부와 버전 기록
- Included material: 저장소의 분석기와 JSON 계약은 독자적으로 작성했으며 dependency-cruiser, ast-grep, Jedi를 vendoring하거나 필수 의존성으로 추가하지 않음

### epoko77-ai, `im-not-ai`

- Source: https://github.com/epoko77-ai/im-not-ai/tree/82137e858763dadb99561f194c5c00465735017b
- Revision: `82137e858763dadb99561f194c5c00465735017b` (`v2.3.0`)
- Checked: 2026-08-06
- Author/Copyright: `Copyright (c) 2026 epoko77-ai`
- License decision: MIT 라이선스(https://github.com/epoko77-ai/im-not-ai/blob/82137e858763dadb99561f194c5c00465735017b/LICENSE)를 확인했으며 외부 코드나 실질적 문구의 반입 대상으로 사용하지 않음
- Scope: 의미 보존, 장르·격식 유지, 국소 편집, 번역투·AI 상투어 완화, 과윤문 방지와 추상 주어·긴 관형 수식·명사화·국소 자연성 재검수 개념(A-15, A-18, D-5, F-4/F-5, finalizer)을 `skills/polish-korean/` 설계에 아이디어 수준으로 참고
- Included material: 원본 실행 파이프라인, 규칙 문구와 보조 자료를 복사하지 않고 단일 프롬프트형 범용 윤문 절차를 독자적으로 작성

### Skill 설치 경로, 플랫폼 도구, Git 작업과 릴리스 버전

- Sources:
  - https://learn.chatgpt.com/docs/build-skills
  - https://code.claude.com/docs/en/slash-commands
  - https://code.claude.com/docs/en/plugin-marketplaces
  - https://semver.org/
  - https://git-scm.com/docs/git-tag
  - https://git-scm.com/docs/git-worktree
  - https://git-scm.com/docs/git-merge
  - https://git-scm.com/docs/git-hash-object
  - https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
  - https://docs.docker.com/engine/storage/bind-mounts/
  - https://hub.docker.com/_/node
- Checked: 2026-08-06
- License decision: 공식 문서를 설치 위치·POSIX 셸 동작·컨테이너 격리·Git 동작·배포 방식·버전 규칙 확인에만 사용하고 외부 코드나 실질적 문구의 반입 대상으로 사용하지 않음
- Scope: Codex와 Claude Code의 사용자·프로젝트 Skill 위치, standalone Skill과 plugin marketplace의 경계, POSIX `sh` 이식성, Git 기반 파일 지문, 읽기 전용 Linux 검증 컨테이너, linked worktree, fast-forward-only 통합, Skill 내부 revision과 annotated 배포 태그 운영을 아이디어 수준에서 참고
- Included material: 원문의 예시와 실질적 문구를 복사하지 않고 이 저장소의 공용 설치 스크립트와 공개 정책에 맞춰 독자적으로 작성

### 커밋 메시지 구조와 trailer

- Sources:
  - https://www.conventionalcommits.org/en/v1.0.0/
  - https://git-scm.com/docs/git-interpret-trailers
- Checked: 2026-08-06
- License decision: 공식 규격을 동작과 인터페이스 확인에만 사용하고 외부 코드·Skill 문구의 반입 대상으로 사용하지 않음
- Scope: 확장 가능한 `<type>[(scope)]: <summary>` 구조와 메시지 마지막의 기계 판독 가능한 trailer 배치를 아이디어 수준에서 참고
- Included material: 원문의 예시와 실질적 문구를 복사하지 않고 이 저장소의 다분야 작업 및 Agent 표기 요구에 맞춰 독자적으로 작성

### AX LABS, 「600억 토큰을 태우고 남은 8줄」

- Source: https://theaxlabs.com/blog/context-file-eight-lines-prompt-guide
- Checked: 2026-08-06
- Author/Copyright: AX LABS 웹페이지 고지 기준
- License decision: 페이지에서 MIT 라이선스를 확인하지 못했으므로 코드·문구 반입 대상으로 사용하지 않음
- Scope: Agent 상시 지침의 밀도를 높이고 단계별 상세 문서를 인덱싱하는 정보 구조를 아이디어 수준에서 참고
- Included material: 원문의 코드와 실질적 문구를 포함하지 않고 이 저장소의 요구사항에 맞춰 독자적으로 작성

### README 정보 구조 벤치마크

- Sources:
  - https://github.com/wshobson/agents at `c4b82b0ad771190355eb8e204b1329732a18449a` ([MIT](https://github.com/wshobson/agents/blob/c4b82b0ad771190355eb8e204b1329732a18449a/LICENSE))
  - https://github.com/Jeffallan/claude-skills at `e8be415bc94d8d6ebddc2fb50e5d03c6e27d4319` ([MIT](https://github.com/Jeffallan/claude-skills/blob/e8be415bc94d8d6ebddc2fb50e5d03c6e27d4319/LICENSE))
  - https://github.com/VoltAgent/awesome-agent-skills at `5241ad954d2880330d9f3a7df086f8d943c4c988` ([MIT](https://github.com/VoltAgent/awesome-agent-skills/blob/5241ad954d2880330d9f3a7df086f8d943c4c988/LICENSE))
- Checked: 2026-08-06
- Scope: 빠른 시작, 작업 흐름, 문서 지도, 보안·라이선스 안내의 배치 방식을 아이디어 수준에서 비교
- Included material: 원본 README의 문구와 코드를 복사하지 않고 이 저장소의 실제 명령과 정책을 기준으로 독자적으로 작성
