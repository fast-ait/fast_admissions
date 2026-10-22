#!/usr/bin/env bash
# Smoke-check a running Admissions site container. Runs on the server.
#   smoke.sh <base-url>   e.g. smoke.sh http://localhost:8082
# Paths are root-relative: the upstream proxy strips /admissions/ before forwarding.
set -uo pipefail

base="${1:?usage: smoke.sh <base-url>}"
failures=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; failures=$((failures + 1)); }

# Prints "<status> <content-type> <cache-control>" for a GET.
probe() {
  curl -s --max-time 10 -o /dev/null -D - "$base$1" | tr -d '\r' | awk '
    NR == 1 { status = $2 }
    tolower($1) == "content-type:" { type = $2 }
    tolower($1) == "cache-control:" { $1 = ""; cache = cache $0 }
    END { print status, type, cache }'
}

expect() {
  local name="$1" path="$2" status="$3" type="${4:-}" want_cache="${5:-}"
  local got got_status got_type got_cache
  got="$(probe "$path")"
  read -r got_status got_type got_cache <<<"$got"
  [[ "$got_status" == "$status" ]] || { fail "$name" "$path status $got_status, want $status"; return; }
  [[ -z "$type" || "$got_type" == "$type"* ]] || { fail "$name" "$path type $got_type, want $type"; return; }
  [[ -z "$want_cache" || "$got_cache" == *"$want_cache"* ]] || { fail "$name" "$path cache [$got_cache], want $want_cache"; return; }
  pass "$name"
}

expect index_no_cache / 200 text/html no-cache
if curl -s --max-time 10 "$base/" | grep -q 'id="scholarships"'; then pass page_content; else fail page_content "no scholarships section"; fi
expect styles_short_cache /styles.css 200 text/css max-age=3600
expect logo_served /assets/fast-logo.png 200 image/png
expect unknown_path_shows_page /nope 200 text/html
# A redirect from nginx itself would drop the /admissions/ prefix the proxy stripped.
expect no_internal_redirect /assets 200 text/html

[[ $failures -eq 0 ]] || { echo "$failures failed"; exit 1; }
echo "all passed"
