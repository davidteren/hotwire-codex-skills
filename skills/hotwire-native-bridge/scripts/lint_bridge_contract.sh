#!/usr/bin/env bash
# Lint the Strada / Hotwire Native bridge CONTRACT across web + iOS + Android.
# Catches the failure class that costs the most time: a component that exists on
# one platform but isn't registered (or is misspelled) on another, and payload
# fields present on one native side but silently dropped on the other.
#
# Usage:
#   lint_bridge_contract.sh --web <piazza-web> --ios <piazza-ios> --android <piazza-android>
#   lint_bridge_contract.sh --root <dir-containing-the-three-repos>   # uses default repo names
#
# Exit code: 0 = no drift, 1 = drift found, 2 = bad usage.
#
# CEILING: this is a heuristic text scan (grep/awk), not a real Swift/Kotlin/JS
# parser. It is deliberately conservative — it flags likely drift to eyeball, and
# can miss exotic formatting. Good enough to gate a PR; not a type checker.
set -uo pipefail

WEB="" IOS="" ANDROID="" ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --web) WEB="$2"; shift 2;;
    --ios) IOS="$2"; shift 2;;
    --android) ANDROID="$2"; shift 2;;
    --root) ROOT="$2"; shift 2;;
    *) echo "usage: $0 --web W --ios I --android A | --root DIR" >&2; exit 2;;
  esac
done
if [ -n "$ROOT" ]; then
  WEB="${WEB:-$ROOT/piazza-web}"; IOS="${IOS:-$ROOT/piazza-ios}"; ANDROID="${ANDROID:-$ROOT/piazza-android}"
fi
[ -d "$WEB" ] && [ -d "$IOS" ] && [ -d "$ANDROID" ] || { echo "usage: provide --web/--ios/--android (or --root)" >&2; exit 2; }

fail=0
warn() { echo "  ⚠️  $*"; fail=1; }
ok()   { echo "  ✓ $*"; }

