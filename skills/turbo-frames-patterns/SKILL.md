---
name: turbo-frames-patterns
description: Scope navigation to a region with Turbo Frames correctly, and catch the wiring mistakes that fail silently. Use when adding a turbo_frame_tag (a turbo-frame element), driving a frame from an outside link/form, lazy-loading a panel (src + loading: :lazy), inline-editing a row, or debugging a frame that does nothing / a click that navigates nowhere / a filter form that loses focus / duplicate frame ids from a collection. The region-scoped complement to targeted streams (turbo-streams-patterns) and morph refreshes (turbo-morphing).
---

# Turbo Frames

Frames scope navigation to a region: a click or form submit inside a `<turbo-frame>` is
captured by Turbo and only that frame updates. The failures are quiet — a mistargeted or
missing frame produces no error, just navigation that goes nowhere. Full patterns:
[`references/turbo-frames-guide.md`](references/turbo-frames-guide.md).

## When to use

- Adding a frame (`turbo_frame_tag "id"` / `<turbo-frame id="id">`).
- Driving a frame from **outside** (`data: { turbo_frame: "id" }`) — e.g. a filter bar
  above a list.
- Lazy-loading a panel (`src:` + `loading: :lazy`).
- Inline-editing one record (a per-row `turbo_frame_tag dom_id(record)`).
- Debugging: a frame that does nothing, a click that navigates nowhere, a filter form
  that loses focus on each keystroke, or duplicate ids from a collection partial.

## The patterns (and their footguns)

1. **Target must resolve** — a link targeting `turbo_frame: "x"` needs a
   `turbo_frame_tag "x"` in the response (and your views), or the click silently does
   nothing. Use `_top` to break out to a full-page navigation (the common case for row
   links). *(linted)*
2. **Collection partials use `dom_id(record)`** — a literal `turbo_frame_tag "card"` in a
   per-row partial stamps the same id on every row → duplicate DOM ids, only the first
   updates. *(linted)*
3. **Frame request variant** — render the lean `show.html+turbo_frame.erb` for frame
   requests (`turbo_frame_request?`) instead of re-rendering the whole layout.
4. **`turbo_action: "advance"`** — frame navigations don't change the URL by default;
   promote tab/list/filter frames so reload/back/forward work.
5. **Filter/search forms go OUTSIDE the frame they target** — a form inside the frame
   replaces itself (and the focused input) on every submit.
6. **Lazy frames** — `src:` + `loading: :lazy` defer content; the `src` response must
   contain a matching `<turbo-frame id>` or the frame stays empty.

Patterns 3–6 aren't checker-able with low false positives — see the reference.

## Lint an app

```bash
scripts/lint_turbo_frames.sh path/to/rails-app
```

Flags (HIGH confidence, literal ids only): a **dangling frame target** — a link/form
targets a frame id with no `turbo_frame_tag` / `<turbo-frame id>` defined in any view
(navigation goes nowhere); a **literal frame id inside a collection partial** — duplicate
DOM ids (use `dom_id`). Reserved targets (`_top`/`_self`) and dynamic ids
(`dom_id(...)`, interpolation, `<%= %>`) are never flagged — when either side is dynamic
it can't be resolved statically, so it's skipped and reported as such. Heuristic regex
scan (needs `python3`), not an ERB/HTML parser — names its ceiling. Verified: clean on
miela_app (6 real frames, all targets resolve, collection partials use `dom_id`), flags a
synthetic dangling-target + duplicate-id app.
