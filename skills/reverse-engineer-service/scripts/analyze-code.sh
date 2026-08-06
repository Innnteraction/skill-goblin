#!/bin/sh
set -eu
case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH= cd -- "$script_dir" && pwd)

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "$script_dir/analyze-code.ps1" "$@"
fi

if command -v powershell.exe >/dev/null 2>&1; then
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_dir/analyze-code.ps1" "$@"
fi

echo "PowerShell 7 또는 Windows PowerShell을 찾을 수 없습니다." >&2
exit 3
