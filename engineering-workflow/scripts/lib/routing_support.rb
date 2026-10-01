# frozen_string_literal: true

# Shared helpers for model-routing and codex-delegate: a minimal TOML reader
# and requested/resolved/observed accounting.

module RoutingSupport
  module_function

  # Minimal TOML reader for flat keys, [tables] and triple-quoted strings.
  # Enough for agent role files and config.toml keys; not a general parser.
  def read_toml(path)
    return nil unless File.exist?(path)
    parse_toml(File.read(path))
  end

  def parse_toml(text)
    data = {}
    table = data
    multiline_key = nil
    buffer = nil
    text.each_line do |raw|
      if multiline_key
        if (idx = raw.index('"""'))
          buffer << raw[0...idx]
          table[multiline_key] = buffer.sub(/\A\n/, "")
          multiline_key = nil
        else
          buffer << raw
        end
        next
      end
      line = raw.strip
      next if line.empty? || line.start_with?("#")
      if (m = line.match(/\A\[\[?([^\]]+)\]\]?\z/))
        table = m[1].split(".").reduce(data) { |h, k| h[k.strip.delete('"')] ||= {} }
        next
      end
      next unless (m = line.match(/\A([A-Za-z0-9_.\-"]+)\s*=\s*(.*)\z/))
      key = m[1].delete('"')
      value = m[2]
      if value.start_with?('"""')
        rest = value[3..]
        if (idx = rest.index('"""'))
          table[key] = rest[0...idx]
        else
          multiline_key = key
          buffer = +"#{rest}\n"
        end
        next
      end
      value = value.sub(/\s+#.*\z/, "")
      table[key] =
        case value
        when /\A"(.*)"\z/, /\A'(.*)'\z/ then Regexp.last_match(1)
        when "true" then true
        when "false" then false
        when /\A-?\d+\z/ then value.to_i
        else value
        end
    end
    data
  end

  FIELDS = %w[model effort service_tier sandbox].freeze

  # Compares what the caller asked for, what the launcher configured, and what
  # the runtime reported. Evidence is attributed to the observed model; a
  # mismatch is recorded and warned, never silently counted for the request.
  def account(requested:, resolved:, observed:)
    warnings = []
    mismatches = {}
    FIELDS.each do |f|
      want = resolved[f] || requested[f]
      have = observed[f]
      next if want.nil?
      if have.nil?
        warnings << "#{f} not observed (requested #{want}); treat it as unverified"
      elsif have.to_s != want.to_s
        mismatches[f] = { "requested" => requested[f], "resolved" => resolved[f], "observed" => have }
        warnings << "#{f} observed #{have} but #{want} was requested/resolved"
      end
    end
    if requested["model"] && resolved["model"] && requested["model"] != resolved["model"]
      warnings << "resolver changed model #{requested['model']} -> #{resolved['model']} (fallback or alias)"
    end
    {
      "requested" => requested, "resolved" => resolved, "observed" => observed,
      "mismatches" => mismatches, "warnings" => warnings,
      "evidence_model" => observed["model"] || "unobserved",
      "evidence_usable_for_requested" => mismatches.empty? && !observed["model"].nil? &&
                                         observed["model"] == (requested["model"] || resolved["model"])
    }
  end
end
