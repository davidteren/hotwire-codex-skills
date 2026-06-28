#!/usr/bin/env bash
# Lint targeted Turbo Streams wiring in a Rails app. Catches the failure classes that
# produce no error: a custom stream action wired on only one side, a channel that
# streams without authorizing the subscriber (broadcast eavesdropping), and async
# broadcasts with no job backend. Read-only.
#
# Usage:  lint_turbo_streams.sh <rails-app-dir>     # defaults to .
# Exit:   0 = clean, 1 = findings, 2 = bad usage.
# CEILING: grep heuristics, not a parser. Conservative; review custom channels.
set -uo pipefail
APP="${1:-.}"
[ -d "$APP/app" ] || { echo "usage: $0 <rails-app-dir> (no app/)" >&2; exit 2; }
JS="$APP/app/javascript"; CH="$APP/app/channels"
fail=0
warn() { echo "  ⚠️  $*"; fail=1; }
bad()  { echo "  ❌ $*"; fail=1; }
ok()   { echo "  ✓ $*"; }

echo "== Turbo Streams wiring: $APP =="

# 1. Custom stream action parity (JS StreamActions.X <-> Ruby turbo_stream_action_tag(:X))
echo "1. Custom stream action parity —"
JS_ACTIONS=$(grep -rhoE 'StreamActions\.[A-Za-z0-9_]+\s*=' "$JS" 2>/dev/null | grep -oE '\.[A-Za-z0-9_]+' | tr -d '.= ' | sort -u)
# Ruby actions = the methods defined in modules prepended onto the TagBuilder (the
# registration pattern), which handles multi-line turbo_stream_action_tag calls.
TAGBUILDER_FILES=$(grep -rlE 'Turbo::Streams::TagBuilder\.prepend' "$APP/app" 2>/dev/null || true)
RB_ACTIONS=$( [ -n "$TAGBUILDER_FILES" ] && grep -hoE '^[[:space:]]*def [a-z_][A-Za-z0-9_]*' $TAGBUILDER_FILES 2>/dev/null | awk '{print $2}' | sort -u )
# fallback: same-line turbo_stream_action_tag(:name) anywhere
RB_ACTIONS=$(printf '%s\n%s\n' "$RB_ACTIONS" "$(grep -rhoE 'turbo_stream_action_tag\([[:space:]]*:[A-Za-z0-9_]+' "$APP/app" 2>/dev/null | grep -oE ':[A-Za-z0-9_]+' | tr -d ':')" | grep -v '^$' | sort -u)
if [ -z "$JS_ACTIONS" ] && [ -z "$RB_ACTIONS" ]; then
  echo "  (no custom stream actions found)"
else
  echo "  js: $(echo "$JS_ACTIONS" | tr '\n' ' ')"
  echo "  rb: $(echo "$RB_ACTIONS" | tr '\n' ' ')"
  for a in $JS_ACTIONS; do echo "$RB_ACTIONS" | grep -qx "$a" || warn "JS action '$a' has no Ruby helper (turbo_stream_action_tag :$a) — server can't emit it"; done
  for a in $RB_ACTIONS; do echo "$JS_ACTIONS" | grep -qx "$a" || warn "Ruby action '$a' has no JS StreamActions.$a — client silently ignores the tag"; done
  [ "$fail" -eq 0 ] && ok "all custom actions wired on both sides"
  # the Ruby side must be registered onto the TagBuilder
  [ -n "$RB_ACTIONS" ] && { grep -rqE 'Turbo::Streams::TagBuilder\.prepend' "$APP/app" || warn "custom Ruby actions defined but not registered via Turbo::Streams::TagBuilder.prepend(...)"; }
fi
echo

