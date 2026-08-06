#!/bin/sh
set -eu

case "$0" in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
test_dir=$(CDPATH='' cd -- "$test_dir" && pwd -P)
repository_root=$(CDPATH='' cd -- "$test_dir/.." && pwd -P)

command -v docker >/dev/null 2>&1 || {
  printf '%s\n' 'Docker 실행 파일을 찾을 수 없습니다.' >&2
  exit 3
}

iid_file=$(mktemp "${TMPDIR:-/tmp}/skill-goblin-linux-image.XXXXXX") || exit 1
cleanup() {
  if [ -s "$iid_file" ]; then
    image_id=$(sed -n '1p' "$iid_file")
    [ -z "$image_id" ] || docker image rm "$image_id" >/dev/null 2>&1 || true
  fi
  rm -f "$iid_file"
}
trap cleanup 0 HUP INT TERM

docker build --file "$repository_root/tests/linux.Dockerfile" --iidfile "$iid_file" "$repository_root"
image_id=$(sed -n '1p' "$iid_file")
docker run --rm \
  --mount "type=bind,src=$repository_root,dst=/workspace,readonly" \
  --workdir /workspace \
  "$image_id" \
  sh -c 'git config --global --add safe.directory /workspace && shellcheck -s sh scripts/*.sh .githooks/* skills/reverse-engineer-service/scripts/analyze-code.sh tests/*.sh && ./tests/run-tests.sh'
