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

### Roadmap — specced, not yet built
Each is backed by a code-grounded analysis note in the app repos
(`*/wip/analysis/`); building them means turning a note into templates + scripts.

| Skill | What it would do | Source note |
|---|---|---|
| `rails-8-upgrade` | 7→8 checklist + lints; ships the **`draw_test_routes` / LazyRouteSet** flake fix (materialize-before-flag) as a codemod; pagy-major + `load_defaults` flip guidance | `piazza-web/wip/analysis/01` |
| `hotwire-native-path-config` | Scaffold + validate `path_configuration.json`; the `turbo_native_app?` detection + request-variant server setup; tab-switch-via-redirect | `piazza-web/wip/analysis/05`, `piazza-ios/wip/analysis/00`, `piazza-android/wip/analysis/00` |
| `rails-token-auth` | `AppSession` DB-backed token auth (one auth for web + Action Cable + native), `Current` attributes, the **controller-concern test harness** | `piazza-web/wip/analysis/06` |
| `turbo-streams-patterns` | The stream-inside-frame patch, custom `switch_class` action, model→Action Cable broadcasting, signed per-user streams, Kredis counters | `piazza-web/wip/analysis/02`, `07` |
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