# --- 1. Collect component names per platform -------------------------------
# web: static component = "X"
WEB_NAMES=$(grep -rhoE 'static[[:space:]]+component[[:space:]]*=[[:space:]]*"[^"]+"' \
            "$WEB/app/javascript" 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
# iOS declared: override class var name: String { "X" }
IOS_NAMES=$(grep -rhoE 'class[[:space:]]+var[[:space:]]+name[^"]*"[^"]+"' \
            "$IOS" 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
# iOS registered classes in allTypes (……Component.self)
IOS_REGISTERED=$(grep -rhoE '[A-Za-z0-9_]+Component\.self' "$IOS" 2>/dev/null | sed 's/\.self//' | sort -u)
# android factories: BridgeComponentFactory("X", ::YComponent)
AND_NAMES=$(grep -rhoE 'BridgeComponentFactory\("[^"]+"' "$ANDROID" 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' | sort -u)

echo "Component names —"
echo "  web    : $(echo "$WEB_NAMES" | tr '\n' ' ')"
echo "  ios    : $(echo "$IOS_NAMES" | tr '\n' ' ')"
echo "  android: $(echo "$AND_NAMES" | tr '\n' ' ')"
echo

# --- 2. Name parity across platforms ---------------------------------------
echo "Name parity —"
ALL=$(printf '%s\n%s\n%s\n' "$WEB_NAMES" "$IOS_NAMES" "$AND_NAMES" | grep -v '^$' | sort -u)
[ -z "$ALL" ] && { echo "  (no bridge components found)"; exit 0; }
while IFS= read -r n; do
  miss=""
  echo "$WEB_NAMES" | grep -qx "$n" || miss="$miss web"
  echo "$IOS_NAMES" | grep -qx "$n" || miss="$miss ios"
  echo "$AND_NAMES" | grep -qx "$n" || miss="$miss android"
  if [ -n "$miss" ]; then warn "'$n' missing on:$miss (typo or unregistered → invisible component)"; else ok "'$n' present on all three"; fi
done <<< "$ALL"
echo

# --- 3. iOS: declared component but not in allTypes ------------------------
echo "iOS registration —"
for f in $(grep -rlE 'class[[:space:]]+var[[:space:]]+name' "$IOS" 2>/dev/null); do
  cls=$(grep -oE 'class[[:space:]]+[A-Za-z0-9_]+Component' "$f" | awk '{print $2}' | head -1)
  [ -z "$cls" ] && continue
  if echo "$IOS_REGISTERED" | grep -qx "$cls"; then ok "$cls in allTypes"; else warn "$cls is defined but NOT in BridgeComponent.allTypes (won't load)"; fi
done
echo

# --- 4. Payload field parity: iOS Decodable vs Android @SerialName ----------
# Heuristic: compare the union of decoded field names on each native side. A field
# the web sends that one side doesn't decode is silently dropped.
echo "Payload field parity (iOS Decodable vs Android @SerialName) —"
# Scope to bridge-component source files ONLY (files that extend BridgeComponent),
# otherwise unrelated `let x:` properties / @Serializable classes leak in as noise.
IOS_BRIDGE_FILES=$(grep -rlE ':[[:space:]]*BridgeComponent\b|BridgeComponent[[:space:]]*\{' "$IOS" 2>/dev/null | grep -E '\.swift$')
AND_BRIDGE_FILES=$(grep -rlE ':[[:space:]]*BridgeComponent<' "$ANDROID" 2>/dev/null | grep -E '\.kt$')
# struct fields are `let name: Type` with NO `=` (exclude guard/let-with-assignment locals)
IOS_FIELDS=$( [ -n "$IOS_BRIDGE_FILES" ] && grep -hE '^[[:space:]]*let[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*:' $IOS_BRIDGE_FILES 2>/dev/null \
             | grep -v '=' | grep -oE 'let[[:space:]]+[a-zA-Z0-9_]+' | awk '{print $2}' | sort -u)
AND_FIELDS=$( [ -n "$AND_BRIDGE_FILES" ] && grep -hoE '@SerialName\("[^"]+"\)' $AND_BRIDGE_FILES 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
only_ios=$(comm -23 <(echo "$IOS_FIELDS") <(echo "$AND_FIELDS") | grep -v '^$')
only_and=$(comm -13 <(echo "$IOS_FIELDS") <(echo "$AND_FIELDS") | grep -v '^$')
# selectedIndex/items are structural; filter the obvious response/container keys
filt() { grep -vxE 'selectedIndex|items'; }
oi=$(echo "$only_ios" | filt); oa=$(echo "$only_and" | filt)
if [ -n "$oi" ]; then for x in $oi; do warn "field '$x' decoded on iOS but no matching @SerialName on Android (likely dropped on Android)"; done; fi
if [ -n "$oa" ]; then for x in $oa; do warn "field '$x' decoded on Android but not found on iOS (likely dropped on iOS)"; done; fi
[ -z "$oi$oa" ] && ok "native decoded fields match"
echo

# --- 5. Library generation (Hotwire Native 1.x vs Strada beta) --------------
echo "Library generation —"
gen() { # gen <label> <beta-pattern> <1x-pattern> <dir> <ext>
  local label="$1" beta="$2" onex="$3" dir="$4" ext="$5" b o
  b=$(grep -rlE --include="*.$ext" "$beta" "$dir" 2>/dev/null | head -1)
  o=$(grep -rlE --include="*.$ext" "$onex" "$dir" 2>/dev/null | head -1)
  if [ -n "$o" ] && [ -z "$b" ]; then echo "  $label: Hotwire Native 1.x"; G1=$((G1+1))
  elif [ -n "$b" ] && [ -z "$o" ]; then echo "  $label: Strada beta (legacy)"; GB=$((GB+1))
  elif [ -n "$b" ] && [ -n "$o" ]; then warn "$label: MIXED beta + 1.x imports — finish the migration"
  else echo "  $label: (bridge lib import not found)"; fi
}
G1=0; GB=0
gen "web    " '@hotwired/strada' '@hotwired/hotwire-native-bridge' "$WEB/app/javascript" js
gen "ios    " 'import Strada' 'import HotwireNative' "$IOS" swift
gen "android" 'dev\.hotwire\.strada' 'dev\.hotwire\.core\.bridge' "$ANDROID" kt
[ "$G1" -gt 0 ] && [ "$GB" -gt 0 ] && warn "platforms split across Hotwire Native 1.x and Strada beta — upgrade them together"
echo

if [ "$fail" -eq 0 ]; then echo "✅ bridge contract OK"; else echo "❌ bridge contract drift found"; fi
exit $fail
