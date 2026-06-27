# Turbo 8 morphing & page refreshes — reference

Verified against the Turbo handbook (`/handbook/page_refreshes`), the turbo-rails
source (`app/models/concerns/turbo/broadcastable.rb`), and the 37signals (2023),
thoughtbot (2024), and Radan Skorić (2023–2025) write-ups.

## Concepts

A **page refresh** = re-rendering the *current* URL (submit a form → redirect back to
the same page; or a broadcast tells the client to reload). With morphing enabled,
Turbo updates only the changed DOM (idiomorph) instead of replacing `<body>`,
preserving scroll/focus/screen state.

## Declarative config (in `<head>`)

| Mechanism | Meta tag | Rails helper |
|---|---|---|
| Refresh method | `<meta name="turbo-refresh-method" content="morph">` (`morph` \| `replace`=default) | `turbo_refreshes_with method: :morph` |
| Scroll | `<meta name="turbo-refresh-scroll" content="preserve">` (`preserve` \| `reset`=default) | `turbo_refreshes_with scroll: :preserve` |
| Exclude an element from morph | `data-turbo-permanent` on the element | — |
| Frame morphs on full-page refresh | `<turbo-frame id=.. refresh="morph">` | — |

Note on frames: `refresh="morph"` only morphs when the frame is reloaded **as part of
a full-page refresh** (or an explicit JS `frame.reload()`) — not when the frame
refreshes itself. Widely misread; clarified by Radan Skorić (2025).

## Broadcasting page refreshes (turbo-rails)

```ruby
# broadcasts_refreshes(stream = model_name.plural) installs:
after_create_commit  -> { broadcast_refresh_later_to(stream) }
after_update_commit  -> { broadcast_refresh_later }       # to the record's own stream
after_destroy_commit -> { broadcast_refresh }
```

Instance methods: `broadcast_refresh_to(*streamables)` / `broadcast_refresh`
(sync), `broadcast_refresh_later_to(*streamables)` / `broadcast_refresh_later`
(async via `Turbo::Streams::BroadcastJob`, carries the request id). View subscribes
with `turbo_stream_from @record` (or a collection stream). Wire payload is a single
`<turbo-stream action="refresh" method="morph" scroll="preserve"></turbo-stream>`.

Mechanics:
- **Debounce**: a burst of refresh broadcasts collapses to the last one. Different
  *models* are not aggregated — don't broadcast from a model that doesn't need to.
- **Self-dedup**: client sends `X-Turbo-Request-Id`; the refresh tag echoes it; a
  client ignores a refresh carrying an id it originated (it already has the HTML from
  its own response).
- **Async needs a job backend** (`_later` variants) — Sidekiq/SolidQueue/etc.

## Scoped morphing

`replace` and `update` stream actions also accept `method="morph"`, morphing a single
target element instead of replacing it: `turbo_stream.replace id, partial:, method: :morph`.

## Footguns + fixes

Morphing forces the DOM to match server HTML → resets browser-only state (open
`<details>`/`<dialog>`, popovers, in-element scroll, focus, JS-library DOM).

1. `data-turbo-permanent` — skip the element (but it then won't update either).
2. Veto specific changes via events + Stimulus:
   - `turbo:before-morph-element` (whole element)
   - `turbo:before-morph-attribute` (one attribute, e.g. keep `<details open>` open)
3. **Best**: store the state server-side (user-pref record, or a URL param) so the
   re-render matches the browser and morph is a no-op — bonus: it persists.

Do **not** enable `turbo_refreshes_with` in the global layout without auditing
stateful widgets (thoughtbot: "sharp knives").

## Versions

`@hotwired/turbo` 8.0.x; `turbo-rails` 2.0.23 (Jan 2025) latest at time of writing.
Morphing landed in Turbo 8.0 — any 8.x app has it.
