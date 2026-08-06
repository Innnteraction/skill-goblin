#!/bin/sh
set -eu

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P)
# shellcheck source=scripts/_common.sh
. "$script_dir/_common.sh"

[ "$#" -eq 0 ] || {
  printf '알 수 없는 옵션: %s\n' "$1" >&2
  exit 2
}

root=$(repository_root) || exit 1
cd "$root"

set_config() {
  key=$1
  value=$2
  git config --local "$key" "$value" || {
    printf 'Git 로컬 설정을 저장하지 못했습니다: %s\n' "$key" >&2
    exit 1
  }
  actual=$(git config --local --get "$key")
  [ "$actual" = "$value" ] || {
    printf 'Git 설정 검증에 실패했습니다: %s\n' "$key" >&2
    exit 1
  }
  printf '[ok] %s=%s\n' "$key" "$actual"
}

set_config user.name Innnteraction
set_config user.email innnteractive@gmail.com
set_config core.hooksPath .githooks
set_config merge.ff only
set_config pull.ff only
set_config push.default nothing
set_config fetch.prune true
printf '%s\n' '저장소 로컬 Git 설정과 hook 경로를 적용했습니다.'
