# Stimulus patterns — reference

The conventions that keep Stimulus controllers small, Turbo-safe, and server-driven.
Grounded in the Piazza controllers (`piazza-web/wip/analysis/03`).

## House style

- **Small, single-purpose controllers.** Piazza's `modal` (one `close`), `navbar`
  (one `toggle`), `remove-element` (one `remove`) are a few lines each. Prefer many
  tiny controllers over one big one.
- **State lives in the DOM; behavior reacts to it.** Push config from the server via
  the Values/Classes API instead of hardcoding it in JS.
- **Turbo-safe by construction.** Controllers connect/disconnect as Turbo swaps the
  DOM — wire via the lifecycle, and clean up anything you set up.

## Pattern 1 — target-connected self-wiring

When elements arrive later (a Turbo Stream append, a frame load), don't re-query in
`connect()` — use the **`xTargetConnected(target)`** callback, which fires per element
as each connects. Piazza's `messages` scrolls to the bottom and styles each new
message as it streams in:

```js
static targets = [ "message" ]
static values  = { recipient: String }
static classes = [ "sender" ]

messageTargetConnected(target) {
  this.scrollToBottom()
  if (target.dataset.from == this.recipientValue) {
    target.classList.add(...this.senderClasses)
  }
}
```

## Pattern 2 — Values + Classes API (config from the server)

Pass data and CSS class names from ERB into JS rather than hardcoding:
- `static values = { recipient: String, blobUrlTemplate: String }` →
  `this.recipientValue`, set via `data-<controller>-recipient-value="..."`.
- `static classes = [ "sender" ]` → `this.senderClasses` (an array), set via
  `data-<controller>-sender-class="has-background-primary..."`. The CSS lives in the
  template; the controller stays style-agnostic.

## Pattern 3 — state machine, delegate the plumbing

A controller can be a small state machine over the DOM while a plain helper object
does the heavy lifting. Piazza's `image-upload` has `setState("no_image" | "uploading"
| "image_set")` toggling `is-hidden` on targets, and delegates the Active Storage
direct-upload to a plain `FileUpload` helper that calls back
(`fileUploadDidStart`, `setFileUploadProgress`, `fileUploadDidComplete`). Keep
SDK/transport plumbing out of the controller.

## Pattern 4 — clone a server-rendered `<template>`

To add repeated markup without building HTML in JS, render a `<template>` on the
server and clone it, swapping a placeholder. Piazza's `tags`:

```js
static targets = [ "template", "container", "input" ]
addTag() {
  const html = this.templateTarget.innerHTML.replace(/{value}/g, this.inputTarget?.value)
  this.containerTarget.insertAdjacentHTML("beforeend", html)
  this.inputTarget.value = null
}
```
The markup stays in the view; the controller just stamps it.

## Pattern 5 — clean up in disconnect()

Anything you set up in `connect()` that Stimulus doesn't manage for you —
`addEventListener` on `window`/`document`, `setInterval`/`setTimeout`, a
`MutationObserver`, or native UI you rendered — **must be undone in `disconnect()`**,
or it leaks and double-fires after Turbo navigation. Piazza's `bridge--nav-menu`
sends a `disconnect` message so the native side removes its menu items (otherwise they
stack up on every navigation). Listeners wired via `data-action` are auto-managed —
manual ones are not.

## Conventions

- Use `data-action` for events where you can (auto cleanup) over manual listeners.
- Register controllers: the manifest `index.js` (`bin/rails
  stimulus:manifest:update`) or `stimulus-loading` eager load — a controller that
  isn't registered never connects.
- Bridge (Hotwire Native) controllers live under `controllers/bridge/` → identifier
  `bridge--name` (see the `hotwire-native-bridge` skill).

## Sources

`piazza-web/app/javascript/controllers/` (`messages`, `image_upload`, `tags`,
`navbar`, `modal`, `remove_element`, `bridge/nav_menu`); analysis note 03.
