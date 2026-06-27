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

### ✅ `hotwire-native-bridge` — built
Create and validate **Strada / Hotwire Native bridge components** across web
(Stimulus), iOS (Swift), Android (Kotlin).
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

### Roadmap — specced, not yet built
Each is backed by a code-grounded analysis note in the app repos
(`*/wip/analysis/`); building them means turning a note into templates + scripts.

| Skill | What it would do | Source note |
|---|---|---|
| `hotwire-native-path-config` | Scaffold + validate `path_configuration.json`; the `turbo_native_app?` detection + request-variant server setup; tab-switch-via-redirect | `piazza-web/wip/analysis/05`, `piazza-ios/wip/analysis/00`, `piazza-android/wip/analysis/00` |
| `rails-token-auth` | `AppSession` DB-backed token auth (one auth for web + Action Cable + native), `Current` attributes, the **controller-concern test harness** | `piazza-web/wip/analysis/06` |
| `turbo-streams-patterns` | The **targeted**-stream patterns: stream-inside-frame patch, custom `switch_class` action, model→Action Cable append/replace, signed per-user streams, Kredis counters (complements the morph-refresh model in `turbo-morphing`) | `piazza-web/wip/analysis/02`, `07` |
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
