#!/usr/bin/env bash
# Build on this machine, publish Releases to the server, roll back.
#
#   release.sh preview                 check the site, then serve it at http://<tailscale-ip>:4174/
#   release.sh setup [--port P]        install deploy/ on the server and (re)start the container on port P
#                                      (default: the port it already runs on, else 8082)
#   release.sh publish [--port P]      build a clean tree, upload a Release, switch to it, smoke-check;
#                                      on failure, restore the Release and config that were live
#   release.sh rollback [<id>]         switch back to <id> or the previous Release
#   release.sh list                    Releases on the server, newest first, current marked *
#
# The server is reached through the ssh alias in $FAST_SSH_HOST (default: web-asl).
set -euo pipefail

HOST="${FAST_SSH_HOST:-web-asl}"
REMOTE_ROOT="fast-admissions"   # relative to the remote home
CONTAINER="fast-admissions-web"
IMAGE="nginx:1.27-alpine"
PORT=""

cd "$(dirname "$0")/.."

die() { echo "release: $*" >&2; exit 1; }

parse_port() {
  if [[ "${1:-}" == "--port" ]]; then
    [[ -n "${2:-}" ]] || die "--port needs a value"
    PORT="$2"
  elif [[ -n "${1:-}" ]]; then
    die "unknown argument: $1"
  fi
}

# No build step: the site is plain files. Check them, then stage as dist/.
build() {
  bash tests/site.test.sh
  rm -rf dist
  cp -r site dist
}

remote() { ssh "$HOST" "$@"; }
activate() { remote "bash $REMOTE_ROOT/deploy/activate.sh $REMOTE_ROOT $*"; }

# Host port the running container publishes, or nothing.
running_port() {
  { remote "docker port $CONTAINER 80/tcp 2>/dev/null" || true; } | head -n 1 | sed 's/.*://'
}

# Upload deploy/ beside the live copy, validate it in a throwaway nginx, then
# copy it over the live one (keeping deploy.prev). An invalid config never lands.
install_deploy() {
  remote "mkdir -p $REMOTE_ROOT/releases $REMOTE_ROOT/deploy $REMOTE_ROOT/deploy.new"
  rsync -a --delete deploy/ "$HOST:$REMOTE_ROOT/deploy.new/"
  remote "docker run --rm -v \"\$HOME/$REMOTE_ROOT/deploy.new:/etc/nginx/conf.d:ro\" $IMAGE nginx -t -q" \
    || die "deploy/nginx.conf is invalid; the live config was not touched"
  remote "rsync -a --delete $REMOTE_ROOT/deploy/ $REMOTE_ROOT/deploy.prev/ &&
          rsync -a --delete $REMOTE_ROOT/deploy.new/ $REMOTE_ROOT/deploy/"
}

restore_deploy() {
  remote "rsync -a --delete $REMOTE_ROOT/deploy.prev/ $REMOTE_ROOT/deploy/"
}

reload() {
  remote "cd $REMOTE_ROOT/deploy && docker compose exec -T web nginx -s reload"
}

smoke() {
  remote "bash $REMOTE_ROOT/deploy/smoke.sh http://localhost:$PORT"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  preview)
    build
    echo "preview: http://$(tailscale ip -4 2>/dev/null || hostname -I | awk '{print $1}'):4174/"
    python3 -m http.server 4174 --bind 0.0.0.0 --directory dist
    ;;

  setup)
    parse_port "$@"
    running="$(running_port)"
    PORT="${PORT:-${running:-8082}}"
    install_deploy
    remote "cd $REMOTE_ROOT/deploy && PORT=$PORT docker compose up -d"
    ;;

  publish)
    parse_port "$@"
    running="$(running_port)"
    [[ -n "$running" ]] || die "$CONTAINER is not running on $HOST; run setup first"
    [[ -z "$PORT" || "$PORT" == "$running" ]] || die "--port $PORT, but $CONTAINER listens on $running"
    PORT="$running"
    dirty="$(git status --porcelain)"
    [[ -z "$dirty" ]] || die "working tree is not clean, commit first:
$dirty"
    build
    id="$(date -u +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
    # Hard-link files unchanged since the live Release.
    # Every build gives files new mtimes, and --link-dest only links files whose
    # preserved attributes match: compare by content and don't preserve times.
    rsync -rlpD --checksum --delete --link-dest=../../current/ dist/ "$HOST:$REMOTE_ROOT/releases/$id/"
    install_deploy
    previous="$(activate current)"
    activate switch "$id"
    if reload && smoke; then
      activate prune
      echo "published $id"
    else
      echo "release: $id failed its checks, restoring ${previous:-nothing}" >&2
      restore_deploy
      [[ -z "$previous" ]] || activate switch "$previous"
      reload || echo "release: WARNING nginx reload failed after restore, check $CONTAINER now" >&2
      exit 1
    fi
    ;;

  rollback)
    activate rollback "${1:-}"
    ;;

  list)
    activate list
    ;;

  *)
    sed -n '2,12p' "$0" >&2
    exit 2
    ;;
esac
