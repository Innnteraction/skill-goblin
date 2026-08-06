#!/bin/sh
set -u

usage_error() {
  printf '%s\n' "$1" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage_error '첫 인자는 discover 또는 trace여야 합니다.'
command_name=$1
shift
case $command_name in discover|trace) ;; *) usage_error '첫 인자는 discover 또는 trace여야 합니다.' ;; esac

root=
entry=
profile=auto
max_depth=4
max_nodes=80
typescript_path=
output=

while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || usage_error "값이 없는 인자입니다: $1"
  option=$1
  value=$2
  case $option in
    --root|-Root) root=$value ;;
    --entry|-Entry) entry=$value ;;
    --profile|-Profile) profile=$value ;;
    --max-depth|-MaxDepth) max_depth=$value ;;
    --max-nodes|-MaxNodes) max_nodes=$value ;;
    --typescript-path|-TypeScriptPath) typescript_path=$value ;;
    --output|-Output) output=$value ;;
    *) usage_error "지원하지 않는 인자입니다: $option" ;;
  esac
  shift 2
done

if [ -z "$root" ] || [ -z "$output" ]; then usage_error '--root와 --output이 필요합니다.'; fi
case $profile in auto|http|worker|cli|generic) ;; *) usage_error '지원하지 않는 profile입니다.' ;; esac
printf '%s\n' "$max_depth" | grep -Eq '^[0-9]+$' || usage_error 'max-depth는 0 이상의 정수여야 합니다.'
printf '%s\n' "$max_nodes" | grep -Eq '^[1-9][0-9]*$' || usage_error 'max-nodes는 1 이상의 정수여야 합니다.'
[ "$command_name" != trace ] || [ -n "$entry" ] || usage_error 'trace에는 --entry가 필요합니다.'

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P) || exit 4
[ -d "$root" ] || { printf 'root 디렉터리를 찾을 수 없습니다: %s\n' "$root" >&2; exit 4; }
resolved_root=$(CDPATH='' cd -- "$root" && pwd -P) || exit 4

output_parent=$(dirname "$output")
output_name=$(basename "$output")
mkdir -p "$output_parent" || exit 4
resolved_output_parent=$(CDPATH='' cd -- "$output_parent" && pwd -P) || exit 4
resolved_output=$resolved_output_parent/$output_name

has_python=false
if find "$resolved_root" \( -type d \( -name .git -o -name .hg -o -name .venv -o -name venv -o -name node_modules -o -name dist -o -name build -o -name coverage -o -name __pycache__ -o -name '.*' \) -prune \) -o \( -type f \( -name pyproject.toml -o -name setup.cfg -o -name setup.py -o -name '*.py' \) -print \) | grep -q .; then
  has_python=true
fi
has_js=false
if find "$resolved_root" \( -type d \( -name .git -o -name .hg -o -name .venv -o -name venv -o -name node_modules -o -name dist -o -name build -o -name coverage -o -name __pycache__ -o -name '.*' \) -prune \) -o \( -type f -name package.json -print \) | grep -q .; then
  has_js=true
fi

language=
if [ "$command_name" = trace ]; then
  entry_path=${entry%%#*}
  entry_path=$(printf '%s' "$entry_path" | sed 's/:[0-9][0-9]*$//')
  case $entry_path in
    *.py) language=python ;;
    *.js|*.jsx|*.mjs|*.mts|*.cjs|*.cts|*.ts|*.tsx) language=js ;;
    *)
      if [ "$has_python" = true ] && [ "$has_js" = false ]; then language=python
      elif [ "$has_js" = true ] && [ "$has_python" = false ]; then language=js
      else usage_error 'entry 언어를 결정할 수 없습니다. 파일 확장자를 포함하십시오.'
      fi
      ;;
  esac
elif [ "$has_python" = true ] && [ "$has_js" = false ]; then
  language=python
elif [ "$has_js" = true ] && [ "$has_python" = false ]; then
  language=js
elif [ "$has_python" = false ] && [ "$has_js" = false ]; then
  usage_error '지원하는 Python 또는 JS/TS 소스를 찾지 못했습니다.'
fi

find_python() {
  if command -v python3 >/dev/null 2>&1; then command -v python3
  elif command -v python >/dev/null 2>&1; then command -v python
  else return 1
  fi
}

run_python() {
  destination=$1
  python=$(find_python) || { printf '%s\n' 'Python 런타임을 찾을 수 없습니다.' >&2; return 3; }
  set -- "$command_name" --root "$resolved_root" --profile "$profile" --max-depth "$max_depth" --max-nodes "$max_nodes" --output "$destination"
  [ -z "$entry" ] || set -- "$@" --entry "$entry"
  "$python" "$script_dir/analyze-python.py" "$@"
}

run_js() {
  destination=$1
  node=$(command -v node 2>/dev/null) || { printf '%s\n' 'Node.js 런타임을 찾을 수 없습니다.' >&2; return 3; }
  set -- "$command_name" --root "$resolved_root" --profile "$profile" --max-depth "$max_depth" --max-nodes "$max_nodes" --output "$destination"
  [ -z "$entry" ] || set -- "$@" --entry "$entry"
  [ -z "$typescript_path" ] || set -- "$@" --typescript-path "$typescript_path"
  "$node" "$script_dir/analyze-js-ts.mjs" "$@"
}

case $language in
  python) run_python "$resolved_output"; exit $? ;;
  js) run_js "$resolved_output"; exit $? ;;
esac

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/reverse-engineer-service.XXXXXX") || exit 4
trap 'rm -rf "$temporary_root"' 0 HUP INT TERM
python_output=$temporary_root/python.json
js_output=$temporary_root/js.json

run_python "$python_output"
python_code=$?
case $python_code in 0|4) ;; *) exit "$python_code" ;; esac
run_js "$js_output"
js_code=$?
case $js_code in 0|4) ;; *) exit "$js_code" ;; esac

python=$(find_python) || { printf '%s\n' 'Python 런타임을 찾을 수 없습니다.' >&2; exit 3; }
"$python" "$script_dir/merge-code-facts.py" --python "$python_output" --javascript "$js_output" --output "$resolved_output" || exit 4
if [ "$python_code" -ne 0 ] || [ "$js_code" -ne 0 ]; then exit 4; fi
exit 0
