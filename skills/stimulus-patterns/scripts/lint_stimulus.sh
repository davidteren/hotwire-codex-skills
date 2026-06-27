#!/usr/bin/env bash
# Lint Stimulus controllers for the mistakes that fail at runtime or leak:
#  1. this.xTarget / xValue / xClass used but not declared in static targets/values/classes
#  2. connect() registers listeners/timers/observers but the controller has no disconnect()
#  3. a controller file that isn't registered in the manifest (index.js) — never connects
# Read-only.
#
# Usage:  lint_stimulus.sh <rails-app-dir | controllers-dir>   # defaults to .
# Exit:   0 = clean, 1 = findings, 2 = bad usage / no python3.
# CEILING: regex heuristics, not a JS parser. Conservative; names its limits.
set -uo pipefail
command -v python3 >/dev/null || { echo "needs python3" >&2; exit 2; }

ROOT="${1:-.}"
if   [ -d "$ROOT/app/javascript/controllers" ]; then CDIR="$ROOT/app/javascript/controllers"
elif [ -d "$ROOT/controllers" ]; then CDIR="$ROOT/controllers"
elif [ -d "$ROOT" ] && ls "$ROOT"/*_controller.js >/dev/null 2>&1; then CDIR="$ROOT"
else echo "no Stimulus controllers dir found under $ROOT" >&2; exit 2; fi

python3 - "$CDIR" <<'PY'
import os, re, sys, glob
CDIR = sys.argv[1]
fail = 0
def warn(m):
    global fail; print(f"  ⚠️  {m}"); fail = 1
def ok(m): print(f"  ✓ {m}")

def arr_items(text, kw):
    m = re.search(r'static\s+'+kw+r'\s*=\s*\[(.*?)\]', text, re.S)
    return set(re.findall(r'["\']([^"\']+)["\']', m.group(1))) if m else set()

def obj_keys(text, kw):
    m = re.search(r'static\s+'+kw+r'\s*=\s*\{(.*?)\}', text, re.S)
    if not m: return set()
    return set(re.findall(r'([A-Za-z0-9_]+)\s*:', m.group(1)))

def norm_has(name):
    # hasFooTarget -> foo
    if re.match(r'has[A-Z]', name):
        rest = name[3:]
        return rest[0].lower() + rest[1:]
    return name

def refs(text, suffix):
    out = set()
    for ident in re.findall(r'this\.([A-Za-z0-9_]+?)'+suffix+r'\b', text):
        out.add(norm_has(ident))
    return out

files = sorted(glob.glob(os.path.join(CDIR, '**', '*_controller.js'), recursive=True))
if not files:
    print("  (no *_controller.js found)"); sys.exit(0)

# manifest registrations (if index.js uses the manifest approach)
index = os.path.join(CDIR, 'index.js')
index_text = open(index).read() if os.path.exists(index) else ""
manifest = 'application.register' in index_text

print(f"Linting {len(files)} controller(s) in {CDIR}")
for f in files:
    text = open(f).read()
    rel = os.path.relpath(f, CDIR)
    name = os.path.basename(f)

    # 1. declared vs referenced
    dt, dv, dc = arr_items(text,'targets'), obj_keys(text,'values'), arr_items(text,'classes')
    rt = refs(text, r'Targets?')
    rv = refs(text, r'Value')
    rc = refs(text, r'Class(?:es)?')
    for n in sorted(rt - dt): warn(f"{name}: this.{n}Target used but '{n}' not in static targets")
    for n in sorted(rv - dv): warn(f"{name}: this.{n}Value used but '{n}' not in static values")
    for n in sorted(rc - dc): warn(f"{name}: this.{n}Class(es) used but '{n}' not in static classes")

    # 2. cleanup parity
    has_connect = re.search(r'\bconnect\s*\(', text)
    leaky = re.search(r'addEventListener|setInterval|setTimeout|new\s+(Mutation|Intersection|Resize)Observer', text)
    has_disconnect = re.search(r'\bdisconnect\s*\(', text)
    if leaky and not has_disconnect:
        kinds = ', '.join(sorted(set(re.findall(r'addEventListener|setInterval|setTimeout|(?:Mutation|Intersection|Resize)Observer', text))))
        warn(f"{name}: registers [{kinds}] but has no disconnect() — leaks / double-fires after Turbo navigation. Remove it in disconnect().")

    # 3. registration
    if manifest:
        import_path = './' + os.path.splitext(rel)[0]
        if import_path not in index_text and import_path.replace('\\','/') not in index_text:
            warn(f"{name}: not registered in index.js manifest ({import_path}) — it will never connect")

if fail == 0:
    ok("all controllers: targets/values/classes declared, cleanup present, registered")
print()
print("✅ Stimulus controllers OK" if fail == 0 else "❌ Stimulus findings above — see references/stimulus-guide.md")
sys.exit(fail)
PY
