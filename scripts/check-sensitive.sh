#!/bin/sh
set -eu

mode=staged
mode_set=false
revision_range=
skip_gitleaks=false

set_mode() {
  requested=$1
  if [ "$mode_set" = true ] && [ "$mode" != "$requested" ]; then
    printf '%s\n' 'Staged, All, Range 중 하나만 지정할 수 있습니다.' >&2
    exit 2
  fi
  mode=$requested
  mode_set=true
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --staged|-Staged) set_mode staged; shift ;;
    --all|-All) set_mode all; shift ;;
    --range|-Range)
      set_mode range
      option=$1
      value=${2-}
      [ -n "$value" ] || { printf '옵션에 값이 필요합니다: %s\n' "$option" >&2; exit 2; }
      revision_range=$value
      shift 2
      ;;
    --skip-gitleaks|-SkipGitleaks) skip_gitleaks=true; shift ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P)
# shellcheck source=scripts/_common.sh
. "$script_dir/_common.sh"
root=$(repository_root) || exit 1
cd "$root"

if [ "$mode" = range ]; then
  [ -n "$revision_range" ] || { printf '%s\n' 'Range 모드에는 revision 범위가 필요합니다.' >&2; exit 2; }
  printf '%s\n' "$revision_range" | grep -Eq '^[0-9a-fA-F.^~!]+(\.\.[0-9a-fA-F.^~!]+)?$' || {
    printf '%s\n' '안전하지 않거나 올바르지 않은 Git revision 범위입니다.' >&2
    exit 1
  }
fi

paths_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-sensitive-paths.XXXXXX") || exit 1
content_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-sensitive-content.XXXXXX") || { rm -f "$paths_file"; exit 1; }
findings_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-sensitive-findings.XXXXXX") || { rm -f "$paths_file" "$content_file"; exit 1; }
trap 'rm -f "$paths_file" "$content_file" "$findings_file"' 0 HUP INT TERM

case $mode in
  staged) git diff --cached --name-only --diff-filter=ACMR -- > "$paths_file" || exit 1 ;;
  all) git ls-files --cached --others --exclude-standard > "$paths_file" || exit 1 ;;
  range) git diff --name-only --diff-filter=ACMR "$revision_range" -- > "$paths_file" || exit 1 ;;
esac

add_finding() {
  rule=$1
  path=$2
  finding="[$rule] $path"
  grep -Fqx "$finding" "$findings_file" 2>/dev/null || printf '%s\n' "$finding" >> "$findings_file"
}

while IFS= read -r path; do
  normalized=$path
  case $normalized in .env.example|.env.sample) continue ;; esac
  case $normalized in
    .env|.env.*|*/.env|*/.env.*|*.key|*.pem|*.p12|*.pfx|*.jks|*.keystore|credentials.json|*/credentials.json|service-account*.json|*/service-account*.json|secrets/*|*/secrets/*|.aws/*|*/.aws/*|.ssh/*|*/.ssh/*)
      add_finding risky-file "$normalized"
      ;;
  esac
done < "$paths_file"

scan_content() {
  label=$1
  file=$2
  generic_pattern="(password|passwd|secret|api[_-]?key|access[_-]?token)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9_./+=:-]{12,}"
  if LC_ALL=C grep -aEq -- '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' "$file"; then add_finding private-key "$label"; fi
  if LC_ALL=C grep -aEq -- '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' "$file"; then add_finding github-token "$label"; fi
  if LC_ALL=C grep -aEq -- '(AKIA|ASIA)[A-Z0-9]{16}' "$file"; then add_finding aws-access-key "$label"; fi
  if LC_ALL=C grep -aEq -- 'xox[baprs]-[A-Za-z0-9-]{20,}' "$file"; then add_finding slack-token "$label"; fi
  if LC_ALL=C grep -aEq -- 'sk-[A-Za-z0-9_-]{20,}' "$file"; then add_finding openai-api-key "$label"; fi
  if LC_ALL=C grep -aiE -- "$generic_pattern" "$file" | LC_ALL=C grep -Eiv -- 'EXAMPLE|PLACEHOLDER|CHANGEME|REDACTED|<' >/dev/null; then
    add_finding generic-secret "$label"
  fi
}

if [ "$mode" = range ]; then
  git diff --no-ext-diff --unified=0 --no-color "$revision_range" -- | awk '/^\+\+\+/ { next } /^\+/ { print substr($0,2) }' > "$content_file" || exit 1
  scan_content "Git 범위: $revision_range" "$content_file"
else
  while IFS= read -r path; do
    if [ "$mode" = staged ]; then
      git show ":$path" > "$content_file" 2>/dev/null || continue
    else
      [ -f "$path" ] || continue
      cp "$path" "$content_file" 2>/dev/null || continue
    fi
    scan_content "$path" "$content_file"
  done < "$paths_file"
fi

if [ -s "$findings_file" ]; then
  printf '%s\n' '민감정보로 의심되는 항목을 발견했습니다. 실제 값은 출력하지 않습니다.' >&2
  while IFS= read -r finding; do printf '%s\n' "$finding" >&2; done < "$findings_file"
  exit 1
fi

if [ "$skip_gitleaks" = false ]; then
  if ! command -v gitleaks >/dev/null 2>&1; then
    printf '%s\n' '경고: Gitleaks가 없어 내장 검사만 실행했습니다.' >&2
  else
    case $mode in
      staged) gitleaks git --pre-commit --redact --staged --verbose ;;
      all) gitleaks git --redact --verbose . ;;
      range) gitleaks git --redact --verbose "--log-opts=$revision_range" . ;;
    esac || { printf '%s\n' 'Gitleaks 검사에 실패했습니다.' >&2; exit 1; }
  fi
fi

case $mode in staged) label=Staged ;; all) label=All ;; range) label=Range ;; esac
printf '민감정보 검사를 통과했습니다: %s\n' "$label"
