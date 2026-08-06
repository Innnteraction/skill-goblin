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

### Skill 설치 경로와 릴리스 버전

- Sources:
  - https://learn.chatgpt.com/docs/build-skills
  - https://code.claude.com/docs/en/slash-commands
  - https://code.claude.com/docs/en/plugin-marketplaces
  - https://semver.org/
  - https://git-scm.com/docs/git-tag
- Checked: 2026-08-06
- License decision: 공식 문서를 설치 위치·배포 방식·버전 규칙 확인에만 사용하고 외부 코드나 실질적 문구의 반입 대상으로 사용하지 않음
- Scope: Codex와 Claude Code의 사용자·프로젝트 Skill 위치, standalone Skill과 plugin marketplace의 경계, 초기 `0.y.z` 버전과 annotated 태그 운영을 아이디어 수준에서 참고
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
