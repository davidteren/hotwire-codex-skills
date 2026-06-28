# Turbo Frames — reference

Frames scope navigation to a region of the page: a click or form submit inside a
`<turbo-frame>` is captured by Turbo, fetched, and the matching frame in the response
replaces the current one — the rest of the page stays put. Powerful, and quiet when
wrong: a frame mismatch produces no Ruby/JS error, just navigation that goes nowhere
or content that never appears. Complements `turbo-streams-patterns` (surgical
broadcasts) and `turbo-morphing` (whole-page refresh).

## The model in one paragraph

A frame is `turbo_frame_tag "id"` (or `<turbo-frame id="id">`). Links/forms **inside**
it navigate it by default. To drive a frame from **outside**, point at it with
`data: { turbo_frame: "id" }` (or `data-turbo-frame="id"`). On navigation Turbo fetches
the URL and looks for `<turbo-frame id="id">` in the **response**; it swaps that frame's
contents in. If the response has no frame with that id, Turbo replaces the frame with
nothing and logs a console warning — but raises no server/JS error. That silent-miss is
the whole reason this skill's linter exists.

## Patterns the linter checks (the silent failures)

### 1. Every target must resolve to a defined frame
A link/form that targets `data: { turbo_frame: "post_form" }` needs a
`turbo_frame_tag "post_form"` to exist **in the response it navigates to** (and, in
practice, somewhere in your views). Typo the id, rename the frame, or forget to add it
and the click does nothing visible. The linter flags any literal target id with no
literal frame definition anywhere in `app/views`.

Reserved targets are fine and never flagged:
- `_top` — break out of the frame, navigate the whole page (the most common one;
  miela uses it on every row link/CTA so detail pages render full-page).
- `_self` — explicitly target the containing frame.

### 2. Collection partials need a dynamic frame id
A partial rendered once per row (`render partial: "...", collection:` or
`render @records`) must build its frame id from the record:

```erb
<%# _billing_code.html.erb — rendered per row %>
<%= turbo_frame_tag dom_id(billing_code) do %>   <%# post_billing_code_42, _43, ... %>
  ...
<% end %>
```

A hardcoded `turbo_frame_tag "billing_code"` in that partial stamps the **same id** on
every row — duplicate ids in the DOM, and Turbo only ever updates the first. Always
`dom_id(record)` (optionally `dom_id(record, :prefix)`) for per-row frames. The linter
flags a literal frame id inside a partial it can see is collection-rendered.

## Patterns the linter does NOT check (verify these by hand)

These are real and important but not statically decidable with low false positives, so
they live here as guidance, not as checks.

### Frame request variant — render less for a frame
A request that originates inside a frame sets `Turbo-Frame` in its headers; Rails
exposes this as `turbo_frame_request?` in the controller and a `turbo_frame` request
variant. Use it to skip the layout/chrome and render only what the frame needs:

```ruby
# controller
def show
  # turbo_frame_request? is true when the click came from inside a frame
end
```
```
app/views/posts/show.html+turbo_frame.erb   # the lean, frame-only variant
app/views/posts/show.html.erb               # the full page
```
Rails picks the `+turbo_frame` template automatically for frame requests. Without it you
re-render the whole layout into the frame and throw most of it away.

### `turbo_action: "advance"` to sync the URL
By default, navigating a frame does **not** change the browser URL — reload and you lose
the frame's state. For frames that act like real navigation (tabs, paginated lists,
filtered views), promote them:

```erb
<%= turbo_frame_tag "results", data: { turbo_action: "advance" } do %>
```
or per-link `data: { turbo_action: "advance" }`. Now the frame pushes a history entry and
the URL reflects the frame's content, so reload/back/forward work. Use `"advance"` to
push, `"replace"` to swap the current entry without adding history.

### Put filter/search forms OUTSIDE the frame they target
A search or filter form that updates a list frame must live **outside** that frame and
point into it (`data: { turbo_frame: "results" }`). If the form is inside the frame, each
submit replaces the frame — including the form and its focused input — and the user
loses focus mid-keystroke. miela follows this: the filter bar sits above the list and
targets the list frame from outside (`turbo_frame: "clients_list"`), so typing in the
filter never blows away the input.

### Lazy-loading frames (`src` + `loading: :lazy`)
A frame can defer its own content to a second request:

```erb
<%= turbo_frame_tag "metrics", src: dashboard_metrics_path, loading: :lazy do %>
  <p>Loading…</p>   <%# placeholder shown until the src resolves %>
<% end %>
```
- `src:` — Turbo fetches that URL and swaps in the matching frame from the response. The
  response **must** contain `<turbo-frame id="metrics">` or the frame stays empty.
- `loading: :lazy` — defer the fetch until the frame is visible (good for
  below-the-fold or tab-hidden content); the default (eager) fetches on load.
- Keep a placeholder in the body so there's something to show while it loads.

## Frames vs streams vs morph

| Need | Use |
|---|---|
| Scope clicks/forms to a region; lazy-load a panel; inline edit one record | **frames** (this skill) |
| Push a specific DOM change to subscribers (append a message, replace a card) | `turbo-streams-patterns` |
| Whole-page refresh that preserves scroll/focus on submit-and-redirect | `turbo-morphing` |

## Sources

Hotwire Turbo Handbook — "Decompose with Turbo Frames", "Loading Frames",
"Promoting a Frame Navigation to a Page Visit" (`turbo_action`), and the frame request
variant / `turbo_frame_request?` in the turbo-rails README. Grounded against miela_app
(`app/views/admin/*` — `clients_list`/`users_list`/`teams_list` frames driven from an
outside filter bar; `billing_codes/_billing_code.html.erb` using `dom_id`).
