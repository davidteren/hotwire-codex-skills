#!/usr/bin/env bash
# Lint Stimulus controllers for the mistakes that fail at runtime or leak:
#  1. this.xTarget / xValue / xClass used but not declared in static targets/values/classes
#  2. connect() registers listeners/timers/observers but the controller has no disconnect()
#  3. a controller file that isn't registered in the manifest (index.js) — never connects
# Read-only.
#
# Usage:  lint_stimulus.sh <rails-app-dir | controllers-dir>   # defaults to .
# Exit:   0 = clean, 1 = findings, 2 = bad usage / no ruby.
# CEILING: regex heuristics, not a JS parser. Conservative; names its limits.
set -uo pipefail
command -v ruby >/dev/null || { echo "needs ruby" >&2; exit 2; }

ROOT="${1:-.}"
if   [ -d "$ROOT/app/javascript/controllers" ]; then CDIR="$ROOT/app/javascript/controllers"
elif [ -d "$ROOT/controllers" ]; then CDIR="$ROOT/controllers"
elif [ -d "$ROOT" ] && ls "$ROOT"/*_controller.js >/dev/null 2>&1; then CDIR="$ROOT"
else echo "no Stimulus controllers dir found under $ROOT" >&2; exit 2; fi

ruby - "$CDIR" <<'RUBY'
require 'set'
CDIR = ARGV[0]
$fail = 0
def flag(m) $fail = 1; puts "  ⚠️  #{m}" end
def ok(m) puts "  ✓ #{m}" end

def arr_items(text, kw)
  m = text.match(/static\s+#{kw}\s*=\s*\[(.*?)\]/m)
  m ? m[1].scan(/["']([^"']+)["']/).flatten.to_set : Set.new
end

def obj_keys(text, kw)
  # Match the WHOLE object via brace balancing (a non-greedy {...} stops at the
  # first inner } — truncating keys after the first typed value like
  # `foo: { type: Number, default: 1 }`), then keep only top-level keys.
  m = text.match(/static\s+#{kw}\s*=\s*\{/)
  return Set.new unless m
  i = m.end(0); depth = 1; start = i
  while i < text.length && depth > 0
    depth += 1 if text[i] == '{'
    depth -= 1 if text[i] == '}'
    i += 1
  end
  body = text[start...(i - 1)]
  keys = Set.new; depth = 0
  body.scan(/([A-Za-z0-9_]+)\s*:|([{}])/) do |key, brace|
    if    brace == '{' then depth += 1
    elsif brace == '}' then depth -= 1
    elsif depth.zero?  then keys << key
    end
  end
  keys
end

def norm_has(name)
  # hasFooTarget -> foo
  return name unless name.match?(/\Ahas[A-Z]/)
  rest = name[3..]
  rest[0].downcase + rest[1..]
end

def refs(text, suffix)
  text.scan(/this\.([A-Za-z0-9_]+?)#{suffix}\b/).flatten.map { |n| norm_has(n) }.to_set
end

files = Dir.glob(File.join(CDIR, '**', '*_controller.js')).sort
if files.empty?
  puts "  (no *_controller.js found)"; exit 0
end

# manifest registrations (if index.js uses the manifest approach)
index = File.join(CDIR, 'index.js')
index_text = File.exist?(index) ? File.read(index) : ""
manifest = index_text.include?('application.register')

puts "Linting #{files.length} controller(s) in #{CDIR}"
files.each do |f|
  text = File.read(f, encoding: 'UTF-8').scrub
  rel = f.sub(%r{\A#{Regexp.escape(CDIR)}/?}, '')
  name = File.basename(f)

  # 1. declared vs referenced
  dt = arr_items(text, 'targets'); dv = obj_keys(text, 'values'); dc = arr_items(text, 'classes')
  rt = refs(text, 'Targets?')
  rv = refs(text, 'Value')
  rc = refs(text, 'Class(?:es)?')
  (rt - dt).sort.each { |n| flag("#{name}: this.#{n}Target used but '#{n}' not in static targets") }
  (rv - dv).sort.each { |n| flag("#{name}: this.#{n}Value used but '#{n}' not in static values") }
  (rc - dc).sort.each { |n| flag("#{name}: this.#{n}Class(es) used but '#{n}' not in static classes") }

  # 2. cleanup parity
  leaky = text.match?(/addEventListener|setInterval|setTimeout|new\s+(Mutation|Intersection|Resize)Observer/)
  has_disconnect = text.match?(/\bdisconnect\s*\(/)
  if leaky && !has_disconnect
    kinds = text.scan(/addEventListener|setInterval|setTimeout|(?:Mutation|Intersection|Resize)Observer/).uniq.sort.join(', ')
    flag("#{name}: registers [#{kinds}] but has no disconnect() — leaks / double-fires after Turbo navigation. Remove it in disconnect().")
  end

  # 3. registration
  if manifest
    import_path = './' + rel.sub(/\.[^.]*\z/, '')
    unless index_text.include?(import_path) || index_text.include?(import_path.tr('\\', '/'))
      flag("#{name}: not registered in index.js manifest (#{import_path}) — it will never connect")
    end
  end
end

if $fail == 0
  ok("all controllers: targets/values/classes declared, cleanup present, registered")
end
puts
puts($fail == 0 ? "✅ Stimulus controllers OK" : "❌ Stimulus findings above — see references/stimulus-guide.md")
exit $fail
RUBY
