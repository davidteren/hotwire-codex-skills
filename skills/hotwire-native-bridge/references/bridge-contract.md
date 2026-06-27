# The Strada bridge contract — reference

Derived from the real Piazza `nav-menu` component (the only Strada component in the
*Rails and Hotwire Codex* app). Use it as the canonical worked example.

## The three halves of `nav-menu`

| Concern | Web (Stimulus) | iOS (Swift) | Android (Kotlin) |
|---|---|---|---|
| File | `controllers/bridge/nav_menu_controller.js` | `Bridge/NavMenuComponent.swift` | `NavMenuComponent.kt` |
| Name | `static component = "nav-menu"` | `override class var name { "nav-menu" }` | `BridgeComponentFactory("nav-menu", ::NavMenuComponent)` |
| Registered in | auto (file under `controllers/bridge/`) | `BridgeComponent.allTypes` | `bridgeComponentFactories` list |
| Renders | hides web markup, sends items | right-bar `UIBarButtonItem`s | toolbar `menu` items |

## Message flow

```
web connect()                       native onReceive(event:"connect")
  this.send("connect", {items}, cb)  ──►  decode items, render native controls
                                          each control's tap →
native reply                              reply(to:"connect", ResponseData(selectedIndex))
  message.data.selectedIndex  ◄──────────
  → itemTargets[selectedIndex].click()    (web replays the click → normal navigation)

web disconnect()                     native onReceive(event:"disconnect")
  this.send("disconnect")            ──►  remove the rendered controls
```

Note the design: native does **not** navigate itself — it reports which item was
chosen and the **web replays `.click()`**, so the existing Turbo navigation/links
stay the single source of truth.

## Payload shapes (must stay in sync)

Web sends per item: `{ title, icon, index }` (`nav_menu_controller.js`).

```swift
// iOS — decodes all three
struct MenuItem: Decodable { let title: String; let index: Int; let icon: String? }
struct ResponseData: Encodable { let selectedIndex: Int }
```

```kotlin
// Android — NOTE: no `icon` field → the icon web sends is silently dropped
@Serializable data class MenuItem(@SerialName("title") val title: String,
                                  @SerialName("index") val index: Int)
@Serializable data class ResponseData(@SerialName("selectedIndex") val selectedIndex: Int)
```

This `icon` mismatch is the textbook example of the silent-drop failure class —
exactly what `lint_bridge_contract.sh` flags.

## Gotcha catalogue

- **Name typo / missing registration → invisible component.** No error; it just
  doesn't connect. (iOS: not in `allTypes`; Android: not in `bridgeComponentFactories`.)
- **Payload key added on web but not on a native struct → silently dropped.** JSON
  decoding ignores unknown keys. Add to Swift `Decodable` *and* Kotlin
  `@Serializable` together.
- **`index` is the round-trip key, not identity.** Web sends `index`; native
  replies `selectedIndex`; web does `itemTargets[selectedIndex].click()`. Reorder
  items and the mapping must stay consistent.
- **Missing `disconnect` cleanup → duplicated native controls** after each Turbo
  navigation (iOS bar buttons stack up; Android menu items duplicate — Android
  also needs an explicit `menu.clear()`).
- **Degrade gracefully.** Without a native bridge, `connect()` never fires, so the
  web markup must work on its own; the JS adds `is-hidden` only once connected.
- **Strada/Hotwire Native version drift.** Piazza uses pre-rename libs
  (`@hotwired/strada`, `strada-ios`, `dev.hotwire:strada`). Hotwire Native 1.x
  folds Strada into the core — the bridge concepts carry over but imports/APIs change.

## Source

Real implementations: `piazza-web/app/javascript/controllers/bridge/nav_menu_controller.js`,
`piazza-ios/Piazza/Bridge/NavMenuComponent.swift`,
`piazza-android/app/src/main/java/com/radioactivetoy/piazza/NavMenuComponent.kt`.
Deeper write-up: `piazza-web/wip/analysis/04-strada-bridge-contract.md`.
