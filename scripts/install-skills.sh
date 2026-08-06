#!/bin/sh
set -eu

target=all
scope=user
project_path=
name=
force=false

while [ "$#" -gt 0 ]; do
  case $1 in
    --target|-Target) option=$1; value=${2-}; [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }; target=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
    --scope|-Scope) option=$1; value=${2-}; [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }; scope=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
    --project-path|-ProjectPath) option=$1; value=${2-}; [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }; project_path=$value; shift 2 ;;
    --name|-Name) option=$1; value=${2-}; [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }; name=$value; shift 2 ;;
    --force|-Force) force=true; shift ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case $target in codex|claude|all) ;; *) printf '지원하지 않는 target입니다: %s\n' "$target" >&2; exit 2 ;; esac
case $scope in user|project) ;; *) printf '지원하지 않는 scope입니다: %s\n' "$scope" >&2; exit 2 ;; esac

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P)
# shellcheck source=scripts/_common.sh
. "$script_dir/_common.sh"
root=$(repository_root) || exit 1

if [ -n "$name" ]; then
  "$script_dir/validate-skills.sh" --skip-sensitive-check --name "$name" || validation_failed=true
else
  "$script_dir/validate-skills.sh" --skip-sensitive-check || validation_failed=true
fi
if [ "${validation_failed-false}" = true ]; then
  printf '%s\n' 'Skill 검증에 실패해 설치를 중단했습니다.' >&2
  exit 1
fi

skills_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-skills.XXXXXX") || exit 1
targets_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-targets.XXXXXX") || { rm -f "$skills_file"; exit 1; }
conflicts_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-conflicts.XXXXXX") || { rm -f "$skills_file" "$targets_file"; exit 1; }
trap 'rm -f "$skills_file" "$targets_file" "$conflicts_file"' 0 HUP INT TERM
skill_directories "$root" "$name" > "$skills_file" || exit 1
[ -s "$skills_file" ] || { printf '%s\n' '설치할 Skill이 없습니다.'; exit 0; }

if [ "$scope" = project ]; then
  [ -n "$project_path" ] || { printf '%s\n' 'Project 범위에는 --project-path가 필요합니다.' >&2; exit 1; }
  [ -d "$project_path" ] || { printf '프로젝트 디렉터리를 찾을 수 없습니다: %s\n' "$project_path" >&2; exit 1; }
  project_root=$(CDPATH='' cd -- "$project_path" && pwd -P)
  case $target in codex|all) printf 'Codex\t%s\n' "$project_root/.agents/skills" >> "$targets_file" ;; esac
  case $target in claude|all) printf 'Claude\t%s\n' "$project_root/.claude/skills" >> "$targets_file" ;; esac
else
  [ -z "$project_path" ] || { printf '%s\n' '--project-path는 Project 범위에서만 사용할 수 있습니다.' >&2; exit 1; }
  home_directory=$(user_home_directory) || exit 1
  case $target in codex|all) printf 'Codex\t%s\n' "$home_directory/.agents/skills" >> "$targets_file" ;; esac
  if [ -n "${CLAUDE_HOME-}" ]; then claude_home=$CLAUDE_HOME; else claude_home=$home_directory/.claude; fi
  case $target in claude|all) printf 'Claude\t%s\n' "$claude_home/skills" >> "$targets_file" ;; esac
fi

while IFS="	" read -r target_name skills_root; do
  mkdir -p "$skills_root"
  while IFS= read -r skill; do
    skill_name=${skill##*/}
    destination=$skills_root/$skill_name
    if [ -e "$destination" ]; then
      source_hash=$(directory_fingerprint "$skill") || exit 1
      destination_hash=$(directory_fingerprint "$destination") || exit 1
      if [ "$source_hash" != "$destination_hash" ] && [ "$force" = false ]; then
        printf '%s: %s\n' "$target_name" "$destination" >> "$conflicts_file"
      fi
    fi
  done < "$skills_file"
done < "$targets_file"

if [ -s "$conflicts_file" ]; then
  while IFS= read -r conflict; do printf '다른 내용의 설치 대상이 있습니다: %s\n' "$conflict" >&2; done < "$conflicts_file"
  printf '%s\n' '기존 복사본을 확인한 뒤 의도적으로 교체할 때만 --force를 사용하세요.' >&2
  exit 1
fi

while IFS="	" read -r target_name skills_root; do
  while IFS= read -r skill; do
    skill_name=${skill##*/}
    destination=$skills_root/$skill_name
    if [ -e "$destination" ]; then
      source_hash=$(directory_fingerprint "$skill") || exit 1
      destination_hash=$(directory_fingerprint "$destination") || exit 1
      if [ "$source_hash" = "$destination_hash" ]; then
        printf '[same] %s: %s\n' "$target_name" "$skill_name"
        continue
      fi
      rm -rf "$destination"
    fi
    cp -R "$skill" "$destination"
    printf '[installed] %s: %s\n' "$target_name" "$skill_name"
  done < "$skills_file"
done < "$targets_file"
