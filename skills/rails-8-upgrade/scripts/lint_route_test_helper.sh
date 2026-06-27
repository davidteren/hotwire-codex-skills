#!/usr/bin/env bash
# Detect the Rails 7->8 flaky-route-test anti-pattern: a test helper that appends
# routes by toggling disable_clear_and_finalize without (a) materializing the
# LazyRouteSet first, (b) resetting the flag, or (c) pairing every draw with a
# reload_routes! teardown. This bug is FLAKY under parallel test runs — it passes
# most single runs — so static detection is worth a lot.
#
# Usage:  lint_route_test_helper.sh <rails-app-dir>      # defaults to .
# Exit:   0 = clean (or pattern not present), 1 = problems found, 2 = bad usage.
set -uo pipefail

APP="${1:-.}"
[ -d "$APP" ] || { echo "usage: $0 <rails-app-dir>" >&2; exit 2; }
TESTDIR="$APP/test"; [ -d "$TESTDIR" ] || TESTDIR="$APP/spec"
[ -d "$TESTDIR" ] || { echo "no test/ or spec/ dir under $APP" >&2; exit 2; }

fail=0
warn() { echo "  ⚠️  $*"; fail=1; }
ok()   { echo "  ✓ $*"; }

# Find the helper file(s) that toggle the flag.
HELPERS=$(grep -rlE 'disable_clear_and_finalize[[:space:]]*=[[:space:]]*true' "$TESTDIR" 2>/dev/null || true)
if [ -z "$HELPERS" ]; then
  echo "No route-appending helper (disable_clear_and_finalize = true) found — nothing to check."
  exit 0
fi

for f in $HELPERS; do
  echo "Checking $f"
  body=$(cat "$f")

  # (a) materialize-before-flag: reload_routes_unless_loaded must appear BEFORE the
  # first `disable_clear_and_finalize = true` (line order).
  mat_line=$(grep -nE 'reload_routes_unless_loaded' "$f" | head -1 | cut -d: -f1)
  flag_line=$(grep -nE 'disable_clear_and_finalize[[:space:]]*=[[:space:]]*true' "$f" | head -1 | cut -d: -f1)
  if [ -z "$mat_line" ]; then
    warn "missing reload_routes_unless_loaded — app routes may not materialize before the flag is set (LazyRouteSet drops named helpers; flaky)"
  elif [ -n "$flag_line" ] && [ "$mat_line" -gt "$flag_line" ]; then
    warn "reload_routes_unless_loaded (line $mat_line) comes AFTER the flag is set (line $flag_line) — must be BEFORE"
  else
    ok "materializes routes before setting the flag"
  fi

  # (b) flag reset: must set disable_clear_and_finalize = false somewhere in the helper.
  if echo "$body" | grep -qE 'disable_clear_and_finalize[[:space:]]*=[[:space:]]*false'; then
    if grep -qE '^\s*ensure\b' "$f"; then ok "resets the flag (ensure block present)"; else
      warn "resets the flag but not in an ensure — a raising draw would leave it stuck true"; fi
  else
    warn "never resets disable_clear_and_finalize = false → stuck true process-wide; later reload_routes! stops clearing (flaky helper drops named routes for other tests)"
  fi

  # warn on the known dead-end
  if grep -qE '\.finalize!\b' "$f" && grep -qE '^\s*ensure\b' "$f"; then
    warn "calls finalize! (likely in ensure) — known dead end; it re-evals appended blocks without rebuilding url helpers. Remove it; rely on materialize-before-flag instead."
  fi
done

# (c) every draw_test_routes caller needs a reload_routes! teardown.
echo "Checking draw_test_routes callers have a reload_routes! teardown —"
CALLERS=$(grep -rlE '\bdraw_test_routes\b' "$TESTDIR" 2>/dev/null | grep -vE 'support/|routes_helper' || true)
if [ -z "$CALLERS" ]; then echo "  (no caller test files found)"; else
  for c in $CALLERS; do
    if grep -qF 'reload_routes!' "$c"; then ok "$(basename "$c") has reload_routes!"; else
      warn "$(basename "$c") calls draw_test_routes but has NO reload_routes! teardown — leaks test routes / stuck state into the next test"; fi
  done
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "✅ route test helper is Rails 8-safe"
else
  echo "❌ flaky-route-test risk found. Apply the fix in templates/routes_helper.rb.fixed:"
  echo "   1) reload_routes_unless_loaded BEFORE setting the flag"
  echo "   2) reset disable_clear_and_finalize=false in an ensure block"
  echo "   3) reload_routes! forces the flag false before reloading"
  echo "   4) add teardown { reload_routes! } to each caller above"
fi
exit $fail
