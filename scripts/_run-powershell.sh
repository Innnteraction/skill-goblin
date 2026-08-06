#!/bin/sh
set -eu

script_path=$1
shift

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "$script_path" "$@"
fi

if command -v powershell.exe >/dev/null 2>&1; then
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_path" "$@"
fi

printf '%s\n' 'PowerShell(pwsh 또는 powershell.exe)을 찾을 수 없습니다.' >&2
exit 127
