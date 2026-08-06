---
name: reverse-engineer-service
description: '코드, 설정, IaC, 테스트, 문서와 런타임 증거를 대조해 처음 접하는 서비스의 아키텍처와 대표 시나리오를 재구성한다. 서비스 온보딩, 특정 기능 추적, 엔트리포인트 탐색, 시스템 구조·데이터 흐름·비동기 경로·아키텍처 드리프트 분석을 요청할 때 사용한다.'
---

# Reverse Engineer Service

전체 파일을 차례로 읽지 말고, 결정적 분석 결과로 읽을 범위를 좁힌 뒤 코드와 런타임 증거를 대조한다. 현재 상태의 이해에 집중하고 목표 아키텍처나 개선안은 사용자가 별도로 요청할 때만 다룬다.

## 시작

1. 사용자의 학습 목적, 알고 싶은 기능이나 시나리오, 사용할 수 있는 코드·문서·IaC·테스트·서비스·로그·트레이스를 확인한다.
2. 질문이 탐색적이어도 서비스 가치, 주요 actor, 도메인 용어에서 해당 기능으로 내려가는 흐름을 제시한다.
3. 분석 대상 root와 revision, dirty 상태, 환경, 접근 제한을 기록한다. 비밀값이나 실제 업무 데이터는 출력하지 않는다.
4. 세부 탐색 방법이 필요하면 [탐색 플레이북](references/exploration-playbook.md)을 읽는다. 문서를 만들거나 갱신하기 전에는 [문서 계약](references/document-contract.md)을 읽는다.

## 증거 모델

주장마다 진실 계층과 상태를 함께 기록한다.

- `intended`: README, ADR, 카탈로그, 인터뷰가 말하는 의도
- `implemented`: 코드, 설정, IaC, 테스트, CI가 구현한 상태
- `observed`: 로그, 메트릭, 트레이스, 실행 중 서비스에서 관찰한 상태
- `확인`: 직접 증거가 주장을 지지함
- `추론`: 여러 증거를 연결한 해석이며 반증 가능함
- `미확인`: 필요한 증거가 없거나 상충함

정적 호출 후보를 런타임 사실로 승격하지 않는다. 문서와 구현, 구현과 관찰이 다르면 드리프트로 명시한다.

## 코드 탐색

1. 임시 디렉터리를 만들고 Windows에서는 `scripts/analyze-code.ps1 discover --root <repo> --output <temp>/facts.json`, macOS·Linux에서는 `scripts/analyze-code.sh discover --root <repo> --output <temp>/facts.json`을 실행한다.
2. 후보가 여러 개면 질문, manifest 근거, 대표 가치 흐름을 기준으로 사용자와 엔트리포인트를 정한다. 임의로 고르지 않는다.
3. `trace --entry <file[#symbol]|file:line>`을 실행한다. 큰 그래프는 `--max-depth`와 `--max-nodes`로 제한한다.
4. `read_set`의 파일과 줄 범위, 미해결 frontier만 우선 읽는다. `candidate`, `syntactic`, `dynamic` edge는 코드에서 확인하고도 불명확하면 그대로 남긴다.
5. TypeScript Compiler API가 없고 대상 저장소에 dependency-cruiser가 있으면 module-only trace를 사용한다. symbol/call 관계가 없음을 명시하고 필요한 파일은 Agent가 확인한다. 분석기가 capability 부족을 종료 코드 `3`으로 보고하면 도구를 자동 설치하지 않는다. 설치된 semantic index나 사용자가 허용한 도구가 있는지 확인하고, 없으면 가능한 범위와 제외 범위를 문서화한다.
6. 대상 모듈을 import하거나 build/install script를 실행하지 않는다. 분석 산출물에 리터럴·환경변수 값·SQL 본문을 복사하지 않는다.

## 대조와 재구성

1. 서비스 가치와 actor를 루트로 Context와 Container 수준의 지도를 만든다. 질문에 필요할 때만 Component 수준으로 내려간다.
2. 대표 성공 경로 하나와 핵심 실패 또는 비동기 경로 하나를 기본 깊이로 추적한다.
3. API 계약, 데이터 스키마, 테스트, IaC, 배포 설정을 코드 경로와 대조한다.
4. 로그·메트릭·트레이스가 있으면 환경, 시간 범위, sampling을 함께 기록하고 정적 그래프와 비교한다.
5. 설명되지 않는 제약이나 모순에 한해 `git log`, `git blame`, 관련 변경 이력을 좁혀 조사한다.
6. 미확인 경계와 다음에 읽을 코드·확보할 증거를 학습 경로로 남긴다.

## 산출물

대상 저장소의 `docs/reverse-engineering/` 아래를 기본 위치로 사용한다.

- `overview.md`: 가치, actor, 용어, 구조, API·데이터·리소스·소유권, 드리프트, 코드 읽기 순서
- `scenarios/<slug>.md`: 엔트리포인트, 재현 명령, 성공·실패·비동기 흐름, 상태와 신뢰 경계
- `evidence.md`: claim ID, 진실 계층, 상태, 출처, revision, 환경, coverage와 충돌

기존 문서는 보수적으로 병합한다. 인간이 작성한 서술을 덮어쓰지 말고 새 증거와 충돌을 별도 항목으로 추가한다. 최초 결과는 `draft`로 두고 명시적인 인간 검토가 있어야 `reviewed`로 바꾼다. Mermaid는 `flowchart`, `sequenceDiagram`, `stateDiagram-v2`만 사용한다.

각 문서는 제목과 짧은 상태 정보 다음에 `핵심 결론`을 먼저 두고, 독자가 세부 근거를 읽기 전에 질문의 답, 구조적 특징, 중요한 불확실성을 파악하게 한다. 이후에는 맥락과 범위에서 구조·시나리오·증거·다음 학습 경로로 이어지는 [권장 흐름](references/document-contract.md)을 따른다. 내용에 맞지 않는 절은 합치거나 생략할 수 있으나 결론을 뒤로 미루지 않는다.

문서에는 분석 명령, 도구 버전, commit, capability를 남긴다. 원시 JSON은 임시 위치에만 두고 작업이 끝나면 자신이 만든 정확한 임시 경로만 제거한다.

## 완료 확인

- 구조와 시나리오의 주요 주장이 증거와 revision에 연결되었는지 확인한다.
- intended, implemented, observed의 충돌을 숨기지 않았는지 확인한다.
- 동적 경계와 분석 제외 범위를 사실처럼 표현하지 않았는지 확인한다.
- 사용자가 다음에 읽을 코드와 확인할 질문을 알 수 있는지 확인한다.
- 개선안이나 신규 아키텍처를 현재 구조 설명에 섞지 않았는지 확인한다.
