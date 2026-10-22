#!/usr/bin/env bash
# Switch, roll back and list Releases under <root>/releases, served via <root>/current.
#
#   activate.sh <root> activate <release-id>   switch, then prune
#   activate.sh <root> switch <release-id>     point current at a Release
#   activate.sh <root> prune                   keep the newest 5 Releases plus current
#   activate.sh <root> current                 print the current Release id
#   activate.sh <root> rollback [<release-id>] point current at the given or previous Release
#   activate.sh <root> list                    Release ids, newest first, current marked with *
#
# Release ids sort lexically by age (they start with a UTC timestamp).
set -euo pipefail

KEEP=5

usage() { echo "usage: $0 <root> activate <id> | switch <id> | prune | current | rollback [<id>] | list" >&2; exit 2; }

[[ $# -ge 2 ]] || usage
root="$1"; cmd="$2"; shift 2

releases() { ls -1 "$root/releases" | sort; }

current_id() {
  local target
  target="$(readlink "$root/current" 2>/dev/null || true)"
  echo "${target#releases/}"
}

# Relative target so the link also resolves inside the container mount.
switch_to() {
  local id="$1"
  [[ -n "$id" && -d "$root/releases/$id" ]] || { echo "no such release: $id" >&2; exit 1; }
  ln -sfn "releases/$id" "$root/current.tmp"
  mv -T "$root/current.tmp" "$root/current"
  echo "current -> $id"
}

prune() {
  local current id
  current="$(current_id)"
  releases | head -n -"$KEEP" | while read -r id; do
    [[ "$id" == "$current" ]] || rm -rf -- "$root/releases/$id"
  done
}

case "$cmd" in
  activate)
    [[ $# -eq 1 ]] || usage
    switch_to "$1"
    prune
    ;;
  switch)
    [[ $# -eq 1 ]] || usage
    switch_to "$1"
    ;;
  prune)
    prune
    ;;
  current)
    current_id
    ;;
  rollback)
    if [[ $# -eq 1 ]]; then
      switch_to "$1"
    else
      previous="$(releases | awk -v cur="$(current_id)" '$0 < cur' | tail -n 1)"
      [[ -n "$previous" ]] || { echo "no older release to roll back to" >&2; exit 1; }
      switch_to "$previous"
    fi
    ;;
  list)
    current="$(current_id)"
    releases | sort -r | while read -r id; do
      if [[ "$id" == "$current" ]]; then echo "* $id"; else echo "$id"; fi
    done
    ;;
  *) usage ;;
esac
