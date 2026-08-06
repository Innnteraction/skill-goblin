#!/bin/sh

repository_root() {
  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf '%s\n' '현재 디렉터리는 Git 저장소가 아닙니다.' >&2
    return 1
  }
  (CDPATH='' cd -- "$root" && pwd -P)
}

is_skill_name() {
  case ${1-} in
    ''|*[!a-z0-9-]*|-*|*-) return 1 ;;
  esac
  [ "${#1}" -le 64 ] || return 1
  case $1 in *--*) return 1 ;; esac
  return 0
}

skill_directories() {
  root=$1
  selected=${2-}
  skills_root=$root/skills

  [ -d "$skills_root" ] || return 0
  if [ -n "$selected" ]; then
    is_skill_name "$selected" || {
      printf '올바르지 않은 Skill 이름입니다: %s\n' "$selected" >&2
      return 1
    }
    [ -d "$skills_root/$selected" ] || {
      printf 'Skill을 찾을 수 없습니다: %s\n' "$selected" >&2
      return 1
    }
    printf '%s\n' "$skills_root/$selected"
    return 0
  fi

  find "$skills_root" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort
}

directory_fingerprint() {
  directory=$1
  [ -d "$directory" ] || return 1
  resolved=$(CDPATH='' cd -- "$directory" && pwd -P) || return 1

  find "$resolved" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    relative=${file#"$resolved"/}
    hash=$(git hash-object --no-filters -- "$file") || exit 1
    printf '%s\n%s\n' "$relative" "$hash"
  done | git hash-object --stdin
}

user_home_directory() {
  if [ -z "${HOME-}" ]; then
    printf '%s\n' 'HOME 환경변수가 비어 있습니다.' >&2
    return 1
  fi
  case $HOME in
    /*) printf '%s\n' "${HOME%/}" ;;
    *) printf '%s\n' "$PWD/${HOME%/}" ;;
  esac
}
