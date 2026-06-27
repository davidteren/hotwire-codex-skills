#!/usr/bin/env bash
# Morph-readiness check for a Rails app using (or about to use) Turbo 8 page-refresh
# morphing. Surfaces the documented footguns: morph enabled globally, stateful
# widgets that morphing resets without a guard, and async broadcasts that need a
# job backend. Read-only.
#
# Usage:  lint_morphing.sh <rails-app-dir>     # defaults to .
# Exit:   0 = nothing to flag, 1 = advisories found, 2 = bad usage.
set -uo pipefail

APP="${1:-.}"
[ -d "$APP/app" ] || { echo "usage: $0 <rails-app-dir> (no app/ found)" >&2; exit 2; }
V="$APP/app/views"
fail=0
note() { echo "  ⚠️  $*"; fail=1; }
ok()   { echo "  ✓ $*"; }

echo "== Turbo morphing readiness: $APP =="

# 1. Is morph enabled at all, and is it GLOBAL (in a layout)?
echo "Morph opt-in —"
MORPH_HITS=$(grep -rlE 'turbo_refreshes_with|turbo-refresh-method' "$V" 2>/dev/null || true)
GLOBAL_MORPH=0
if [ -z "$MORPH_HITS" ]; then
  echo "  (no turbo_refreshes_with / turbo-refresh-method found — morphing not enabled)"
else
  for f in $MORPH_HITS; do
    if echo "$f" | grep -qE '/layouts/'; then
      GLOBAL_MORPH=1
      note "morph enabled in a LAYOUT ($f) → applies site-wide. Audit every stateful widget below before shipping (thoughtbot: 'sharp knives')."
    else
      ok "morph enabled per-view: $f"
    fi
  done
fi
echo

# 2. Stateful widgets morphing may reset, without a nearby guard.
#    Scope: if morph is GLOBAL (layout) every stateful view is in scope; if it's
#    per-view, only the opted-in files themselves are checked statically (partials
#    they render are not traced — noted below).
echo "Stateful widgets vs morph guards —"
if [ "$GLOBAL_MORPH" -eq 1 ]; then
  SCOPE=$(grep -rlE '<details( |>)|<dialog( |>)|data-controller=' "$V" 2>/dev/null || true)
else
  SCOPE="$MORPH_HITS"
fi
flagged=0
for f in $SCOPE; do
  [ -n "$f" ] || continue
  grep -qE '<details( |>)|<dialog( |>)|data-controller=' "$f" 2>/dev/null || continue
  grep -qE 'data-turbo-permanent|turbo:before-morph-(element|attribute)' "$f" && continue
  kinds=$(grep -oE '<details|<dialog|data-controller=' "$f" | sort -u | tr '\n' ' ')
  note "$f has stateful markup [$kinds] but no data-turbo-permanent / before-morph guard — morph may reset its open/scroll/JS state"
  flagged=1
done
if [ "$flagged" -eq 0 ]; then ok "no unguarded stateful widgets in morph scope (or morph not enabled)"; fi
[ "$GLOBAL_MORPH" -eq 0 ] && [ -n "$MORPH_HITS" ] && echo "  (per-view morph: partials rendered by the opted-in views are not statically traced — eyeball those too)"
echo

# 3. Broadcasting model: broadcasts_refreshes vs targeted; async needs a job backend.
echo "Broadcast model —"
if grep -rqE '\bbroadcasts_refreshes\b|broadcast_refresh' "$APP/app/models" 2>/dev/null; then
  ok "uses broadcasts_refreshes / broadcast_refresh (page-refresh model)"
  if grep -rqE 'broadcast_refresh_later|broadcasts_refreshes\b' "$APP/app/models" 2>/dev/null; then
    if grep -rqiE 'sidekiq|solid_queue|resque|good_job|delayed_job|async' "$APP/Gemfile" 2>/dev/null; then
      ok "async refresh broadcasts have a job backend"
    else
      note "async refresh broadcasts (_later / broadcasts_refreshes) but no obvious Active Job backend in Gemfile — they'll run inline/async-adapter; confirm a real queue in production"
    fi
  fi
else
  echo "  (no broadcasts_refreshes — using targeted streams or no broadcasting; both fine)"
fi
echo

if [ "$fail" -eq 0 ]; then echo "✅ no morphing advisories"; else
  echo "ℹ️  advisories above are guidance, not errors. Fix order: data-turbo-permanent →"
  echo "   turbo:before-morph-* + Stimulus → push state to server/URL. See references/morphing-guide.md"
fi
exit $fail
