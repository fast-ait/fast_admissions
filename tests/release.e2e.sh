#!/usr/bin/env bash
# End-to-end tests for scripts/release.sh against a throwaway host with Docker.
#   FAST_SSH_HOST=sanit@dgx-geoid-lab bash tests/release.e2e.sh
# Creates and removes ~/fast-admissions and container fast-admissions-web on that host.
# Never point this at the live server.
set -uo pipefail

HOST="${FAST_SSH_HOST:?set FAST_SSH_HOST to a throwaway docker host}"
[[ "$HOST" != *web-asl* ]] || { echo "refusing to run against the live server" >&2; exit 2; }
PORT=18092
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp)"
failures=0

remote() { ssh "$HOST" "$@"; }
release() { bash "$1/scripts/release.sh" "${@:2}" >>"$LOG" 2>&1; }
current() { remote "readlink fast-admissions/current" | sed 's|^releases/||'; }

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "PASS $name"; else
    echo "FAIL $name: expected [$expected], got [$actual]"; failures=$((failures + 1)); fi
}

# A worktree of HEAD with one extra commit made by the given command.
variant() {
  local dir; dir="$(mktemp -d)/wt"
  git -C "$REPO" worktree add -q --detach "$dir" HEAD
  (cd "$dir" && eval "$1" && git add -A && git -c user.name=e2e -c user.email=e2e@local commit -qm "e2e: $2")
  echo "$dir"
}

cleanup() {
  remote "cd fast-admissions/deploy 2>/dev/null && docker compose down >/dev/null 2>&1; rm -rf ~/fast-admissions" || true
  for wt in "${worktrees[@]:-}"; do [[ -n "$wt" ]] && git -C "$REPO" worktree remove --force "$wt"; done
}
worktrees=()
trap cleanup EXIT

remote "test ! -e fast-admissions" || { echo "~/fast-admissions already exists on $HOST" >&2; exit 2; }
release "$REPO" setup --port "$PORT"

# 1. publish with no --port uses the port the container actually listens on.
status=0; release "$REPO" publish || status=$?
good="$(current)"
check publish_uses_running_port "0 yes" "$status $([[ -n "$good" ]] && echo yes)"

# 2. failed publishes roll back to the Release that was live, and never prune it.
broken_site="$(variant 'rm site/assets/ait-logo.png && sed -i "/ait-logo.png/d" site/index.html' 'break the site')"; worktrees+=("$broken_site")
release "$broken_site" publish || true
release "$broken_site" publish || true
check failed_publish_restores_live "$good yes" \
  "$(current) $(remote "test -d fast-admissions/releases/$good" && echo yes)"

# 3. an invalid nginx.conf never replaces the live one.
before="$(remote 'md5sum < fast-admissions/deploy/nginx.conf')"
broken_conf="$(variant 'echo "garbage" >> deploy/nginx.conf' 'break nginx.conf')"; worktrees+=("$broken_conf")
status=0; release "$broken_conf" publish || status=$?
check bad_nginx_conf_rejected "1 $before $good" \
  "$status $(remote 'md5sum < fast-admissions/deploy/nginx.conf') $(current)"

echo "log: $LOG"
[[ $failures -eq 0 ]] || { echo "$failures failed"; exit 1; }
echo "all passed"
