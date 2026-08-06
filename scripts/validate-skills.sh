#!/bin/sh
set -eu
case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH= cd -- "$script_dir" && pwd)
exec "$script_dir/_run-powershell.sh" "$script_dir/validate-skills.ps1" "$@"
