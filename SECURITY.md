# 공개 저장소 보안 정책

## 반입 금지 정보

- API key, access token, session cookie, 비밀번호, 개인키, 인증서 원본
- 회사 소스 코드, 설계 문서, 계약서, 재무 자료, 내부 URL과 시스템 식별자
- 고객·직원·지인의 개인정보와 실제 업무 데이터
- 개인 또는 회사 계정의 로컬 설정, 대화 기록, prompt 원문, 로그와 dump

예제에는 실제 값을 변형해 사용하지 말고 `EXAMPLE_TOKEN`, `example.invalid`, `00000000`처럼 명백한 placeholder를 새로 만든다.

## 커밋 전 확인

1. staged 파일 목록과 diff를 직접 읽는다.
2. `scripts/check-sensitive.ps1 -Staged`를 실행한다.
3. 외부 자료의 라이선스와 provenance 기록을 확인한다.
4. 공개된 GitHub에서 누구나 읽어도 되는 내용인지 다시 판단한다.

자동 검사는 의미상 기밀이나 개인정보를 완전히 식별하지 못한다. 탐지 결과가 없다는 이유만으로 공개 가능하다고 판단하지 않는다.

## 유출이 의심될 때

1. push를 즉시 중단한다.
2. 실제 credential이면 먼저 폐기하거나 교체한다.
3. 최신 commit만 포함하면 amend하고, 과거 commit에도 있으면 안전한 history rewrite 절차를 별도로 검토한다.
4. 이미 push했다면 새 commit에서 삭제하는 것만으로 충분하지 않다. 원격 기록 정리와 관련 사용자 통지를 진행한다.
5. 정리 과정에서 secret 값을 이슈, 로그, 채팅에 다시 붙여 넣지 않는다.
