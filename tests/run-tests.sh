#!/bin/sh
set -eu

fail() {
  printf '테스트 실패: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  expected=$1
  actual=$2
  message=$3
  [ "$expected" = "$actual" ] || fail "$message (expected=$expected, actual=$actual)"
}

assert_file() {
  [ -f "$1" ] || fail "$2"
}

expect_code() {
  expected=$1
  shift
  set +e
  "$@"
  actual=$?
  set -e
  assert_equal "$expected" "$actual" "예상하지 못한 종료 코드: $*"
}

case "$0" in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
test_dir=$(CDPATH='' cd -- "$test_dir" && pwd -P)
repository_root=$(CDPATH='' cd -- "$test_dir/.." && pwd -P)
temp_base=${TMPDIR:-/tmp}
temporary_root=$(mktemp -d "$temp_base/skill-goblin-tests.XXXXXX") || exit 1
worktree_root=$temporary_root-worktrees
remote_root=$temporary_root-remote.git
cleanup() {
  case $temporary_root in "$temp_base"/skill-goblin-tests.*) rm -rf "$temporary_root" "$worktree_root" "$remote_root" ;; esac
}
trap cleanup 0 HUP INT TERM

for path in "$repository_root"/scripts/*.sh "$repository_root"/.githooks/* "$repository_root"/skills/reverse-engineer-service/scripts/analyze-code.sh; do
  [ "${path##*/}" = _common.sh ] && continue
  [ -x "$path" ] || fail "실행 권한이 없습니다: $path"
