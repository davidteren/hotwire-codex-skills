# hotwire-codex-skills

**An unofficial skillset inspired by [*The Rails and Hotwire Codex*](https://railsandhotwirecodex.com/)
by [Ayush Newatia](https://radioactivetoy.tech) — published with his permission.**

**Skills and runnable tools for building Rails + Hotwire apps that ship to web/PWA,
iOS, and Android.**

Extracted while working through the *Rails and Hotwire Codex* "Piazza" app and
carrying it forward across all three platforms — `piazza-web`, `piazza-ios`, and
`piazza-android`. Those implementation repos are **private**: they're a derivative
of the book's copyrighted example app, so out of respect for the author they aren't
public (build your own by following the book). Each skill captures
the knowledge a real cross-platform project forces you to learn — the contracts
between web and native, the upgrade gotchas, the security boundaries, the
conventions — and packages it as a Claude Code **skill**: a `SKILL.md`, a grounded
reference, code templates, and a **runnable checker**.

Eight skills, all built and verified.

> ### Read the book first
> These skills are a companion to — not a replacement for — **[The Rails and Hotwire
> Codex](https://railsandhotwirecodex.com/)** by **Ayush Newatia**. The book teaches
> you to build *Piazza*, a neighbourhood-marketplace app, across **web, iOS, and
> Android** with Ruby on Rails and Hotwire — authentication from scratch, Turbo,
> Turbo Native, Stimulus, Action Cable, full-text search, and more. Everything here
> assumes you understand *what* the code does and *why*; the book is where that
> understanding comes from.
>
> **[Buy it on Gumroad — $49](https://ayushn21.gumroad.com/l/railshotwirecodex)**
> (a [free 3-chapter preview](https://railsandhotwirecodex.com/) is on the book site).
> The book targets **Rails 7.1**; this toolkit carries the same app forward to
> **Rails 8**, **Turbo 8**, and **Hotwire Native 1.x** — read the book for the
> foundations, use these skills for the upgrade and the sharp edges.
>
> This project is an independent, community effort. It is **not** an official product
> of the book or its author, and reuses none of the book's text or source code.

## The skills

| Skill | Use it when | Ships |
|---|---|---|
| **hotwire-native-bridge** | adding/validating a Strada-style bridge component across web + iOS + Android | generator (3 platform halves from one name) · cross-platform contract linter |
| **rails-8-upgrade** | bumping Rails 7 → 8, or chasing an intermittent route-test flake | pre-flight audit · LazyRouteSet `draw_test_routes` flake detector + fix |
| **turbo-morphing** | adding Turbo 8 page refreshes / `broadcasts_refreshes`, or morph resets browser state | decision guide · morph-readiness checker |
| **turbo-frames-patterns** | adding a frame, driving one from an outside link/form, lazy-loading a panel, or a frame click navigates nowhere / a collection makes duplicate ids | patterns guide · dangling-target + duplicate-id linter |
| **hotwire-native-path-config** | a native screen opens with the wrong presentation, or wiring native nav | 1.x starter config · schema/footgun validator + iOS↔Android drift check |
| **rails-token-auth** | adding login, or sharing one auth across web + Action Cable + native | secure templates (no gem) · 6-point security audit |
| **turbo-streams-patterns** | live updates, custom stream actions, or private broadcasts | authorized-channel + custom-action templates · wiring/eavesdropping linter |
| **stimulus-patterns** | writing a controller, or one doesn't connect / leaks after navigation | annotated + self-wiring templates · declaration/cleanup/registration linter |

### What each checker catches (the failures that produce no error)

| Script | Flags |
|---|---|
| `hotwire-native-bridge/scripts/lint_bridge_contract.sh` | name mismatch across platforms, unregistered (invisible) component, **silently-dropped payload field**, beta-vs-1.x library drift |
| `hotwire-native-bridge/scripts/new_bridge_component.sh` | (generator) emits web/iOS/Android halves + registration steps; refuses to overwrite |
| `rails-8-upgrade/scripts/upgrade_audit.sh` | version/lock mismatch, `load_defaults` gap, pagy <6 + custom views, flaky-route usage |
| `rails-8-upgrade/scripts/lint_route_test_helper.sh` | `draw_test_routes` not materialize-before-flag, no `ensure` reset, `finalize!` dead-end, missing `reload_routes!` teardown |
| `turbo-morphing/scripts/lint_morphing.sh` | global (layout) morph, stateful widget in morph scope without a guard, async broadcast with no job backend |
| `turbo-frames-patterns/scripts/lint_turbo_frames.sh` | **dangling frame target** (link/form targets a frame id no `turbo_frame_tag`/`<turbo-frame>` defines → navigation goes nowhere), **literal frame id in a collection partial** (duplicate DOM ids — use `dom_id`); skips reserved (`_top`/`_self`) + dynamic ids |
| `hotwire-native-path-config/scripts/lint_path_config.sh` | bad regex, off-schema property/value, `presentation:"modal"` beta-ism, unanchored pattern, catch-all order; `--compare` iOS↔Android drift |
| `rails-token-auth/scripts/audit_token_auth.sh` | `find_by+authenticate` enumeration, plaintext token, plain cookie, opt-in auth, cookie-only logout, weak password |
| `turbo-streams-patterns/scripts/lint_turbo_streams.sh` | half-wired custom action, **channel that streams without authorizing** (eavesdropping), async broadcast with no job backend, **response-template `*.turbo_stream.erb` with a dangling `partial:` or an unregistered custom action** |
| `stimulus-patterns/scripts/lint_stimulus.sh` | `this.xTarget/Value/Class` not declared, `connect()` without `disconnect()` cleanup, controller missing from the manifest |

## Layout

```
skills/<name>/
  SKILL.md          # frontmatter (name + description trigger) + how to use
  references/*.md   # the contract / conventions explainer, cited to path:line
  templates/*.tmpl  # code templates (placeholder tokens like __NAME__)
  scripts/*.sh      # runnable generators + linters (plain bash; python3 for 3 of them)
```

## Using it

**As a tool** — the scripts run standalone; point them at an app repo:

```bash
# audit auth, check the bridge contract, lint Stimulus, validate a path config…
skills/rails-token-auth/scripts/audit_token_auth.sh        path/to/rails-app
skills/hotwire-native-bridge/scripts/lint_bridge_contract.sh --root path/to/workspace
skills/stimulus-patterns/scripts/lint_stimulus.sh          path/to/rails-app
skills/hotwire-native-path-config/scripts/lint_path_config.sh --compare ios.json android.json
```

Pure bash; three checkers (`lint_path_config`, `lint_stimulus`, `lint_turbo_frames`) need `python3`. Every
checker exits non-zero on findings (CI-friendly) and prints the fix or a reference
pointer.

**As a Claude Code skill** — read or invoke `skills/<name>/SKILL.md`. To make one live
in a session, copy or symlink `skills/<name>/` into `~/.claude/skills/`.

## How it's built (and why you can trust it)

- **Code-grounded.** Every reference claim traces to a `path:line` in the (private)
  Piazza implementation — no invented APIs. The deeper write-ups live in those repos'
  `wip/analysis/` notes; they stay private with the book-derived source, but each
  skill's `references/*.md` carries the distilled reasoning in full.
- **Verified both ways.** Every checker is run against the **real** Piazza code (must
  be clean / report the truth) **and** a synthetic broken case (must flag it) before
  shipping. Example: the bridge linter catches Piazza's real web→Android `icon`-drop
  and nothing else.
- **Version-current.** Targets **Hotwire Native 1.x** and **Turbo 8** (morphing,
  `broadcasts_refreshes`), with the legacy (Strada-beta / Turbo 7) mapping kept as a
  migration path.
- **Honest about limits.** The checkers are heuristic text scans, not parsers — each
  one says so in its output. A clean run is a gate, not a proof; review custom logic.
- **Security-aware.** The auth audit and the stream linter encode real
  vulnerability classes (user enumeration, plaintext tokens, broadcast eavesdropping),
  not just style.

## Acknowledgements

All credit for the underlying material goes to **[Ayush Newatia](https://radioactivetoy.tech)**,
author of **[The Rails and Hotwire Codex](https://railsandhotwirecodex.com/)**. The
*Piazza* app, its architecture, and the cross-platform approach these skills encode
are his work — this toolkit only distils and extends that into runnable, agent-usable
form. Ayush kindly gave permission to publish it. If these skills are useful to you,
the right thanks is to **[buy the book ($49)](https://ayushn21.gumroad.com/l/railshotwirecodex)**
and read it.

Ayush is also available for Ruby / Rails / Hotwire contract work — see
[radioactivetoy.tech](https://radioactivetoy.tech).

## Provenance

Built from a private Piazza implementation (a derivative of the book's example app,
kept private out of respect for the author's copyright). Skill knowledge is distilled
from these analysis notes — the notes themselves live in the private repos, but each
skill's own `references/*.md` reproduces the reasoning:

- `piazza-web/wip/analysis/` — 01 (Rails 8 upgrade + the flake), 02 (frames/streams),
  03 (Stimulus), 04 (Strada bridge contract), 05 (native variants), 06 (token auth),
  07 (realtime messaging), 08 (Turbo 8 morphing).
- `piazza-ios/wip/analysis/00`, `piazza-android/wip/analysis/00` — native architecture.

Contributing a new skill: ground it in a `path:line`, target the current framework
version (keep the legacy mapping), write a checker that's **verified clean on real
code and flags a synthetic break**, and make it name its own ceiling. One built +
verified skill beats five stubs.

## License

[MIT](./LICENSE) © David Teren. Covers this toolkit's own code (skills, checkers,
references, and site) — which reuses none of *The Rails and Hotwire Codex*'s text or
source. The book and its Piazza example app remain the copyright of Ayush Newatia.
