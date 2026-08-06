#!/bin/sh
set -eu

name=
description=
with_scripts=false
with_references=false
with_assets=false

while [ "$#" -gt 0 ]; do
  case $1 in
    --name|-Name)
      option=$1
      value=${2-}
      [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }
      name=$value
      shift 2
      ;;
    --description|-Description)
      option=$1
      value=${2-}
      [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }
      description=$value
      shift 2
      ;;
    --with-scripts|-WithScripts) with_scripts=true; shift ;;
    --with-references|-WithReferences) with_references=true; shift ;;
    --with-assets|-WithAssets) with_assets=true; shift ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$name" ] || [ -z "$description" ]; then
  printf '%s\n' '사용법: new-skill.sh --name <name> --description <text>' >&2
  exit 2
fi

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P)
# shellcheck source=scripts/_common.sh
. "$script_dir/_common.sh"

is_skill_name "$name" || {
  printf '%s\n' 'Skill 이름은 64자 이하의 소문자, 숫자, 하이픈만 사용하고 하이픈으로 시작하거나 끝낼 수 없습니다.' >&2
  exit 1
}
[ "${#description}" -le 1024 ] || {
  printf '%s\n' 'Skill description은 1024자를 넘을 수 없습니다.' >&2
  exit 1
}

root=$(repository_root) || exit 1
destination=$root/skills/$name
[ ! -e "$destination" ] || {
  printf '이미 같은 이름의 경로가 있습니다: skills/%s\n' "$name" >&2
  exit 1
}
template=$root/templates/skill/SKILL.md
version_template=$root/templates/skill/VERSION
[ -f "$template" ] || { printf '%s\n' 'Skill 템플릿을 찾을 수 없습니다.' >&2; exit 1; }
[ -f "$version_template" ] || { printf '%s\n' 'Skill VERSION 템플릿을 찾을 수 없습니다.' >&2; exit 1; }

title=$(printf '%s\n' "$name" | awk -F- '{ for (i=1; i<=NF; i++) { printf "%s%s", toupper(substr($i,1,1)) substr($i,2), (i<NF ? " " : "") } }')
yaml_description=$(printf '%s' "$description" | sed "s/'/''/g")
temp_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-new-skill.XXXXXX") || exit 1
trap 'rm -f "$temp_file"' 0 HUP INT TERM

awk -v skill_name="$name" -v skill_description="$yaml_description" -v skill_title="$title" '
function replace_all(text, needle, replacement,    result, position) {
  result = ""
  while ((position = index(text, needle)) > 0) {
    result = result substr(text, 1, position - 1) replacement
    text = substr(text, position + length(needle))
  }
  return result text
}
{
  line = replace_all($0, "__SKILL_NAME__", skill_name)
  line = replace_all(line, "__SKILL_DESCRIPTION__", skill_description)
  line = replace_all(line, "__SKILL_TITLE__", skill_title)
  print line
}' "$template" > "$temp_file"

mkdir -p "$destination"
mv "$temp_file" "$destination/SKILL.md"
trap - 0 HUP INT TERM
cp "$version_template" "$destination/VERSION"
[ "$with_scripts" = false ] || mkdir -p "$destination/scripts"
[ "$with_references" = false ] || mkdir -p "$destination/references"
[ "$with_assets" = false ] || mkdir -p "$destination/assets"
printf 'Skill 골격을 만들었습니다: skills/%s/SKILL.md\n' "$name"
