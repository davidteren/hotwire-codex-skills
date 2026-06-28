# AGENTS.md — hotwire-rails-toolkit

A suite of Claude Code **skills + tools** for Rails + Hotwire apps that target
web/PWA + iOS + Android. See **[README.md](./README.md)** for the catalog.

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
  scripts/*.sh       # runnable, dependency-free bash (generators + linters)
```

## Conventions for adding/editing skills

- **Ground every claim in real code.** A reference statement should trace to a
  `path:line` in one of the app repos. No invented APIs.
- **Scripts are plain bash, no deps**, and must `set -euo pipefail` (or document
  why not). A generator must refuse to overwrite. A linter must exit non-zero on
  drift and **name its ceiling** (e.g. "heuristic scan, not a parser").
- **Verify before shipping.** Run a new linter against the real Piazza repos and
  confirm it catches the known divergence (the `nav-menu` `icon` drop) with no
  false positives. Test a generator end-to-end (dry-run + real-write + overwrite
  guard) before committing.
- **One built and verified beats five stubs.** The README roadmap lists candidates;
  build them on demand from their source analysis note — don't scaffold empty dirs.

## The built skill

`skills/hotwire-native-bridge/` — Strada bridge component generator + contract
linter. Validated: the linter flags Piazza's real web→Android `icon` drop and
nothing else; the generator produces all three halves with consistent name/payload.

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
