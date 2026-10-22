#!/usr/bin/env bash
# Static checks for site/. Run: bash tests/site.test.sh
set -uo pipefail

SITE="$(cd "$(dirname "$0")/.." && pwd)/site"
PAGE="$SITE/index.html"
failures=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; failures=$((failures + 1)); }

[[ -f "$PAGE" ]] || { fail page_exists "$PAGE missing"; echo "1 failed"; exit 1; }

# Sections present, in order.
order="$(grep -o 'id="\(programs\|fees\|apply\|scholarships\|contact\)"' "$PAGE" | tr '\n' ' ')"
if [[ "$order" == 'id="programs" id="fees" id="apply" id="scholarships" id="contact" ' ]]; then
  pass site_has_sections
else
  fail site_has_sections "got: $order"
fi

required=(
  https://ait.ac.th/faculty/faculty-of-advanced-science-and-technology/
  https://ait.ac.th/program/computer-science-and-communication-technology-csct/
  https://ait.ac.th/program/industrial-systems-engineering-ise/
  https://ait.ac.th/program/remote-sensing-and-geographic-information-systems-rs-gis/
  https://ait.ac.th/tuition-and-fees/
  https://ait.ac.th/eligibility/
  https://ait.ac.th/apply-online/
  https://ait.ac.th/financial/royal-thai-government-scholarships/
  https://ait.ac.th/financial/rtg-fellowships-ph-d-to-support-the-asian-innovation-hub/
  https://ait.ac.th/financial/rtg-fellowships/
  https://ait.ac.th/financial/asian-development-bank-japan-scholarship-program-adb-jsp/
  https://ait.ac.th/financial/mitani-trading-thailand-co-ltd-masters-scholarship-with-job-offer/
  https://ait.ac.th/financial/ais-scholarship/
  https://ait.ac.th/financial/chinese-government-scholarships/
  https://ait.ac.th/financial/japanese-government-scholarships/
  https://ait.ac.th/financial/ait-scholarships/
  https://ait.ac.th/financial-aid/
  mailto:fast_admissions@ait.ac.th
  https://www.facebook.com/fast.ait
  https://fast.ait.ac.th/info/
)
missing=()
for url in "${required[@]}"; do grep -qF "href=\"$url\"" "$PAGE" || missing+=("$url"); done
[[ ${#missing[@]} -eq 0 ]] && pass site_has_required_links || fail site_has_required_links "${missing[*]}"

scholarships="$(grep -c 'class="scholarship"' "$PAGE")"
applies="$(grep -c 'href="https://ait.ac.th/apply-online/"' "$PAGE")"
[[ "$applies" == 2 ]] && pass apply_now_in_hero_and_section || fail apply_now_in_hero_and_section "got $applies"

[[ "$scholarships" == 10 ]] && pass ten_scholarships || fail ten_scholarships "got $scholarships"

# Behind the proxy the page lives at /admissions/, so root-absolute URLs break.
absolute="$(grep -rnoE '(src|href)="/[^/]' "$SITE" || true)"
[[ -z "$absolute" ]] && pass site_uses_relative_urls || fail site_uses_relative_urls "$absolute"

unsafe="$(grep -o '<a [^>]*target="_blank"[^>]*>' "$PAGE" | grep -v 'rel="noopener' || true)"
[[ -z "$unsafe" ]] && pass external_links_are_safe || fail external_links_are_safe "$unsafe"

broken=()
for ref in $(grep -oE '(src|href)="[^":#]+"' "$PAGE" | sed -E 's/^(src|href)="//; s/"$//'); do
  [[ -f "$SITE/$ref" ]] || broken+=("$ref")
done
[[ ${#broken[@]} -eq 0 ]] && pass assets_exist || fail assets_exist "${broken[*]}"

[[ $failures -eq 0 ]] || { echo "$failures failed"; exit 1; }
echo "all passed"
