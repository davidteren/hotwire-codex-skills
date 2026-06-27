#!/usr/bin/env bash
# Security audit for Rails session/token auth. Heuristic grep scan — flags the
# high-cost auth mistakes (user enumeration, plaintext tokens, readable cookies,
# opt-in auth, fake logout, weak passwords). Read-only.
#
# Usage:  audit_token_auth.sh <rails-app-dir>     # defaults to .
# Exit:   0 = clean, 1 = findings, 2 = bad usage.
#
# CEILING: text scan, not taint analysis. It catches the common shapes; a clean
# run is not a formal proof. Pair with a real review for anything custom.
set -uo pipefail
APP="${1:-.}"
[ -d "$APP/app" ] || { echo "usage: $0 <rails-app-dir> (no app/)" >&2; exit 2; }
M="$APP/app/models"; C="$APP/app/controllers"
fail=0
bad()  { echo "  ❌ $*"; fail=1; }
warn() { echo "  ⚠️  $*"; fail=1; }
ok()   { echo "  ✓ $*"; }
has()  { grep -rqE "$1" "$2" 2>/dev/null; }

echo "== Rails token-auth security audit: $APP =="

# 1. Timing-safe login (no user enumeration)
echo "1. Login is timing-safe —"
if has 'authenticate_by\(' "$M"; then
  ok "uses authenticate_by (timing-safe, no user-enumeration leak)"
else
  if grep -rqE 'find_by\(\s*email' "$M" "$C" 2>/dev/null && has '\.authenticate\b' "$APP/app"; then
    bad "looks like find_by(email:) + .authenticate — leaks whether an email exists via timing. Use User.authenticate_by(email:, password:)"
  else
    warn "no authenticate_by found — confirm login compares credentials in constant time (use authenticate_by)"
  fi
fi

# 2. Token hashed at rest
echo "2. Session token hashed at rest —"
if has 'has_secure_password\s+:token|has_secure_token' "$M"; then
  ok "token stored as a digest (has_secure_password :token / has_secure_token)"
elif grep -rliE 'token' "$M" 2>/dev/null | grep -q .; then
  warn "a model references a 'token' but no has_secure_password :token / has_secure_token — is it stored in PLAINTEXT? Hash it (store a digest, keep plaintext only in the cookie)."
else
  echo "  (no DB-backed token/session model detected — skipping)"
fi
# plaintext token comparison smell
if grep -rqE 'token\s*==\s|==\s*.*token\b' "$M" "$C" 2>/dev/null; then
  warn "found a '== token' comparison — secret compares should be constant-time (authenticate_token / secure_compare), not =="
fi

# 3. Confidential session cookie
echo "3. Session cookie is encrypted/signed —"
if has 'cookies\.encrypted' "$C"; then ok "session written with cookies.encrypted"
elif has 'cookies\.signed' "$C"; then ok "session written with cookies.signed (tamper-proof; not confidential)"
fi
if grep -rnE 'cookies\[[^]]*(token|session|app_session)[^]]*\]\s*=' "$C" 2>/dev/null | grep -vqE 'encrypted|signed'; then
  bad "a token/session value is written to a PLAIN cookie (readable + tamperable). Use cookies.encrypted."
elif ! has 'cookies\.(encrypted|signed)' "$C"; then
  warn "no cookies.encrypted/.signed found — confirm the session isn't stored in a plain cookie"
fi

# 4. Secure by default (auth required unless opted out)
echo "4. Authentication is secure-by-default —"
AC="$C/application_controller.rb"
if [ -f "$AC" ] && grep -qE 'before_action :authenticate|include Authenticate' "$AC"; then
  ok "ApplicationController enforces authentication globally"
  has 'skip_authentication|skip_before_action :authenticate|allow_unauthenticated' "$C" \
    && ok "public actions opt OUT explicitly (skip_authentication)" \
    || warn "no skip_authentication usage — confirm public pages are intended to require login"
else
  warn "ApplicationController doesn't appear to enforce auth globally — is auth opt-IN per controller? (a forgotten controller becomes public). Prefer a global before_action with explicit skips."
fi

# 5. Real logout (server-side revocation)
echo "5. Logout revokes server-side —"
if grep -rqE 'def log_out|def destroy' "$C" 2>/dev/null && grep -rqE 'app_session.*\.destroy|session.*\.destroy|\.sessions.*destroy' "$C" "$M" 2>/dev/null; then
  ok "logout destroys the server-side session record (token is revoked, not just the cookie)"
else
  warn "couldn't confirm logout destroys the server session — clearing only the cookie leaves the token usable if replayed. Destroy the AppSession."
fi

# 6. Strong password storage
echo "6. Password storage —"
has 'has_secure_password\b' "$M" && ok "has_secure_password (bcrypt)" || warn "no has_secure_password found — how are passwords hashed?"
has 'length:\s*\{\s*minimum' "$M" && ok "password length validation present" || warn "no password length validation found — add a minimum length"

echo
if [ "$fail" -eq 0 ]; then echo "✅ no auth findings (heuristic — still review custom logic)"; else echo "❌ auth findings above — see references/token-auth-guide.md"; fi
exit $fail
