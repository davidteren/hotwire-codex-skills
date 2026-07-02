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
# Exit:   0 = clean, 1 = findings, 2 = bad usage / no ruby.
# CEILING: regex heuristics, not an ERB/HTML parser. Conservative — only literal,
#   statically-resolvable ids are flagged; anything dynamic is reported as skipped.
set -uo pipefail
command -v ruby >/dev/null || { echo "needs ruby" >&2; exit 2; }

APP="${1:-.}"
[ -d "$APP/app/views" ] || { echo "usage: $0 <rails-app-dir> (no app/views/)" >&2; exit 2; }

ruby - "$APP" <<'RUBY'
require 'set'
require 'pathname'

APP = ARGV[0]
VIEWS = File.join(APP, "app", "views")
$fail = 0
def flag(m) $fail = 1; puts "  ⚠️  #{m}" end
def bad(m) $fail = 1; puts "  ❌ #{m}" end
def ok(m) puts "  ✓ #{m}" end
def rel(f) Pathname(f).relative_path_from(Pathname(APP)).to_s end

RESERVED = %w[_top _self _parent _blank].to_set
EXTS = %w[erb haml slim].freeze

files = EXTS.flat_map { |ext| Dir.glob(File.join(VIEWS, '**', "*.#{ext}")) }.uniq.sort
if files.empty?
  puts "  (no view files found under app/views)"; exit 0
end

texts = files.to_h { |f| [f, File.read(f, encoding: 'UTF-8').scrub] }

# --- collect literal frame definitions + note whether any dynamic defs exist ----------
defined = Set.new                # literal frame ids defined anywhere
has_dynamic_def = false
DEF_LITERAL_TAG  = /turbo_frame_tag\s+["']([^"'\#{]+)["']/
DEF_LITERAL_HTML = /<turbo-frame\b[^>]*\bid=["']([^"'<\#]+)["']/i
DEF_DYNAMIC = /turbo_frame_tag\s+(?:dom_id|["'][^"']*\#\{)|<turbo-frame\b[^>]*\bid=["'][^"']*(?:<%|\#\{)/i
texts.each_value do |t|
  t.scan(DEF_LITERAL_TAG)  { defined << Regexp.last_match(1) }
  t.scan(DEF_LITERAL_HTML) { defined << Regexp.last_match(1) }
  has_dynamic_def = true if t.match?(DEF_DYNAMIC)
end

# --- collect literal frame targets (file:line) ----------------------------------------
# data-turbo-frame="X" | turbo_frame: "X" (covers data: { turbo_frame: "X" } and the kwarg)
HTML_TARGET = /data-turbo-frame=["']([^"']+)["']/
RUBY_TARGET = /\bturbo_frame:\s*["']([^"']+)["']/
TAG_TARGET  = /target:\s*["']([^"']+)["']/   # only on turbo_frame_tag lines

targets = []  # [id, file, lineno]
texts.each do |f, t|
  t.each_line.with_index(1) do |line, i|
    line.scan(HTML_TARGET) { targets << [Regexp.last_match(1), f, i] }
    line.scan(RUBY_TARGET) { targets << [Regexp.last_match(1), f, i] }
    if line.include?("turbo_frame_tag")
      line.scan(TAG_TARGET) { targets << [Regexp.last_match(1), f, i] }
    end
  end
end

puts "== Turbo Frames: #{APP} =="
puts "   #{files.length} view(s) · #{defined.length} literal frame def(s) · " \
     "#{has_dynamic_def ? 'dynamic defs present' : 'no dynamic defs'}"

# --- check 1: dangling targets --------------------------------------------------------
puts "1. Dangling frame targets —"
dom_id_shaped = /_\d+\z/   # looks like dom_id(record) output → can't verify
flagged = 0; skipped_dynamic = 0
seen = Set.new
targets.each do |fid, f, ln|
  next if RESERVED.include?(fid)
  next if defined.include?(fid)
  key = [fid, rel(f), ln]
  next if seen.include?(key)
  seen << key
  if has_dynamic_def && fid.match?(dom_id_shaped)
    skipped_dynamic += 1; next   # could match a dom_id frame we can't resolve
  end
  bad("#{rel(f)}:#{ln} targets frame \"#{fid}\" but no " \
      "turbo_frame_tag \"#{fid}\" / <turbo-frame id=\"#{fid}\"> is defined in any view " \
      "— navigation goes nowhere, no error")
  flagged += 1
end
if flagged == 0
  ok("every literal frame target resolves to a defined frame")
end
if skipped_dynamic > 0
  puts "  (skipped #{skipped_dynamic} target(s) shaped like a dom_id while dynamic " \
       "frame defs exist — can't resolve statically)"
end

# --- check 2: literal frame id inside a collection partial ----------------------------
puts "2. Literal frame ids in collection partials —"
# explicit collection renders: render [partial:] "a/b/c" ... collection:
COLL = /render\b(?:\s+partial:)?\s+["']([^"']+)["'][^>%]*?collection:/m
coll_partials = Set.new
texts.each_value do |t|
  t.scan(COLL) { coll_partials << Regexp.last_match(1) }
end

def resolve(path)
  # Rails partials are _name.<format>.<handler> (e.g. _post.html.erb), so match the
  # leading _name.* and keep the first that ends in a handler we scan. File.dirname
  # returns "." for a dir-less partial ("post"); collapse it so the globbed path has
  # no "/./" segment and still matches the keys in `texts` (else the lookup is nil).
  d = File.dirname(path)
  b = File.basename(path)
  dir = d == "." ? VIEWS : File.join(VIEWS, d)
  Dir.glob(File.join(dir, "_#{b}.*")).sort.find { |cand| cand.end_with?(*EXTS) }
end

checked = 0
coll_partials.sort.each do |p|
  f = resolve(p)
  next unless f
  checked += 1
  if (m = texts[f].match(DEF_LITERAL_TAG))
    flag("#{rel(f)} renders via collection: but defines a literal " \
         "turbo_frame_tag \"#{m[1]}\" — every row gets the SAME id (duplicate " \
         "in the DOM). Use turbo_frame_tag dom_id(record).")
  end
end
if checked == 0
  puts "  (no explicit collection: renders of a frame-bearing partial found)"
elsif $fail == 0
  ok("#{checked} collection partial(s) use dom_id / no literal frame id")
end
puts "  note: only explicit `collection:` renders are resolved; implicit `render @items`" \
     " can't be mapped to a partial here — verify those by hand."

puts
puts($fail == 0 ? "✅ Turbo Frames OK" : "❌ Turbo Frames findings above — see references/turbo-frames-guide.md")
exit $fail
RUBY
