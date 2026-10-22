#!/usr/bin/env bash
# Tests for deploy/activate.sh. Run: bash tests/activate.test.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/deploy/activate.sh"
failures=0

new_root() {
  local root
  root="$(mktemp -d)"
  mkdir -p "$root/releases"
  for id in "$@"; do mkdir -p "$root/releases/$id"; done
  echo "$root"
}

run() { bash "$SCRIPT" "$@" >/dev/null 2>&1; }

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS $name"
  else
    echo "FAIL $name: expected [$expected], got [$actual]"
    failures=$((failures + 1))
  fi
}

releases_of() { ls "$1/releases" | tr '\n' ' ' | sed 's/ $//'; }

test_activate_points_current_relative() {
  local root; root="$(new_root R1)"
  run "$root" activate R1 || true
  check activate_points_current_relative "releases/R1" "$(readlink "$root/current" || true)"
}

test_activate_missing_release_fails() {
  local root status=0; root="$(new_root R1)"
  run "$root" activate R1 || true
  run "$root" activate NOPE || status=$?
  check activate_missing_release_fails "1 releases/R1" "$status $(readlink "$root/current" || true)"
}

test_activate_prunes_to_five() {
  local root; root="$(new_root R1 R2 R3 R4 R5 R6 R7)"
  run "$root" activate R7 || true
  check activate_prunes_to_five "R3 R4 R5 R6 R7" "$(releases_of "$root")"
}

test_prune_keeps_current() {
  local root; root="$(new_root R1 R2 R3 R4 R5 R6)"
  run "$root" rollback R1 || true
  mkdir -p "$root/releases/R7"
  run "$root" activate R1 || true
  check prune_keeps_current "releases/R1 | R1 R3 R4 R5 R6 R7" \
    "$(readlink "$root/current" || true) | $(releases_of "$root")"
}

test_rollback_goes_to_previous() {
  local root; root="$(new_root R1 R2 R3)"
  run "$root" activate R3 || true
  run "$root" rollback || true
  check rollback_goes_to_previous "releases/R2" "$(readlink "$root/current" || true)"
}

test_rollback_at_oldest_fails() {
  local root status=0; root="$(new_root R1)"
  run "$root" activate R1 || true
  run "$root" rollback || status=$?
  check rollback_at_oldest_fails "1 releases/R1" "$status $(readlink "$root/current" || true)"
}

test_list_marks_current() {
  local root; root="$(new_root R1 R2)"
  run "$root" activate R1 || true
  check list_marks_current "R2|* R1" "$(bash "$SCRIPT" "$root" list 2>/dev/null | tr '\n' '|' | sed 's/|$//')"
}

test_switch_does_not_prune() {
  local root; root="$(new_root R1 R2 R3 R4 R5 R6 R7)"
  run "$root" switch R7 || true
  check switch_does_not_prune "releases/R7 | R1 R2 R3 R4 R5 R6 R7" \
    "$(readlink "$root/current" || true) | $(releases_of "$root")"
}

test_prune_command_keeps_current() {
  local root; root="$(new_root R1 R2 R3 R4 R5 R6 R7)"
  run "$root" switch R1 || true
  run "$root" prune || true
  check prune_command_keeps_current "R1 R3 R4 R5 R6 R7" "$(releases_of "$root")"
}

test_current_prints_id() {
  local root; root="$(new_root R1 R2)"
  run "$root" switch R2 || true
  check current_prints_id "R2" "$(bash "$SCRIPT" "$root" current 2>/dev/null || true)"
}

test_activate_points_current_relative
test_activate_missing_release_fails
test_activate_prunes_to_five
test_prune_keeps_current
test_rollback_goes_to_previous
test_rollback_at_oldest_fails
test_list_marks_current
test_switch_does_not_prune
test_prune_command_keeps_current
test_current_prints_id

[[ $failures -eq 0 ]] || { echo "$failures failed"; exit 1; }
echo "all passed"
