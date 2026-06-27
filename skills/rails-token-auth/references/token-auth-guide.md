# Rails token-backed session auth — reference

A DB-backed, revocable session model (`AppSession`) that authenticates web **and**
native (Hotwire Native) clients with one mechanism, plus `Current` attributes and
secure-by-default controller concerns. Distilled from the Piazza app
(`piazza-web/wip/analysis/06-auth-appsession-and-concern-testing.md`).

## Why not just the Rails `session`?

The plain cookie `session` is fine for web, but a **DB-backed token session** buys:
- **One auth for web + Action Cable + native.** The native apps store a cookie (or
  could send a header) carrying the same token; the same code authenticates all three.
- **Server-side revocation.** Logging out (or an admin kicking a device) **destroys
  the `AppSession` row** — the token is dead immediately, unlike a stateless JWT.
- **Per-device sessions.** A user has many `app_sessions`; you can list/revoke them.

## The pieces

### 1. `AppSession` — the session record
- `belongs_to :user`; a row per login/device.
- **The token is hashed at rest.** `has_secure_password :token, validations: false`
  stores a **bcrypt digest** in `token_digest`; the plaintext token is generated once
  (`generate_unique_secure_token`) and returned only to put in the cookie. A DB leak
  never exposes usable tokens.
- `to_h` → `{ user_id:, app_session: id, token: }` — the trio stored in the cookie.

### 2. `User::Authentication` (model concern)
- `has_secure_password` for the password (bcrypt) + a length validation.
- `create_app_session(email:, password:)` uses **`User.authenticate_by(email:,
  password:)`** — the Rails 7.1+ helper that is **timing-safe** (no user-enumeration
  leak: it does the bcrypt work whether or not the email exists). Then
  `user.app_sessions.create`.
- `authenticate_app_session(id, token)` → `app_sessions.find(id).authenticate_token(token)`
  (the `has_secure_password :token` comparator — constant-time bcrypt compare).

### 3. `Current` (request-scoped state)
```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :app_session, :organization
end
```
Set per request; auto-reset between requests. Avoids threading `current_user` everywhere.

### 4. `Authenticate` (controller concern) — secure by default
- `before_action :authenticate` then `before_action :require_login, unless: :logged_in?`
  in `included` → **every controller requires login unless it opts out.**
- Class methods to opt out *explicitly*: `skip_authentication(only:)` (public pages)
  and `allow_unauthenticated(only:)` (runs `authenticate` but doesn't force login).
- `log_in(app_session)` → `cookies.encrypted.permanent[:app_session] = { value: app_session.to_h }`
  (**encrypted** cookie — tamper-proof + confidential).
- `log_out` → `Current.app_session&.destroy` (server-side revocation).
- `authenticate` reads the encrypted cookie, pattern-matches `{user_id, app_session,
  token}`, finds the user, and verifies via `authenticate_app_session`; any mismatch →
  `nil` (anonymous).

### 5. `SessionsController`
- `skip_authentication only: [:new, :create]`.
- `create` → `create_app_session` → `log_in` → `recede_or_redirect_to root_path,
  status: :see_other` (Turbo-friendly). Failure → `render :new, status:
  :unprocessable_entity`.
- `destroy` → `log_out`.

## Security properties (the audit checks these)

| Property | Why | How |
|---|---|---|
| Timing-safe login | no user-enumeration via response timing | `User.authenticate_by(...)`, **not** `find_by(email:)&.authenticate` |
| Token hashed at rest | DB leak ≠ session takeover | `has_secure_password :token` (digest column) |
| Confidential cookie | tamper-proof + can't read token | `cookies.encrypted[...]`, not plain `cookies[...]` |
| Secure by default | a forgotten controller isn't accidentally public | global `before_action :authenticate`; opt-out via `skip_*` |
| Real logout | revoke server-side, not just clear cookie | `log_out` destroys the `AppSession` |
| Strong password | resist brute force | `has_secure_password` + length validation |

Anti-pattern to avoid: `user = User.find_by(email: ...); user&.authenticate(password)`
— leaks whether an email exists via timing/branching. Use `authenticate_by`.

## Testing controller concerns in isolation

The auth concerns are tested with a **test harness**: an anonymous
`TestController < ActionController::Base` that `include`s the concern, with routes
drawn at runtime via `draw_test_routes`. This exercises `skip_authentication` /
`allow_unauthenticated` and the redirect/render behavior without a real controller.
See the `rails-8-upgrade` skill for the Rails 8-safe `draw_test_routes` helper (it
has a LazyRouteSet flake you must avoid), and
`piazza-web/test/controllers/concerns/authenticate_test.rb` for the worked example.

## Sources

`piazza-web` `app/models/app_session.rb`, `app/models/user/authentication.rb`,
`app/models/current.rb`, `app/controllers/concerns/authenticate.rb`,
`app/controllers/sessions_controller.rb`; analysis note 06. `authenticate_by` /
`has_secure_password :token` are stock Rails (7.1+).
