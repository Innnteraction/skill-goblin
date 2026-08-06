#!/bin/sh
set -eu

name=
skip_sensitive=false
while [ "$#" -gt 0 ]; do
  case $1 in
    --name|-Name) option=$1; value=${2-}; [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }; name=$value; shift 2 ;;
    --skip-sensitive-check|-SkipSensitiveCheck) skip_sensitive=true; shift ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P)
# shellcheck source=scripts/_common.sh
. "$script_dir/_common.sh"
root=$(repository_root) || exit 1
errors=0

report_error() {
  printf '%s\n' "$1" >&2
  errors=1
}

repository_version_path=$root/VERSION
if [ ! -f "$repository_version_path" ]; then
  report_error '루트 VERSION 파일이 없습니다.'
else
  repository_version=$(cat "$repository_version_path")
  if ! printf '%s\n' "$repository_version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || [ "$(printf '%s\n' "$repository_version" | wc -l | tr -d ' ')" -ne 1 ]; then
    report_error '루트 VERSION은 X.Y.Z 형식이어야 합니다.'
  fi
fi

directories_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-validate.XXXXXX") || exit 1
references_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-references.XXXXXX") || { rm -f "$directories_file"; exit 1; }
trap 'rm -f "$directories_file" "$references_file"' 0 HUP INT TERM
skill_directories "$root" "$name" > "$directories_file" || exit 1
skill_count=0

while IFS= read -r directory; do
  skill_count=$((skill_count + 1))
  skill_name=${directory##*/}
  skill_errors=0
  version_path=$directory/VERSION
  skill_path=$directory/SKILL.md

  if [ ! -f "$version_path" ]; then
    printf '%s: VERSION 파일이 없습니다.\n' "$skill_name" >&2
    skill_errors=1
  else
    skill_version=$(cat "$version_path")
    if ! printf '%s\n' "$skill_version" | grep -Eq '^[1-9][0-9]*$' || [ "$(printf '%s\n' "$skill_version" | wc -l | tr -d ' ')" -ne 1 ]; then
      printf '%s: VERSION은 점 없는 양의 정수여야 합니다.\n' "$skill_name" >&2
      skill_errors=1
    fi
  fi

  if [ ! -f "$skill_path" ]; then
    printf '%s: SKILL.md가 없습니다.\n' "$skill_name" >&2
    errors=1
    continue
  fi
  if ! is_skill_name "$skill_name"; then
    printf '%s: 디렉터리 이름이 kebab-case 규칙에 맞지 않습니다.\n' "$skill_name" >&2
    skill_errors=1
  fi
  lines=$(awk 'END { print NR }' "$skill_path")
  if [ "$lines" -gt 500 ]; then
    printf '%s: SKILL.md가 500줄을 넘습니다 (%s줄).\n' "$skill_name" "$lines" >&2
    skill_errors=1
  fi

  if ! awk -v expected="$skill_name" -v prefix="$skill_name" '
function error(message) { print prefix ": " message > "/dev/stderr"; failed=1 }
function unquote(value) {
  sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value)
  if (value ~ /^\047.*\047$/) { value=substr(value,2,length(value)-2); gsub(/\047\047/,"\047",value) }
  else if (value ~ /^".*"$/) { value=substr(value,2,length(value)-2) }
  return value
}
NR==1 {
  if ($0 !~ /^[[:space:]]*---[[:space:]]*$/) { error("YAML frontmatter 시작 구분자가 없습니다."); exit }
  next
}
!closed && $0 ~ /^[[:space:]]*---[[:space:]]*$/ { closed=1; next }
!closed {
  if ($0 ~ /^[[:space:]]*$/) next
  if ($0 !~ /^[A-Za-z][A-Za-z0-9_-]*:[[:space:]]*/) { error("frontmatter " NR "번째 줄 형식이 올바르지 않습니다."); next }
  key=$0; sub(/:.*/, "", key)
  value=$0; sub(/^[^:]*:[[:space:]]*/, "", value)
  if (seen[key]++) error("frontmatter에 " key " 필드가 중복됩니다.")
  if (key != "name" && key != "description") error("공용 frontmatter에서 지원하지 않는 필드입니다: " key)
  values[key]=unquote(value)
}
END {
  if (NR > 1 && !closed) error("YAML frontmatter 종료 구분자가 없습니다.")
  if (closed) {
    if (!("name" in values) || values["name"] != expected) error("frontmatter name이 디렉터리 이름과 일치하지 않습니다.")
    if (!("description" in values) || values["description"] ~ /^[[:space:]]*$/) error("description이 비어 있습니다.")
    else if (length(values["description"]) > 1024) error("description이 1024자를 넘습니다.")
  }
  exit failed
}' "$skill_path"; then
    skill_errors=1
  fi

  if grep -Eq '\]\([^)]*\\[^)]*\)' "$skill_path"; then
    printf '%s: Markdown 링크에는 Windows 역슬래시 대신 /를 사용해야 합니다.\n' "$skill_name" >&2
    skill_errors=1
  fi

  awk '
{
  text=$0
  while (match(text, /\]\([^)]*\)/)) {
    reference=substr(text, RSTART+2, RLENGTH-3)
    print reference
    text=substr(text, RSTART+RLENGTH)
  }
}' "$skill_path" > "$references_file"
  while IFS= read -r reference; do
    reference=${reference%%#*}
    case $reference in ''|http://*|https://*|mailto:*|/*) continue ;; esac
    if [ ! -e "$directory/$reference" ]; then
      printf '%s: 참조 파일을 찾을 수 없습니다: %s\n' "$skill_name" "$reference" >&2
      skill_errors=1
    fi
  done < "$references_file"

  if [ "$skill_errors" -eq 0 ]; then
    printf '[ok] %s\n' "$skill_name"
  else
    errors=1
  fi
done < "$directories_file"

if [ "$skip_sensitive" = false ]; then
  "$script_dir/check-sensitive.sh" --all --skip-gitleaks || {
    report_error '민감정보 검사에 실패했습니다.'
  }
fi

[ "$errors" -eq 0 ] || exit 1
printf 'Skill 검증을 완료했습니다: %s개\n' "$skill_count"
