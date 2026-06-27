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

## Hotwire Native 1.x vs the Piazza baseline (Strada beta)

Bridge Components were formerly called **Strada** components and "work exactly as
before" — but the framework merged into Hotwire Native 1.x, so imports, the Android
destination type, and registration changed. The skill's templates target **1.x**;
the Piazza example repos still use the beta wiring. Migration map:

| Concern | Piazza baseline (Strada beta) | Hotwire Native 1.x |
|---|---|---|
| Web package | `@hotwired/strada` | `@hotwired/hotwire-native-bridge` |
| Web `connect()` | manual | call `super.connect()`; `this.bridgeElement` getter |
| iOS import / package | `import Strada` (turbo-ios + strada-ios) | `import HotwireNative` (hotwire-native-ios, one dep) |
| iOS register | `BridgeComponent.allTypes` extension | `Hotwire.registerBridgeComponents([X.self])` in AppDelegate, **before** any `Navigator` |
| iOS delegate | `delegate.destination` | `delegate?.destination` (optional) |
| Android package | `dev.hotwire.strada.*` (dev.hotwire:turbo + strada) | `dev.hotwire.core.bridge.*` (dev.hotwire:core) |
| Android destination | `BridgeComponent<NavDestination>` | `BridgeComponent<HotwireDestination>` |
| Android register | `bridgeComponentFactories` list → WebFragment | `Hotwire.registerBridgeComponents(BridgeComponentFactory(...))` in `Application` |

The component **bodies** (`onReceive`, `reply`/`replyTo`, `message.data()`,
`send` + callback) are unchanged across the rename. The cross-platform **contract**
(name + payload parity) is identical in both eras — so `lint_bridge_contract.sh`
works regardless of version. Gotcha specific to 1.x iOS: register components before
the `Navigator` is created or they never attach (hotwire-native-ios #35; addressed
via a notification in v1.1).

Upgrading the Piazza apps: `piazza-ios` and `piazza-android` ship the beta libs;
their `wip/analysis/00-*-architecture.md` flag the 1.x port as deferred — this table
is the migration checklist for it.

Sources (verified): native.hotwired.dev iOS/Android/reference bridge-components +
bridge-installation; `dev.hotwire.core.bridge` package confirmed from the
hotwire-native-android source.

## Source

Real implementations: `piazza-web/app/javascript/controllers/bridge/nav_menu_controller.js`,
`piazza-ios/Piazza/Bridge/NavMenuComponent.swift`,
`piazza-android/app/src/main/java/com/radioactivetoy/piazza/NavMenuComponent.kt`.
Deeper write-up: `piazza-web/wip/analysis/04-strada-bridge-contract.md`.
