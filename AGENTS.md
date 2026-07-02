# AGENTS.md — hotwire-codex-skills

A suite of Claude Code **skills + tools** for Rails + Hotwire apps that target
web/PWA + iOS + Android. See **[README.md](./README.md)** for the catalog.

Unofficial skillset inspired by *[The Rails and Hotwire Codex](https://railsandhotwirecodex.com/)*
by [Ayush Newatia](https://radioactivetoy.tech), published with his permission. Not an
official product of the book; reuses none of its text or source code.

## What this is

Knowledge extracted from building the Piazza app (the *Rails and Hotwire Codex*
example) across three platforms, packaged as reusable skills. The companion app
repos hold the source + the code-grounded analysis notes this suite is distilled
from: `piazza-web`, `piazza-ios`, `piazza-android` (each has `wip/analysis/`).

## How a skill is structured

```
skills/<name>/
  SKILL.md          # YAML frontmatter: name + description (the trigger). Then usage.
  references/*.md    # the contract/conventions reference (traceable to path:line)
  templates/*.tmpl   # code templates; placeholder tokens like __COMPONENT_NAME__
  scripts/*.sh       # runnable bash (generators + linters); 3 linters also need ruby
```

## Conventions for adding/editing skills

- **Ground every claim in real code.** A reference statement should trace to a
  `path:line` in one of the app repos. No invented APIs.
- **Scripts are plain bash** (no deps beyond bash; 3 linters also require `ruby`),
  and must `set -euo pipefail` (or document why not). A generator must refuse to
  overwrite. A linter must exit non-zero on drift and **name its ceiling** (e.g.
  "heuristic scan, not a parser").
- **Verify before shipping.** Run a new linter against the real Piazza repos and
  confirm it catches the known divergence (the `nav-menu` `icon` drop) with no
  false positives. Test a generator end-to-end (dry-run + real-write + overwrite
  guard) before committing.
- **One built and verified beats five stubs.** Build a new skill on demand from its
  source analysis note — don't scaffold empty dirs.

## The built skills

All eight skills in the [README catalog](./README.md#the-skills) are fully built and
verified (each: `SKILL.md` + a code-grounded reference + templates + a runnable
checker). Example — `skills/hotwire-native-bridge/`: a Strada/Hotwire Native bridge
generator + contract linter; the linter flags Piazza's real web→Android `icon` drop
and nothing else, and the generator produces all three platform halves with a
consistent name/payload.

## Skill-lint pre-push hook

A pre-push gate (`hooks/pre-push`) runs `scripts/skill_lint.py` over every `SKILL.md` and blocks a push on
any failure — a clean-room implementation of Anthropic's Agent Skills authoring rules (frontmatter present +
kebab `name` matching the dir; `description` ≤ 1024 chars and no XML tags — write `turbo_frame_tag`, not
`<turbo-frame>`; reference files ≤ 500 lines, a `## Contents` on any > 100 lines, every reference linked from
SKILL.md by a real markdown link, links resolve). Enable once per clone:

```sh
git config core.hooksPath hooks
```

Bypass a single push with `git push --no-verify`. Run directly: `python3 scripts/skill_lint.py`.

## Docs site (GitHub Pages)

`docs/` is the landing site, served by GitHub Pages from `main` `/docs`. It's a single
static `index.html` styled with **Tailwind v4** (standalone CLI, no Node project). The
committed `docs/styles.css` is generated — do not hand-edit it. After changing
`docs/index.html` (classes) or `docs/src/input.css` (theme), rebuild:

```sh
tailwindcss -i docs/src/input.css -o docs/styles.css --minify   # tailwindcss v4.x standalone
```

`docs/.nojekyll` disables Jekyll processing. Committing the precompiled CSS (instead of
a CI Node build) keeps the repo's no-deps philosophy.

The Open Graph share image `docs/og.png` (1200x630, referenced by the `og:image` meta)
is rendered from `docs/og-card.html` — open that file in a 1200x630 viewport and
screenshot to `docs/og.png`. `og-card.html` is a design-time source (uses the Tailwind
Play CDN); it is never served as a page.
