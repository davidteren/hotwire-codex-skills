#!/usr/bin/env bash
# Generate the three platform halves of a Strada / Hotwire Native bridge component
# from one component name, so the name + payload shape start out identical.
#
# Usage:
#   new_bridge_component.sh <component-name-in-kebab> \
#       [--web <piazza-web>] [--ios <piazza-ios>] [--android <piazza-android>] \
#       [--package com.example.app]
#
# Writes (only if the target dir exists; otherwise prints the file to stdout):
#   web:     <web>/app/javascript/controllers/bridge/<snake>_controller.js
#   ios:     <ios>/<AppDir>/Bridge/<Pascal>Component.swift
#   android: <android>/app/src/main/java/<pkgpath>/<Pascal>Component.kt
# and prints the manual registration steps for iOS + Android.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

NAME="${1:-}"; shift || true
[ -n "$NAME" ] || die "component name (kebab-case, e.g. nav-menu) required"
echo "$NAME" | grep -Eq '^[a-z][a-z0-9-]*$' || die "name must be kebab-case [a-z0-9-]"

WEB="" ; IOS="" ; ANDROID="" ; PACKAGE="com.example.app"
while [ $# -gt 0 ]; do
  case "$1" in
    --web) WEB="$2"; shift 2;;
    --ios) IOS="$2"; shift 2;;
    --android) ANDROID="$2"; shift 2;;
    --package) PACKAGE="$2"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done

SNAKE="${NAME//-/_}"
# kebab -> PascalCase
PASCAL="$(echo "$NAME" | awk -F- '{for(i=1;i<=NF;i++){printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}}')"
TPL_DIR="$(cd "$(dirname "$0")/../templates" && pwd)"

render() { # render <template> ; substitutes the placeholder tokens
  sed -e "s/__COMPONENT_NAME__/$NAME/g" \
      -e "s/__SNAKE_NAME__/$SNAKE/g" \
      -e "s/__CLASS_NAME__/$PASCAL/g" \
      -e "s/__PACKAGE__/$PACKAGE/g" \
      "$1"
}

emit() { # emit <rendered-content-file-or-text> <dest-path>
  local content="$1" dest="$2"
  if [ -n "$dest" ] && [ -d "$(dirname "$dest")" ]; then
    [ -e "$dest" ] && die "refusing to overwrite existing $dest"
    printf '%s\n' "$content" > "$dest"
    echo "  wrote $dest"
  else
    echo "  --- (no target dir; printing) ---"
    printf '%s\n' "$content"
  fi
}

echo "Generating bridge component '$NAME' (class ${PASCAL}Component)"

# WEB
WEB_DEST=""
[ -n "$WEB" ] && WEB_DEST="$WEB/app/javascript/controllers/bridge/${SNAKE}_controller.js"
emit "$(render "$TPL_DIR/web_controller.js.tmpl")" "$WEB_DEST"

# iOS — locate the app source dir containing Bridge/
IOS_DEST=""
if [ -n "$IOS" ]; then
  BRIDGE_DIR="$(find "$IOS" -type d -name Bridge -not -path '*/build/*' | head -1 || true)"
  [ -n "$BRIDGE_DIR" ] && IOS_DEST="$BRIDGE_DIR/${PASCAL}Component.swift"
fi
emit "$(render "$TPL_DIR/ios_Component.swift.tmpl")" "$IOS_DEST"

# ANDROID
AND_DEST=""
if [ -n "$ANDROID" ]; then
  PKGPATH="${PACKAGE//.//}"
  AND_DIR="$ANDROID/app/src/main/java/$PKGPATH"
  [ -d "$AND_DIR" ] && AND_DEST="$AND_DIR/${PASCAL}Component.kt"
fi
emit "$(render "$TPL_DIR/android_Component.kt.tmpl")" "$AND_DEST"

cat <<EOF

NEXT — register the component (the generator does NOT edit registries for you):

  iOS  : add  ${PASCAL}Component.self
         to   BridgeComponent.allTypes  (Bridge/BridgeComponent+<App>.swift)

  Android: add  BridgeComponentFactory("$NAME", ::${PASCAL}Component)
           to   the bridgeComponentFactories list (BridgeComponentFactories.kt)

  Web  : Stimulus auto-registers it as  bridge--$NAME  (no manual step), as long
         as the file is under app/javascript/controllers/bridge/.

  Markup: attach with  data-controller="bridge--$NAME"  and per-item targets
          data-bridge--$NAME-target="item"  (+ data-bridge-<attr> for payload).

Then run lint_bridge_contract.sh to confirm all three sides agree.
EOF