done
sh -n "$repository_root"/scripts/*.sh "$repository_root"/.githooks/* "$repository_root"/skills/reverse-engineer-service/scripts/analyze-code.sh

cp -R "$repository_root/scripts" "$temporary_root/scripts"
cp -R "$repository_root/templates" "$temporary_root/templates"
cp -R "$repository_root/.githooks" "$temporary_root/.githooks"
cp "$repository_root/VERSION" "$temporary_root/VERSION"
mkdir "$temporary_root/skills"

cd "$temporary_root"
git init --initial-branch=main >/dev/null
global_name_before=$(git config --global --get user.name || true)
global_email_before=$(git config --global --get user.email || true)
./scripts/setup.sh
assert_equal Innnteraction "$(git config --local --get user.name)" '로컬 Git 이름 설정 실패'
assert_equal innnteractive@gmail.com "$(git config --local --get user.email)" '로컬 Git 이메일 설정 실패'
assert_equal .githooks "$(git config --local --get core.hooksPath)" 'hook 경로 설정 실패'
assert_equal only "$(git config --local --get merge.ff)" 'fast-forward merge 설정 실패'
assert_equal only "$(git config --local --get pull.ff)" 'fast-forward pull 설정 실패'
assert_equal nothing "$(git config --local --get push.default)" '명시 push 설정 실패'
assert_equal "$global_name_before" "$(git config --global --get user.name || true)" '전역 Git 이름이 변경됨'
assert_equal "$global_email_before" "$(git config --global --get user.email || true)" '전역 Git 이메일이 변경됨'

./scripts/new-skill.sh --name sample-skill --description '한국어 설명을 처리한다. 샘플 작업을 요청할 때 사용한다.' --with-scripts --with-references
assert_file skills/sample-skill/SKILL.md 'Skill 생성 실패'
assert_equal 1 "$(sed -n '1p' skills/sample-skill/VERSION)" 'Skill 초기 VERSION 생성 실패'
./scripts/validate-skills.sh
expect_code 1 ./scripts/new-skill.sh --name Bad_Name --description invalid
expect_code 1 ./scripts/new-skill.sh --name "$(printf '%065d' 0 | tr 0 a)" --description invalid
expect_code 2 ./scripts/new-skill.sh --name

mkdir skills/missing-version
printf '%s\n' '---' 'name: missing-version' "description: 'VERSION 검증용 Skill이다.'" '---' > skills/missing-version/SKILL.md
expect_code 1 ./scripts/validate-skills.sh --name missing-version --skip-sensitive-check
rm -rf skills/missing-version
for version_case in zero:0 negative:-1 dotted:1.0; do
  case_name=${version_case%%:*}-version
  value=${version_case#*:}
  mkdir "skills/$case_name"
  printf '%s\n' '---' "name: $case_name" "description: 'VERSION 검증용 Skill이다.'" '---' > "skills/$case_name/SKILL.md"
  printf '%s\n' "$value" > "skills/$case_name/VERSION"
  expect_code 1 ./scripts/validate-skills.sh --name "$case_name" --skip-sensitive-check
  rm -rf "skills/$case_name"
done
valid_repository_version=$(sed -n '1p' VERSION)
printf '%s\n' 01.2.3 > VERSION
expect_code 1 ./scripts/validate-skills.sh --skip-sensitive-check
printf '0.1.0\n0.2.0' > VERSION
expect_code 1 ./scripts/validate-skills.sh --skip-sensitive-check
printf '%s\n' "$valid_repository_version" > VERSION

test_home=$temporary_root/user-home
claude_home=$temporary_root/claude-home
HOME=$test_home CLAUDE_HOME=$claude_home ./scripts/install-skills.sh --target all --name sample-skill
codex_copy=$test_home/.agents/skills/sample-skill/SKILL.md
claude_copy=$claude_home/skills/sample-skill/SKILL.md
assert_file "$codex_copy" 'Codex 사용자 설치 실패'
assert_file "$claude_copy" 'Claude 사용자 설치 실패'
assert_equal 1 "$(sed -n '1p' "$test_home/.agents/skills/sample-skill/VERSION")" '설치본 VERSION 누락'
HOME=$test_home CLAUDE_HOME=$claude_home ./scripts/install-skills.sh --target all --name sample-skill
printf '%s\n' '충돌' >> "$codex_copy"
expect_code 1 env HOME="$test_home" CLAUDE_HOME="$claude_home" ./scripts/install-skills.sh --target codex --name sample-skill
HOME=$test_home CLAUDE_HOME=$claude_home ./scripts/install-skills.sh --target codex --name sample-skill --force
grep -q 충돌 "$codex_copy" && fail '강제 재설치가 충돌 내용을 제거하지 못함'

project_root=$temporary_root/target-project
mkdir "$project_root"
./scripts/install-skills.sh --target all --scope project --project-path "$project_root" --name sample-skill
assert_file "$project_root/.agents/skills/sample-skill/SKILL.md" 'Codex 프로젝트 설치 실패'
assert_file "$project_root/.claude/skills/sample-skill/SKILL.md" 'Claude 프로젝트 설치 실패'
expect_code 1 ./scripts/install-skills.sh --scope project --name sample-skill
expect_code 1 ./scripts/install-skills.sh --scope project --project-path "$temporary_root/missing" --name sample-skill
expect_code 1 ./scripts/install-skills.sh --scope user --project-path "$project_root" --name sample-skill
expect_code 2 ./scripts/install-skills.sh --target unknown

git add .
git commit -m '안전한 테스트 커밋' >/dev/null
safe_commit=$(git rev-parse HEAD)
./scripts/check-sensitive.sh --range "$safe_commit^!" --skip-gitleaks

fake_token=$(printf 'ghp_%030d' 0)
printf 'token=%s\n' "$fake_token" > unsafe.txt
git add unsafe.txt
expect_code 1 ./scripts/check-sensitive.sh --staged --skip-gitleaks
git reset -- unsafe.txt >/dev/null
rm unsafe.txt
printf '%s\n' 'EXAMPLE_TOKEN=placeholder' > .env
git add -f .env
expect_code 1 ./scripts/check-sensitive.sh -Staged -SkipGitleaks
git reset -- .env >/dev/null
rm .env

mock_bin=$temporary_root/mock-bin
mkdir "$mock_bin"
printf '%s\n' '#!/bin/sh' 'exit 9' > "$mock_bin/gitleaks"
chmod +x "$mock_bin/gitleaks"
expect_code 1 env PATH="$mock_bin:$PATH" ./scripts/check-sensitive.sh --staged

git init --bare --initial-branch=main "$remote_root" >/dev/null
git remote add origin "$remote_root"
git push --no-verify -u origin main >/dev/null
mkdir "$worktree_root"
git worktree add -b feat/task-a "$worktree_root/task-a" main >/dev/null
git worktree add -b feat/task-b "$worktree_root/task-b" main >/dev/null
printf '%s\n' task-a > "$worktree_root/task-a/task-a.txt"
git -C "$worktree_root/task-a" add task-a.txt
git -C "$worktree_root/task-a" commit -m 'feat: 첫 worktree 변경' >/dev/null
printf '%s\n' task-b > "$worktree_root/task-b/task-b.txt"
git -C "$worktree_root/task-b" add task-b.txt
git -C "$worktree_root/task-b" commit -m 'feat: 두 번째 worktree 변경' >/dev/null
git merge --ff-only feat/task-a >/dev/null
git -C "$worktree_root/task-b" rebase main >/dev/null
git merge --ff-only feat/task-b >/dev/null
git push --no-verify origin main >/dev/null
remote_heads=$(git ls-remote --heads origin | wc -l | tr -d ' ')
assert_equal 1 "$remote_heads" '원격에 main 외 작업 브랜치가 push됨'
[ -z "$(git -C "$worktree_root/task-a" status --porcelain)" ] || fail '첫 worktree가 clean하지 않음'
[ -z "$(git -C "$worktree_root/task-b" status --porcelain)" ] || fail '두 번째 worktree가 clean하지 않음'
git worktree remove "$worktree_root/task-a"
git worktree remove "$worktree_root/task-b"
git branch -d feat/task-a feat/task-b >/dev/null

analyzer=$repository_root/skills/reverse-engineer-service/scripts/analyze-code.sh
fixture_root=$repository_root/tests/fixtures/reverse-engineer-service
facts_root=$temporary_root/facts
mkdir "$facts_root"
"$analyzer" discover --root "$fixture_root/python" --output "$facts_root/python-1.json"
"$analyzer" discover --root "$fixture_root/python" --output "$facts_root/python-2.json"
cmp "$facts_root/python-1.json" "$facts_root/python-2.json" || fail 'Python discover 결과가 결정적이지 않음'
"$analyzer" trace --root "$fixture_root/python" --entry src/sample/api.py#post_order --max-depth 4 --max-nodes 40 --output "$facts_root/python-trace.json"
expect_code 2 "$analyzer" trace --root "$fixture_root/python" --entry missing.py --output "$facts_root/missing.json"
expect_code 4 "$analyzer" discover --root "$fixture_root/python-invalid" --output "$facts_root/invalid.json"
"$analyzer" discover --root "$fixture_root/typescript" --output "$facts_root/js.json"
expect_code 3 "$analyzer" trace --root "$fixture_root/typescript" --entry src/server.ts#postOrder --output "$facts_root/js-trace.json"

mixed_root=$temporary_root/mixed-fixture
cp -R "$fixture_root/python" "$mixed_root"
cp "$fixture_root/typescript/package.json" "$mixed_root/package.json"
cp -R "$fixture_root/typescript/src/." "$mixed_root/src/"
"$analyzer" discover --root "$mixed_root" --output "$facts_root/mixed.json"
python3 - "$facts_root/python-1.json" "$facts_root/python-trace.json" "$facts_root/js.json" "$facts_root/mixed.json" <<'PY'
import json
import re
import sys

required = {"snapshot", "tools", "capabilities", "entrypoints", "modules", "symbols", "edges", "read_set", "diagnostics"}
documents = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:]]
assert len(documents[0]["entrypoints"]) >= 3
assert len(documents[1]["read_set"]) >= 1
assert "manifest-only" in documents[2]["capabilities"]
assert any(item.endswith("python-ast") for item in documents[3]["capabilities"])
assert "manifest-only" in documents[3]["capabilities"]
for document in documents:
    assert required <= document.keys()
    assert re.fullmatch(r"[a-f0-9]{64}", document["snapshot"]["source_digest"])
PY

cd "$repository_root"
./scripts/validate-skills.sh
./scripts/check-sensitive.sh --all --skip-gitleaks
git diff --check
printf '%s\n' '[ok] macOS·Linux Unix 회귀 테스트를 통과했습니다.'