# 2. Channel stream authorization (eavesdropping boundary)
echo "2. Channel stream authorization —"
CHANS=$(grep -rlE 'ApplicationCable::Channel' "$CH" 2>/dev/null | grep -E '\.rb$' || true)
if [ -z "$CHANS" ]; then echo "  (no custom Action Cable channels)"; else
  for c in $CHANS; do
    base=$(basename "$c")
    grep -qE '\bstream_(from|for)\b' "$c" || { ok "$base does not call stream_from/for (nothing to authorize)"; continue; }
    # authorized if it rejects, branches on an auth predicate, or verifies the name
    if grep -qE '\breject\b' "$c" && grep -qE 'verified_stream_name_from_params|\bshow\?|authorized\?|accessible|can_|policy|current_user|owner' "$c"; then
      ok "$base authorizes the subscriber before streaming (guard + reject)"
    elif grep -qE '\breject\b' "$c"; then
      warn "$base calls reject but no obvious authorization predicate — confirm it actually checks ownership"
    else
      bad "$base calls stream_from/for with NO reject/authorization — any signed name can subscribe (broadcast eavesdropping). Authorize the subscriber and reject() otherwise."
    fi
  done
fi
echo

# 3. Async broadcasts need a job backend
echo "3. Async broadcasts have a job backend —"
if grep -rqE 'broadcast_[a-z_]*_later' "$APP/app" 2>/dev/null; then
  if grep -rqiE 'sidekiq|solid_queue|resque|good_job|delayed_job' "$APP/Gemfile" 2>/dev/null; then
    ok "broadcast_*_later present and a job backend is in the Gemfile"
  else
    warn "broadcast_*_later present but no obvious Active Job backend in Gemfile — confirm a real queue in production (else it runs on the async/inline adapter)"
  fi
else
  echo "  (no broadcast_*_later usage)"
fi
echo

# 4. Response-stream templates (controller-rendered turbo_stream — the non-broadcast path)
echo "4. Response-stream templates (controller-rendered) —"
TS_TEMPLATES=$(find "$APP/app/views" -name '*.turbo_stream.erb' 2>/dev/null)
if [ -z "$TS_TEMPLATES" ]; then
  echo "  (no controller-response *.turbo_stream.erb templates)"
else
  echo "  $(echo "$TS_TEMPLATES" | grep -c .) response template(s)"
  STD='append|prepend|replace|update|remove|before|after|replace_all|morph|refresh|action'
  # 4a. Dangling partial: a literal `partial: "dir/name"` (slash-pathed → resolvable from the
  #     views root) that maps to no file → ActionView::MissingTemplate when that stream renders.
  resp=0
  PARTIAL_REFS=$(grep -rhoE "partial:[[:space:]]*[\"'][^\"']+[\"']" $TS_TEMPLATES 2>/dev/null \
                 | grep -oE "[\"'][^\"']+[\"']" | tr -d "\"'" | sort -u)
  for p in $PARTIAL_REFS; do
    case "$p" in */*) : ;; *) continue ;; esac          # bare name → relative to template dir, skip (ceiling)
    case "$p" in *'#{'*|*'<%'*) continue ;; esac          # dynamic path, skip
    dir=$(dirname "$p"); base=$(basename "$p")
    ls "$APP/app/views/$dir/_$base".* >/dev/null 2>&1 || {
      bad "partial \"$p\" in a turbo_stream template resolves to no file (app/views/$dir/_$base.*) — ActionView::MissingTemplate when that stream renders"; resp=1; }
  done
  # 4b. Custom action used in a response template but not registered client-side (parity, response side).
  TS_ACTIONS=$(grep -rhoE 'turbo_stream\.[a-z_][A-Za-z0-9_]*' $TS_TEMPLATES 2>/dev/null | sed 's/turbo_stream\.//' | sort -u)
  for a in $TS_ACTIONS; do
    echo "$a" | grep -qE "^($STD)$" && continue
    echo "$JS_ACTIONS" | grep -qx "$a" || { warn "response template uses custom turbo_stream.$a but no JS StreamActions.$a — client silently ignores it"; resp=1; }
  done
  [ "$resp" -eq 0 ] && ok "response templates: literal partials resolve, custom actions registered"
  echo "  note: bare (no-slash) partials, dynamic render targets, and target-id existence aren't resolved here — verify those by hand."
fi
echo

if [ "$fail" -eq 0 ]; then echo "✅ Turbo Streams wiring OK"; else echo "❌ Turbo Streams findings above — see references/turbo-streams-guide.md"; fi
exit $fail
