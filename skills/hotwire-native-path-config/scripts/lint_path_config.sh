#!/usr/bin/env bash
# Validate a Hotwire Native path-configuration JSON (schema + footguns), and
# optionally diff two configs (iOS vs Android) for path-coverage drift.
#
# Usage:
#   lint_path_config.sh <config.json> [config2.json]   # validate one or two
#   lint_path_config.sh --compare <iosA.json> <androidB.json>
#
# Exit: 0 = clean, 1 = problems, 2 = bad usage / no python3.
set -uo pipefail
command -v python3 >/dev/null || { echo "needs python3" >&2; exit 2; }

[ $# -ge 1 ] || { echo "usage: $0 <config.json> [config2.json] | --compare A B" >&2; exit 2; }

python3 - "$@" <<'PY'
import json, re, sys

VALID_CONTEXT = {"default", "modal"}
VALID_PRESENTATION = {"default","push","pop","replace","replace_root","clear_all","refresh","none"}
KNOWN_PROPS = {
    "context","presentation","pull_to_refresh_enabled","animated",     # universal
    "uri","fallback_uri","title",                                       # android
    "view_controller","modal_style","modal_dismiss_gesture_enabled",    # ios
}
VALID_MODAL_STYLE = {"large","medium","full","page_sheet","form_sheet"}

fail = 0
def warn(m):
    global fail; print(f"  ⚠️  {m}"); fail = 1
def ok(m): print(f"  ✓ {m}")

def load(path):
    with open(path) as f:
        return json.load(f)

def validate(path, cfg):
    print(f"Validating {path}")
    if not isinstance(cfg, dict):
        warn("top level is not an object"); return set()
    if "rules" not in cfg or not isinstance(cfg["rules"], list) or not cfg["rules"]:
        warn("missing or empty 'rules' array"); return set()
    if "settings" in cfg and not isinstance(cfg["settings"], dict):
        warn("'settings' is not an object")
    all_patterns = set()
    catchall_first = False
    for i, rule in enumerate(cfg["rules"]):
        where = f"rule[{i}]"
        if not isinstance(rule, dict) or "patterns" not in rule or "properties" not in rule:
            warn(f"{where}: each rule needs 'patterns' and 'properties'"); continue
        pats, props = rule["patterns"], rule["properties"]
        if not isinstance(pats, list) or not pats:
            warn(f"{where}: 'patterns' must be a non-empty array")
        for p in (pats if isinstance(pats, list) else []):
            all_patterns.add(p)
            try: re.compile(p)
            except re.error as e: warn(f"{where}: pattern {p!r} is not valid regex ({e})")
            # footgun: unanchored short path segment
            if re.fullmatch(r"/[a-z_]+", p):
                warn(f"{where}: pattern {p!r} is unanchored — '/new' also matches '/renew'; use '{p}$'")
            if i == 0 and p in (".*","/.*","^.*$","^/.*"): catchall_first = True
        if not isinstance(props, dict):
            warn(f"{where}: 'properties' must be an object"); continue
        for k, v in props.items():
            if k not in KNOWN_PROPS:
                warn(f"{where}: unknown property {k!r} (typo? not in the 1.x schema)")
            if k == "context" and v not in VALID_CONTEXT:
                warn(f"{where}: context={v!r} invalid (use {sorted(VALID_CONTEXT)})")
            if k == "presentation":
                if v == "modal":
                    warn(f"{where}: presentation='modal' is a Strada-beta-ism — in 1.x use context='modal'")
                elif v not in VALID_PRESENTATION:
                    warn(f"{where}: presentation={v!r} invalid (use {sorted(VALID_PRESENTATION)})")
            if k == "modal_style" and v not in VALID_MODAL_STYLE:
                warn(f"{where}: modal_style={v!r} invalid")
        # android needs a uri on each navigable rule
    if catchall_first:
        ok("catch-all rule is first (specific rules below override it)")
    else:
        # not fatal, but the most common ordering mistake
        first_pats = cfg["rules"][0].get("patterns", [])
        if not any(p in (".*","/.*","^.*$","^/.*") for p in first_pats):
            warn("first rule is not a broad catch-all — rules are matched top-to-bottom with LATER winning; confirm ordering is intentional")
    if fail == 0:
        ok("schema valid")
    return all_patterns

args = sys.argv[1:]
if args[0] == "--compare":
    if len(args) != 3:
        print("usage: --compare A B", file=sys.stderr); sys.exit(2)
    a, b = args[1], args[2]
    pa = validate(a, load(a)); print()
    pb = validate(b, load(b)); print()
    print("Cross-config path coverage (anchors normalized — ceiling: not full semantic regex equivalence) —")
    def norm(p):
        p = p.strip()
        if p.startswith("^"): p = p[1:]
        if p.endswith("$"): p = p[:-1]
        p = p.rstrip("*").strip("/")
        return "<catch-all>" if p in ("", ".", ".*") else p
    na = {norm(p): p for p in pa}; nb = {norm(p): p for p in pb}
    only_a = sorted(set(na) - set(nb)); only_b = sorted(set(nb) - set(na))
    if only_a:
        for k in only_a: warn(f"path {na[k]!r} handled in {a} but not {b} — platforms navigate it differently")
    if only_b:
        for k in only_b: warn(f"path {nb[k]!r} handled in {b} but not {a} — platforms navigate it differently")
    if not only_a and not only_b: ok("both configs cover the same paths (after anchor normalization)")
else:
    for path in args:
        validate(path, load(path)); print()

print("✅ path config OK" if fail == 0 else "❌ path config issues found")
sys.exit(fail)
PY
