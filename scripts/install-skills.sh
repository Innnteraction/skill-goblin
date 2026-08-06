#!/bin/sh
set -eu

target='All'
scope='User'
project_path=''
name=''
force=false

require_value() {
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    printf '옵션에 값이 필요합니다: %s\n' "$1" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) require_value "$@"; target=$2; shift 2 ;;
    --scope) require_value "$@"; scope=$2; shift 2 ;;
    --project-path) require_value "$@"; project_path=$2; shift 2 ;;
    --name) require_value "$@"; name=$2; shift 2 ;;
    --force) force=true; shift ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH= cd -- "$script_dir" && pwd)

set -- -Target "$target" -Scope "$scope"
if [ -n "$name" ]; then
  set -- "$@" -Name "$name"
fi
if [ -n "$project_path" ]; then
  set -- "$@" -ProjectPath "$project_path"
fi
if [ "$force" = true ]; then
  set -- "$@" -Force
fi
exec "$script_dir/_run-powershell.sh" "$script_dir/install-skills.ps1" "$@"
