# 문서 계약

## 공통 규칙

- 기본 경로는 `docs/reverse-engineering/`이다.
- 모든 새 문서는 `status: draft`로 시작한다.
- 명시적인 인간 검토 전에는 `reviewed`를 사용하지 않는다.
- claim은 `RE-001` 형식의 안정적인 ID를 사용한다.
- 각 claim에 truth layer(`intended`, `implemented`, `observed`)와 상태(`확인`, `추론`, `미확인`)를 붙인다.
- 파일 증거는 저장소 상대 경로와 줄 또는 symbol을 사용한다.
- Mermaid는 `flowchart`, `sequenceDiagram`, `stateDiagram-v2`만 사용한다.
- 미확인 노드와 후보 edge는 점선이나 라벨로 구분하고 범례를 둔다.

## 권장 문서 흐름

문서 사이의 편차를 줄이기 위해 다음 흐름을 기본값으로 사용한다.

1. 핵심 결론
2. 맥락과 분석 범위
3. 구조와 책임
4. 대표 시나리오와 상태 변화
5. 증거, 드리프트, 불확실성
6. 코드 읽기 순서와 다음 질문

이는 강제 템플릿이 아니다. 질문과 증거에 맞지 않는 절은 합치거나 생략하고, 특정 기능 분석에서는 구조보다 시나리오를 더 상세히 다룰 수 있다. 다만 제목과 상태·snapshot 다음의 첫 설명 절에는 `핵심 결론`을 둔다. 3~7개의 짧은 문장이나 bullet로 질문에 대한 답, 가장 중요한 구조적 특징, 주요 불확실성을 요약하고 세부 근거를 새로 도입하지 않는다.

## `overview.md`

다음 순서를 사용한다.

1. 상태와 분석 snapshot
2. 핵심 결론
3. 질문과 범위
4. 서비스 가치, actor, 도메인 용어
5. Context/Container 구조도와 필요한 Component 상세
6. API, 데이터 저장소, 메시지, 외부 리소스, 소유권
7. intended/implemented/observed 대조표
8. 대표 시나리오 링크
9. 권장 코드 읽기 순서
10. 제외 범위와 다음 질문

snapshot에는 commit, dirty 여부, 실행 환경, 분석 명령, 도구와 capability를 기록한다. 원시 JSON이나 소스 리터럴을 붙이지 않는다.

## `scenarios/<slug>.md`

다음을 포함한다.

- 핵심 결론: 사용자 관점의 결과, 실제 구현 경로, 가장 중요한 실패·미확인 지점
- 사용자 가치와 actor
- entrypoint와 분석 재현 명령
- 성공 경로의 `sequenceDiagram`
- 필요할 때 상태 전이의 `stateDiagram-v2`
- 단계별 code/API/schema/IaC/runtime claim
- 인증과 신뢰 경계
- transaction, retry, timeout, idempotency
- 비동기 분기와 관측성
- unresolved frontier와 추가 증거

정적 `calls` edge가 `candidate`, `syntactic`, `dynamic`이면 다이어그램에도 그 상태를 표시한다.

## `evidence.md`

claim 표는 다음 열을 사용한다.

표 앞에는 확인된 범위, 가장 큰 증거 공백, 주요 충돌을 3~5개 항목의 `핵심 결론`으로 요약한다.

| Claim | 상태 | 계층 | 주장 | 출처 | Revision/환경 |
| --- | --- | --- | --- | --- | --- |

그 아래에 다음을 기록한다.

- 실행 명령과 도구 버전
- 분석 capability와 fallback
- 포함·제외 범위
- 충돌과 stale 가능성
- 확보하지 못한 런타임 증거

## 보수적 병합

기존 문서가 있으면 전체를 재생성하지 않는다.

1. 기존 인간 서술과 reviewed 표시를 보존한다.
2. 같은 claim ID의 근거가 바뀌면 새 revision과 함께 변경을 제안한다.
3. 기존 주장과 충돌하면 한쪽을 삭제하지 말고 드리프트 표에 추가한다.
4. 자동 생성 블록이 명시되어 있을 때만 그 블록 내부를 교체한다.
5. 구조가 불명확하면 새 `draft` 절을 추가하고 병합 결정을 사용자에게 남긴다.
