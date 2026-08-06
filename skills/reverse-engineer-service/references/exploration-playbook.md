# 탐색 플레이북

## 1. 범위 고정

분석 전에 다음을 짧게 고정한다.

- 학습 목적: 전체 온보딩, 특정 기능, 장애 경로, 데이터 흐름 중 무엇인가
- 대표 actor와 기대 가치
- 코드 root와 포함할 workspace
- 사용할 수 있는 intended, implemented, observed 증거
- 제외할 저장소, 환경, 데이터

질문이 넓으면 시스템 지도, 대표 성공 경로 하나, 핵심 실패 또는 비동기 경로 하나를 기본 범위로 삼는다.

## 2. 증거 우선순위

같은 주장에 여러 증거가 있으면 revision이 고정된 직접 증거를 우선한다. 각 계층은 서로 대체하지 않는다.

| 계층 | 주로 볼 자료 | 주의점 |
| --- | --- | --- |
| intended | README, ADR, Backstage catalog, 운영 문서, 인터뷰 | 오래되었거나 희망 상태일 수 있음 |
| implemented | manifest, code, config, schema, tests, IaC, CI | 동적 구성과 외부 시스템을 놓칠 수 있음 |
| observed | trace, metric, log, 서비스 응답 | 환경·시간·sampling에 종속됨 |

비밀값은 읽거나 옮기지 않는다. 설정에서는 key 이름과 구조만 기록한다. 로그는 식별자와 payload를 문서에 복사하지 않고 패턴과 위치만 남긴다.

## 3. 엔트리포인트 찾기

먼저 `discover` 결과를 보고 다음 순서로 좁힌다.

1. manifest의 `main`, `exports`, `bin`, scripts 또는 Python script entry
2. HTTP/ASGI/WSGI application과 router 등록
3. queue consumer, scheduler, worker, serverless handler
4. CLI main과 `__main__`
5. 테스트가 호출하는 public API

후보가 여러 개면 질문과 연결되는 외부 계약을 선택한다. 근거가 같으면 후보를 모두 보고하고 사용자 선택을 받는다.

## 4. 대형·멀티 저장소

- workspace와 deployable 경계를 먼저 식별한다.
- 생성물, vendor, cache, virtual environment, `node_modules`는 분석에서 제외한다.
- 한 번에 한 entry와 bounded trace를 사용한다.
- 제한에 걸리면 frontier에서 다음 trace를 시작하고 이전 결과와 claim ID로 연결한다.
- 기존 Sourcegraph, SCIP, CodeQL, Semgrep 결과가 있으면 provenance와 revision을 확인한 뒤 보조 증거로 쓴다.

## 5. 언어별 해석

### JavaScript와 TypeScript

TypeScript Compiler API가 있으면 tsconfig와 path alias를 적용한 semantic 결과를 우선한다. interface dispatch, factory, computed property, dynamic import는 완전한 런타임 대상이라고 단정하지 않는다. Compiler API가 없고 대상 저장소에 dependency-cruiser가 있으면 module-only trace를 사용하고 symbol/call 관계가 없음을 기록한다. 둘 다 없으면 `discover`만 수행하며 `trace` 결과를 추정으로 대체하지 않는다. ast-grep은 설치 여부와 버전을 보조 capability로만 기록하고 의미 기반 호출 그래프를 대신하게 하지 않는다.

### Python

표준 AST 분석은 대상 모듈을 import하지 않는다. 상대 import와 직접 alias는 해석하되 객체 메서드, monkey patching, dependency injection, metaclass, 동적 import는 후보로 남긴다. Jedi가 있으면 보조 capability로 기록하되 결과의 revision과 버전을 남긴다.

Java, native extension, 생성 코드, macro, 런타임 code generation은 v1 범위 밖이다.

## 6. 런타임 대조

- trace에서 실제 service/span 순서와 critical path를 확인한다.
- metric은 빈도·지연·오류율을 설명할 뿐 단일 요청 순서를 증명하지 않는다.
- log correlation은 동일 환경과 correlation ID 정책을 확인한다.
- sampling, trace loss, 비동기 context 전파 누락을 제한 사항에 적는다.
- 운영 서비스에 변경이나 부하를 주는 요청은 명시적 허가 없이 실행하지 않는다.

## 7. Git 이력

현재 코드만으로 설명되지 않는 경계에만 이력을 사용한다.

- `git log -- <path>`로 관련 변경을 좁힌다.
- `git blame`은 설계 의도 증거가 아니라 관련 commit을 찾는 색인으로 쓴다.
- PR이나 issue의 설명은 intended 계층으로 기록하고 현재 구현과 다시 대조한다.

## 8. 블랙박스와 불완전한 증거

코드가 없으면 공개 계약, 네트워크 경계, 관측 신호만으로 Context와 시나리오를 작성한다. 내부 컴포넌트를 상상해 채우지 않는다. 서로 충돌하는 증거는 한쪽을 제거하지 말고 각각의 revision·환경과 함께 기록한다.
