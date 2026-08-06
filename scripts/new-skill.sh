#!/bin/sh
set -eu

name=''
description=''
extra=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) name=${2-}; shift 2 ;;
    --description) description=${2-}; shift 2 ;;
    --with-scripts) extra="$extra -WithScripts"; shift ;;
    --with-references) extra="$extra -WithReferences"; shift ;;
    --with-assets) extra="$extra -WithAssets"; shift ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$name" ] || [ -z "$description" ]; then
  printf '%s\n' '사용법: new-skill.sh --name <name> --description <text>' >&2
  exit 2
fi

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH= cd -- "$script_dir" && pwd)
# shellcheck disable=SC2086
exec "$script_dir/_run-powershell.sh" "$script_dir/new-skill.ps1" -Name "$name" -Description "$description" $extra
