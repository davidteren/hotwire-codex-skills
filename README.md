# hotwire-rails-toolkit

Reusable **skills and tools** for building **Rails + Hotwire** apps that ship to
web/PWA, **iOS**, and **Android** — extracted while implementing the *Rails and
Hotwire Codex* "Piazza" app across all three platforms
([piazza-web](https://github.com/davidteren/piazza-web),
[piazza-ios](https://github.com/davidteren/piazza-ios),
[piazza-android](https://github.com/davidteren/piazza-android)).

Each skill captures knowledge that isn't generic LLM background — the
cross-platform contracts, the upgrade gotchas, the conventions that take a real
project to discover — and packages it as a Claude Code **skill** (`SKILL.md` +
templates + runnable scripts).

## Skills

### ✅ `hotwire-native-bridge` — built (Hotwire Native 1.x)
Create and validate **Hotwire Native bridge components** (formerly Strada) across
web (Stimulus), iOS (Swift), Android (Kotlin). Templates target **Hotwire Native
1.x** (`@hotwired/hotwire-native-bridge`, `import HotwireNative`,
`dev.hotwire.core.bridge`, `Hotwire.registerBridgeComponents`); the reference maps
1.x ↔ the Strada-beta wiring the Piazza example apps still use, and the linter
reports each platform's generation.
- `scripts/new_bridge_component.sh` — generate the three platform halves from one
  component name (consistent name + payload), with the registration steps.
- `scripts/lint_bridge_contract.sh` — flag name mismatches, unregistered (invisible)
  components, and **silently-dropped payload fields** (the highest-cost bug class —
  validated by catching Piazza's real `icon`-dropped-on-Android divergence).
- `references/bridge-contract.md` — the contract + the worked `nav-menu` example.

### ✅ `rails-8-upgrade` — built
Upgrade a Rails 7 app to Rails 8 safely + catch the flake it introduces.
- `scripts/upgrade_audit.sh` — read-only pre-flight: versions (+ Gemfile.lock RUBY
  mismatch), `load_defaults` vs Rails major, known-risky gems (pagy <6 with custom
  views), and whether the test suite uses the flaky route pattern.
- `scripts/lint_route_test_helper.sh` — detects the **`draw_test_routes` /
  LazyRouteSet** parallel-test flake (materialize-before-flag, flag reset, the
  `finalize!` dead-end, missing `reload_routes!` teardowns) and prints the fix.
  Verified: clean on the fixed `piazza-web`, flags a synthetic book-original helper.
- `templates/routes_helper.rb.fixed` + `references/rails-7-to-8.md` (the checklist).

### ✅ `turbo-morphing` — built
Turbo 8 page refreshes with morphing + broadcast refreshes, done right.
- `references/morphing-guide.md` — `turbo_refreshes_with`, `data-turbo-permanent`,
  frame `refresh="morph"`, `broadcasts_refreshes` mechanics (debounce, request-id
  dedup, BroadcastJob), scoped morph, and the decision guide (morph-refresh vs
  targeted streams vs frames). Verified against the Turbo handbook + turbo-rails source.
- `scripts/lint_morphing.sh` — morph-readiness check: flags global (layout) morph,
  stateful widgets (`<details>`/`<dialog>`/Stimulus) in morph scope without a
  `data-turbo-permanent` / `before-morph` guard, and async broadcasts lacking a job
  backend. Verified: scopes correctly per-view vs global, honours guards.
- Keeps the suite current with modern Hotwire — see `piazza-web/wip/analysis/08`.

### ✅ `hotwire-native-path-config` — built
Author + validate the path configuration JSON that drives native navigation, plus
the Rails `turbo_native_app?` + request-variant setup.
- `templates/path_configuration.json.tmpl` — a 1.x starter (catch-all → tabs → modal
  → image viewer).
- `scripts/lint_path_config.sh` — schema + footgun validator (regex compile, 1.x
  property/value check, `presentation: "modal"` beta-ism, unanchored patterns,
  catch-all ordering) and an iOS↔Android `--compare` drift check. Verified: template
  clean, flags the Piazza iOS modal beta-ism, surfaces the real iOS↔Android gap
  (Android handles image URLs, iOS doesn't).
- `references/path-config-guide.md` — schema (verified against native.hotwired.dev),
  bundled-vs-remote, tab-switch-via-redirect, and the server variant setup.

### ✅ `rails-token-auth` — built
Secure DB-backed token session auth (web + Action Cable + Hotwire Native), no gem.
- `templates/` — `AppSession` (token hashed at rest), `User::Authentication`
  (`authenticate_by`), `Current`, the secure-by-default `Authenticate` concern, and
  `SessionsController`. Generic, ready to adapt.
- `scripts/audit_token_auth.sh` — security audit for the six properties (timing-safe
  login, token digest, encrypted cookie, secure-by-default, server-side logout,
  password storage). Verified: passes the secure Piazza app, flags a synthetic
  insecure one on every check.
- `references/token-auth-guide.md` — design + rationale + the anti-patterns.

### ✅ `turbo-streams-patterns` — built
The targeted-stream complement to `turbo-morphing`: model broadcasts, custom stream
actions, **authorized** stream channels, Kredis presence.
- `templates/` — a custom stream action (JS + Ruby `TagBuilder.prepend` halves) and an
  authorized channel (verify signed name → authorize → `reject`).
- `scripts/lint_turbo_streams.sh` — flags half-wired custom actions, **channels that
  `stream_from` without authorizing the subscriber** (eavesdropping, reported as an
  error), and `broadcast_*_later` without a job backend. Verified: clean on Piazza,
  flags a synthetic leaky-channel + half-wired app.
- `references/turbo-streams-guide.md` — the five patterns + the morph-vs-targeted
  decision + the stream-auth security note.

### Roadmap — specced, not yet built
Each is backed by a code-grounded analysis note in the app repos
(`*/wip/analysis/`); building them means turning a note into templates + scripts.

| Skill | What it would do | Source note |
|---|---|---|
| `stimulus-patterns` | Target-connected self-wiring, Values/Classes API, `disconnect()` cleanup, server-template cloning | `piazza-web/wip/analysis/03` |

## Layout

```
skills/<name>/
  SKILL.md            # frontmatter (name/description) + how to use
  references/*.md     # the contract / conventions explainer
  templates/*.tmpl    # code templates (placeholder tokens)
  scripts/*.sh        # runnable generators + linters (plain bash, no deps)
```

## Using a skill

These are Claude Code skills — invoked via the Skill tool (or read `SKILL.md`
directly). The scripts are plain bash and run standalone; point them at the three
app repos. To install a skill globally, copy `skills/<name>/` into
`~/.claude/skills/`.

## Philosophy

Lazy, code-grounded, honest: one skill built and **verified against real code**
before the rest are scaffolded. Every claim in a reference traces to a `path:line`
in the Piazza repos. Tools name their ceiling (the linter is a heuristic scan, not
a parser) and their upgrade path.
