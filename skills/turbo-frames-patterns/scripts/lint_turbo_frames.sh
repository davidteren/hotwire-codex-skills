#!/usr/bin/env bash
# Lint Turbo Frame wiring in a Rails app for the mistakes that fail silently (no error):
#  1. Dangling frame target — a link/form/component targets frame "X" (data-turbo-frame,
#     data: { turbo_frame: }, turbo_frame:, or target: on turbo_frame_tag) but NO
#     turbo_frame_tag "X" / <turbo-frame id="X"> is defined anywhere in views →
#     navigation goes nowhere, no error. (HIGH confidence: literal ids only.)
#  2. Literal frame id in a collection partial — turbo_frame_tag "literal" (no dom_id /
#     interpolation) in a partial rendered via collection: → duplicate DOM ids. (Heuristic.)
# Reserved targets (_top _self _parent _blank) and dynamic ids (dom_id(...)/#{}/<%= %>)
# are never flagged — when either side is dynamic we can't resolve it, so we skip.
# Read-only.
#
# Usage:  lint_turbo_frames.sh <rails-app-dir>     # defaults to .
# Exit:   0 = clean, 1 = findings, 2 = bad usage / no python3.
# CEILING: regex heuristics, not an ERB/HTML parser. Conservative — only literal,
#   statically-resolvable ids are flagged; anything dynamic is reported as skipped.
set -uo pipefail
command -v python3 >/dev/null || { echo "needs python3" >&2; exit 2; }

APP="${1:-.}"
[ -d "$APP/app/views" ] || { echo "usage: $0 <rails-app-dir> (no app/views/)" >&2; exit 2; }

python3 - "$APP" <<'PY'
import os, re, sys, glob

APP = sys.argv[1]
VIEWS = os.path.join(APP, "app", "views")
fail = 0
def warn(m):
    global fail; print(f"  ⚠️  {m}"); fail = 1
def bad(m):
    global fail; print(f"  ❌ {m}"); fail = 1
def ok(m): print(f"  ✓ {m}")

RESERVED = {"_top", "_self", "_parent", "_blank"}
EXTS = ("erb", "haml", "slim")

files = []
for ext in EXTS:
    files += glob.glob(os.path.join(VIEWS, "**", f"*.{ext}"), recursive=True)
files = sorted(set(files))
if not files:
    print("  (no view files found under app/views)"); sys.exit(0)

texts = {f: open(f, encoding="utf-8", errors="replace").read() for f in files}

# --- collect literal frame definitions + note whether any dynamic defs exist ----------
defined = set()                 # literal frame ids defined anywhere
has_dynamic_def = False
DEF_LITERAL_TAG = re.compile(r'turbo_frame_tag\s+["\']([^"\'#{]+)["\']')
DEF_LITERAL_HTML = re.compile(r'<turbo-frame\b[^>]*\bid=["\']([^"\'<#]+)["\']', re.I)
DEF_DYNAMIC = re.compile(r'turbo_frame_tag\s+(?:dom_id|["\'][^"\']*#\{)'      # dom_id(...) or "#{...}"
                         r'|<turbo-frame\b[^>]*\bid=["\'][^"\']*(?:<%|#\{)', re.I)
for f, t in texts.items():
    for m in DEF_LITERAL_TAG.finditer(t):  defined.add(m.group(1))
    for m in DEF_LITERAL_HTML.finditer(t): defined.add(m.group(1))
    if DEF_DYNAMIC.search(t): has_dynamic_def = True

# --- collect literal frame targets (file:line) ----------------------------------------
# data-turbo-frame="X" | turbo_frame: "X" (covers data: { turbo_frame: "X" } and the kwarg)
HTML_TARGET = re.compile(r'data-turbo-frame=["\']([^"\']+)["\']')
RUBY_TARGET = re.compile(r'\bturbo_frame:\s*["\']([^"\']+)["\']')
TAG_TARGET  = re.compile(r'target:\s*["\']([^"\']+)["\']')   # only on turbo_frame_tag lines

targets = []  # (id, file, lineno)
for f, t in texts.items():
    for i, line in enumerate(t.splitlines(), 1):
        for m in HTML_TARGET.finditer(line): targets.append((m.group(1), f, i))
        for m in RUBY_TARGET.finditer(line): targets.append((m.group(1), f, i))
        if "turbo_frame_tag" in line:
            for m in TAG_TARGET.finditer(line): targets.append((m.group(1), f, i))

print(f"== Turbo Frames: {APP} ==")
print(f"   {len(files)} view(s) · {len(defined)} literal frame def(s) · "
      f"{'dynamic defs present' if has_dynamic_def else 'no dynamic defs'}")

# --- check 1: dangling targets --------------------------------------------------------
print("1. Dangling frame targets —")
dom_id_shaped = re.compile(r'_\d+$')   # looks like dom_id(record) output → can't verify
flagged = skipped_dynamic = 0
seen = set()
for fid, f, ln in targets:
    if fid in RESERVED:   continue
    if fid in defined:    continue
    key = (fid, os.path.relpath(f, APP), ln)
    if key in seen: continue
    seen.add(key)
    if has_dynamic_def and dom_id_shaped.search(fid):
        skipped_dynamic += 1; continue   # could match a dom_id frame we can't resolve
    bad(f"{os.path.relpath(f, APP)}:{ln} targets frame \"{fid}\" but no "
        f"turbo_frame_tag \"{fid}\" / <turbo-frame id=\"{fid}\"> is defined in any view "
        f"— navigation goes nowhere, no error")
    flagged += 1
if flagged == 0:
    ok("every literal frame target resolves to a defined frame")
if skipped_dynamic:
    print(f"  (skipped {skipped_dynamic} target(s) shaped like a dom_id while dynamic "
          f"frame defs exist — can't resolve statically)")

# --- check 2: literal frame id inside a collection partial ----------------------------
print("2. Literal frame ids in collection partials —")
# explicit collection renders: render [partial:] "a/b/c" ... collection:
COLL = re.compile(r'render\b(?:\s+partial:)?\s+["\']([^"\']+)["\'][^>%]*?collection:', re.S)
coll_partials = set()
for t in texts.values():
    for m in COLL.finditer(t):
        coll_partials.add(m.group(1))

def resolve(path):
    # Rails partials are _name.<format>.<handler> (e.g. _post.html.erb), so match the
    # leading _name.* and keep the first that ends in a handler we scan.
    d, b = os.path.split(path)
    for cand in sorted(glob.glob(os.path.join(VIEWS, d, f"_{b}.*"))):
        if cand.endswith(EXTS): return cand
    return None

checked = 0
for p in sorted(coll_partials):
    f = resolve(p)
    if not f: continue
    checked += 1
    if DEF_LITERAL_TAG.search(texts[f]):
        m = DEF_LITERAL_TAG.search(texts[f])
        warn(f"{os.path.relpath(f, APP)} renders via collection: but defines a literal "
             f"turbo_frame_tag \"{m.group(1)}\" — every row gets the SAME id (duplicate "
             f"in the DOM). Use turbo_frame_tag dom_id(record).")
if checked == 0:
    print("  (no explicit collection: renders of a frame-bearing partial found)")
elif fail == 0:
    ok(f"{checked} collection partial(s) use dom_id / no literal frame id")
print("  note: only explicit `collection:` renders are resolved; implicit `render @items`"
      " can't be mapped to a partial here — verify those by hand.")

print()
print("✅ Turbo Frames OK" if fail == 0
      else "❌ Turbo Frames findings above — see references/turbo-frames-guide.md")
sys.exit(fail)
PY
