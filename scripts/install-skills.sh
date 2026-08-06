#!/bin/sh
set -eu

target='All'
name=''
force=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) target=${2-}; shift 2 ;;
    --name) name=${2-}; shift 2 ;;
    --force) force='-Force'; shift ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH= cd -- "$script_dir" && pwd)
if [ -n "$name" ]; then
  exec "$script_dir/_run-powershell.sh" "$script_dir/install-skills.ps1" -Target "$target" -Name "$name" $force
fi
exec "$script_dir/_run-powershell.sh" "$script_dir/install-skills.ps1" -Target "$target" $force
