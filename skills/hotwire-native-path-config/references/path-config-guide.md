# Hotwire Native path configuration — reference

How one Rails app drives **native** navigation (push/replace/modal, tabs, image
viewer) on iOS + Android via a JSON **path configuration**, plus the server-side
`turbo_native_app?` + request-variant setup that strips web chrome. Schema verified
against native.hotwired.dev (1.x); examples grounded in the Piazza apps.

## Contents

- The JSON schema (1.x)
- Bundled vs remote
- How Piazza wires it
- Server side: `turbo_native_app?` + request variants
- Tab switching from a server redirect
- Common footguns
- Sources

## The JSON schema (1.x)

```json
{
  "settings": { "screenshots_enabled": true },
  "rules": [
    { "patterns": ["/.*"], "properties": { "context": "default", "uri": "app://fragment/web" } },
    { "patterns": ["/new$", "/edit$"], "properties": { "context": "modal" } }
  ]
}
```

- **`settings`** — app-level sandbox (feature flags, app-wide data) read by native code.
- **`rules`** — evaluated **top to bottom; later matches override earlier**. Put the
  broadest catch-all FIRST, specific overrides BELOW.
- **`patterns`** — array of **regex** strings matched against the URL path.
- **`properties`** — the navigation/behavior config for matched paths.

### Properties

| Property | Values | Platform |
|---|---|---|
| `context` | `default`, `modal` | both |
| `presentation` | `default`, `push`, `pop`, `replace`, `replace_root`, `clear_all`, `refresh`, `none` | both |
| `pull_to_refresh_enabled` | `true` / `false` (default: Android false, iOS true) | both |
| `animated` | `true` / `false` | both |
| `uri` | deep-link to a registered destination, e.g. `app://fragment/web/modal` | **Android (required)** |
| `fallback_uri` | deep-link | Android |
| `title` | toolbar title | Android |
| `view_controller` | native VC id (needs `PathConfigurationIdentifiable`) | iOS |
| `modal_style` | `large`, `medium`, `full`, `page_sheet`, `form_sheet` | iOS |
| `modal_dismiss_gesture_enabled` | `true` / `false` | iOS |

> **Modal: `context` vs `presentation`.** In 1.x a modal is expressed with
> `"context": "modal"`. Older Strada-beta configs used `"presentation": "modal"`
> (see the Piazza iOS config) — that's legacy; prefer `context: modal`. `presentation`
> is for the navigation-stack action (replace/replace_root/etc.).

## Bundled vs remote

The config can be **bundled** in the app (Piazza does this: iOS
`Piazza/path_configuration.json`, Android `assets/json/configuration.json`) or
**loaded from a URL** the Rails app serves, so you can change native navigation
**without an app-store release** (with a bundled file as the offline fallback). For a
fast-moving app, serve it (e.g. `/configurations/ios.json`, `/configurations/android.json`)
and keep the bundled copy as fallback.

## How Piazza wires it

- iOS: `Global.swift` builds `PathConfiguration(sources: [.file(... path_configuration.json)])`;
  `RoutingController.swift` sets `session.pathConfiguration`.
- Android: `SessionNavHostFragment.kt` → `pathConfigurationLocation =
  TurboPathConfiguration.Location(assetFilePath = "json/configuration.json")`.
  (1.x renames the Turbo* types to Hotwire* — see the bridge skill's migration map.)
- Piazza's rules: auth + `/new`/`/edit`/`/contact` → modal; root + tab roots
  (`/`, `/profile`, `/my_listings`, `/saved_listings`, `/conversations`) → replace /
  replace_root (the tabs); Android adds an image-viewer rule for image URLs.

## Server side: `turbo_native_app?` + request variants

The same controllers serve web + native; the server detects native via the
User-Agent and serves trimmed markup:

```ruby
# app/controllers/concerns/set_request_variant.rb (Piazza)
def set_request_variant
  if turbo_native_app?              # provided by turbo-rails; UA contains "Turbo Native"
    request.variant = :mobile
  else
    request.variant = Browser.new(request.user_agent).device.mobile? ? :mobile : :desktop
  end
end
```

Then `_navbar.html+mobile.erb` vs `.html+desktop.erb`, and `unless turbo_native_app?`
guards hide web chrome (top nav) that the native shell replaces. `turbo_native_app?`
comes from turbo-rails (`Turbo::Native::Navigation`); it works because Hotwire Native
appends `Turbo Native` (+ `Hotwire Native`) to the WebView User-Agent.

## Tab switching from a server redirect

Native tab roots use `replace`/`replace_root`. Because the tab roots are matched by
the path config, a normal server **redirect** to a tab's URL (e.g. after an action,
redirect to `/conversations`) makes the native app **select that tab** instead of
pushing a new screen — navigation stays server-driven. Keep the tab-root patterns in
the path config in sync with the native tab bar's URLs.

## Common footguns

- **Rule order**: catch-all must be first; specific rules below override it. Reversed
  order = everything matches the catch-all.
- **Anchors**: `"/new"` matches `/renew`; use `"/new$"`. `"/conversations$"` not `"/conversations"`.
- **Android `uri` required**: every Android rule needs a `uri` pointing at a
  registered destination, or navigation falls back/breaks.
- **iOS/Android drift**: the two configs are separate files — a path handled on one
  platform but not the other navigates differently. Keep coverage aligned (the linter
  compares them).
- **Modal beta-ism**: `presentation: modal` → use `context: modal` in 1.x.

## Sources

native.hotwired.dev `/reference/path-configuration`; Piazza
`piazza-ios/Piazza/path_configuration.json`,
`piazza-android/app/src/main/assets/json/configuration.json`,
`piazza-web/app/controllers/concerns/set_request_variant.rb`. Deeper:
`piazza-web/wip/analysis/05-hotwire-native-variants.md`.
