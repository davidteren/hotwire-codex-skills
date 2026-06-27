#!/usr/bin/env bash
# Pre-flight audit for a Rails 7 -> 8 upgrade. Read-only: reports state + risks,
# changes nothing. Run from anywhere with the app dir as arg.
#
# Usage:  upgrade_audit.sh <rails-app-dir>     # defaults to .
set -uo pipefail

APP="${1:-.}"
[ -f "$APP/Gemfile" ] || { echo "no Gemfile in $APP — not a Rails app dir?" >&2; exit 2; }
say() { echo "  $*"; }
risk() { echo "  ⚠️  $*"; }

echo "== Rails 7->8 upgrade audit: $APP =="

# --- versions ---
echo "Versions —"
say "Ruby (.ruby-version): $(cat "$APP/.ruby-version" 2>/dev/null || echo '?')"
say "Gemfile ruby pin    : $(grep -E '^\s*ruby\s+["'\'']' "$APP/Gemfile" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo 'none')"
RAILS_LOCK=$(grep -A1 '^    rails ' "$APP/Gemfile.lock" 2>/dev/null | grep -oE '\([0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d '(')
say "rails (Gemfile.lock): ${RAILS_LOCK:-?}"
# warn if Gemfile.lock RUBY VERSION mismatches .ruby-version
LOCK_RUBY=$(grep -A1 'RUBY VERSION' "$APP/Gemfile.lock" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
RV=$(cat "$APP/.ruby-version" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ -n "$LOCK_RUBY" ] && [ -n "$RV" ] && [ "$LOCK_RUBY" != "$RV" ] && \
  risk "Gemfile.lock RUBY VERSION ($LOCK_RUBY) != .ruby-version ($RV) — bundle will refuse; bump both"

# --- load_defaults ---
echo "Framework defaults —"
LD=$(grep -rhoE 'config\.load_defaults\s+[0-9]+\.[0-9]+' "$APP/config/application.rb" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
say "config.load_defaults: ${LD:-not found}"
if ls "$APP"/config/initializers/new_framework_defaults_*.rb >/dev/null 2>&1; then
  say "new_framework_defaults file(s): $(ls "$APP"/config/initializers/new_framework_defaults_*.rb | xargs -n1 basename | tr '\n' ' ')"
else
  say "no new_framework_defaults_*.rb (expected if load_defaults not yet flipped)"
fi
[ -n "$LD" ] && [ -n "$RAILS_LOCK" ] && [ "${LD%%.*}" -lt "${RAILS_LOCK%%.*}" ] && \
  say "(load_defaults $LD < Rails ${RAILS_LOCK%%.*} — fine for the low-risk gem-first upgrade; flip later via new_framework_defaults)"

# --- known-risky gems ---
echo "Known-risky gems —"
gem_ver() { grep -E "^\s*gem\s+[\"']$1[\"']" "$APP/Gemfile" | head -1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1; }
PAGY=$(gem_ver pagy)
if [ -n "$PAGY" ]; then
  if [ "${PAGY%%.*}" -lt 6 ]; then
    if grep -rqE 'pagy_link_proc|pagy_t|pagy_nav' "$APP/app/views" 2>/dev/null; then
      risk "pagy $PAGY pinned <6 AND custom pagy view helpers in app/views — pagy 6+ removed pagy_link_proc/pagy_t. Bumping = template+initializer port; keep pinned or budget the rewrite."
    else
      say "pagy $PAGY (<6) — safe to bump unless you add custom nav partials"
    fi
  else say "pagy $PAGY (>=6) — ok"; fi
fi
for g in sidekiq redis kredis; do v=$(gem_ver "$g"); [ -n "$v" ] && say "$g $v"; done

# --- the flaky route-test pattern (delegate to the sibling linter if present) ---
echo "Flaky route-test pattern —"
if grep -rqE 'disable_clear_and_finalize' "$APP/test" "$APP/spec" 2>/dev/null; then
  risk "app toggles disable_clear_and_finalize in tests — run lint_route_test_helper.sh (the #1 Rails 8 test flake)"
else
  say "no disable_clear_and_finalize usage in tests"
fi

echo
echo "Next: bump rails ~> 8.x + ruby, 'bundle update', keep load_defaults as-is,"
echo "run the suite >=6x (parallel flakes hide), then flip framework defaults separately."
