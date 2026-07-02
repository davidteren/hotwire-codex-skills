#!/usr/bin/env bash
# Validate a Hotwire Native path-configuration JSON (schema + footguns), and
# optionally diff two configs (iOS vs Android) for path-coverage drift.
#
# Usage:
#   lint_path_config.sh <config.json> [config2.json]   # validate one or two
#   lint_path_config.sh --compare <iosA.json> <androidB.json>
#
# Exit: 0 = clean, 1 = problems, 2 = bad usage / no ruby.
set -uo pipefail
command -v ruby >/dev/null || { echo "needs ruby" >&2; exit 2; }

[ $# -ge 1 ] || { echo "usage: $0 <config.json> [config2.json] | --compare A B" >&2; exit 2; }

ruby - "$@" <<'RUBY'
require 'json'
require 'set'

VALID_CONTEXT = %w[default modal].to_set
VALID_PRESENTATION = %w[default push pop replace replace_root clear_all refresh none].to_set
KNOWN_PROPS = %w[
  context presentation pull_to_refresh_enabled animated
  uri fallback_uri title
  view_controller modal_style modal_dismiss_gesture_enabled
].to_set
# universal / android / ios (same grouping as the 1.x docs)
VALID_MODAL_STYLE = %w[large medium full page_sheet form_sheet].to_set

$fail = 0
def flag(m) $fail = 1; puts "  ⚠️  #{m}" end
def ok(m) puts "  ✓ #{m}" end
def rep(x)                                                       # python-repr-style
  case x
  when String then "'#{x}'"
  when true   then "True"
  when false  then "False"
  when nil    then "None"
  else x.inspect
  end
end
def lst(s) "[" + s.sort.map { |x| "'#{x}'" }.join(", ") + "]" end # python-list-style

CATCH_ALL = [".*", "/.*", "^.*$", "^/.*"].freeze

def load_cfg(path)
  JSON.parse(File.read(path))
end

def validate(path, cfg)
  puts "Validating #{path}"
  unless cfg.is_a?(Hash)
    flag("top level is not an object"); return Set.new
  end
  if !cfg.key?("rules") || !cfg["rules"].is_a?(Array) || cfg["rules"].empty?
    flag("missing or empty 'rules' array"); return Set.new
  end
  if cfg.key?("settings") && !cfg["settings"].is_a?(Hash)
    flag("'settings' is not an object")
  end
  all_patterns = Set.new
  catchall_first = false
  cfg["rules"].each_with_index do |rule, i|
    where = "rule[#{i}]"
    unless rule.is_a?(Hash) && rule.key?("patterns") && rule.key?("properties")
      flag("#{where}: each rule needs 'patterns' and 'properties'"); next
    end
    pats = rule["patterns"]; props = rule["properties"]
    unless pats.is_a?(Array) && !pats.empty?
      flag("#{where}: 'patterns' must be a non-empty array")
    end
    (pats.is_a?(Array) ? pats : []).each do |p|
      all_patterns << p
      begin
        Regexp.new(p)
      rescue RegexpError => e
        flag("#{where}: pattern #{rep(p)} is not valid regex (#{e})")
      end
      # footgun: unanchored short path segment
      if p.match?(%r{\A/[a-z_]+\z})
        flag("#{where}: pattern #{rep(p)} is unanchored — '/new' also matches '/renew'; use '#{p}$'")
      end
      catchall_first = true if i.zero? && CATCH_ALL.include?(p)
    end
    unless props.is_a?(Hash)
      flag("#{where}: 'properties' must be an object"); next
    end
    props.each do |k, v|
      unless KNOWN_PROPS.include?(k)
        flag("#{where}: unknown property #{rep(k)} (typo? not in the 1.x schema)")
      end
      if k == "context" && !VALID_CONTEXT.include?(v)
        flag("#{where}: context=#{rep(v)} invalid (use #{lst(VALID_CONTEXT)})")
      end
      if k == "presentation"
        if v == "modal"
          flag("#{where}: presentation='modal' is a Strada-beta-ism — in 1.x use context='modal'")
        elsif !VALID_PRESENTATION.include?(v)
          flag("#{where}: presentation=#{rep(v)} invalid (use #{lst(VALID_PRESENTATION)})")
        end
      end
      if k == "modal_style" && !VALID_MODAL_STYLE.include?(v)
        flag("#{where}: modal_style=#{rep(v)} invalid")
      end
    end
    # android needs a uri on each navigable rule
  end
  if catchall_first
    ok("catch-all rule is first (specific rules below override it)")
  else
    # not fatal, but the most common ordering mistake
    rule0 = cfg["rules"][0]
    first_pats = rule0.is_a?(Hash) ? (rule0["patterns"] || []) : []
    unless first_pats.is_a?(Array) && first_pats.any? { |p| CATCH_ALL.include?(p) }
      flag("first rule is not a broad catch-all — rules are matched top-to-bottom with LATER winning; confirm ordering is intentional")
    end
  end
  if $fail == 0
    ok("schema valid")
  end
  all_patterns
end

args = ARGV
if args[0] == "--compare"
  if args.length != 3
    $stderr.puts "usage: --compare A B"; exit 2
  end
  a, b = args[1], args[2]
  pa = validate(a, load_cfg(a)); puts
  pb = validate(b, load_cfg(b)); puts
  puts "Cross-config path coverage (anchors normalized — ceiling: not full semantic regex equivalence) —"
  norm = lambda do |p|
    p = p.strip
    p = p[1..]    if p.start_with?("^")
    p = p[0..-2]  if p.end_with?("$")
    p = p.sub(/\*+\z/, "").gsub(%r{\A/+|/+\z}, "")
    ["", ".", ".*"].include?(p) ? "<catch-all>" : p
  end
  na = pa.each_with_object({}) { |p, h| h[norm.call(p)] = p }
  nb = pb.each_with_object({}) { |p, h| h[norm.call(p)] = p }
  only_a = (na.keys - nb.keys).sort
  only_b = (nb.keys - na.keys).sort
  only_a.each { |k| flag("path #{rep(na[k])} handled in #{a} but not #{b} — platforms navigate it differently") }
  only_b.each { |k| flag("path #{rep(nb[k])} handled in #{b} but not #{a} — platforms navigate it differently") }
  if only_a.empty? && only_b.empty?
    ok("both configs cover the same paths (after anchor normalization)")
  end
else
  args.each do |path|
    validate(path, load_cfg(path)); puts
  end
end

puts($fail == 0 ? "✅ path config OK" : "❌ path config issues found")
exit $fail
RUBY
