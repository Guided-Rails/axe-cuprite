# frozen_string_literal: true

module AxeCuprite
  # Recursively freezes a parsed-JSON tree (hashes/arrays of scalars) so the
  # read-only wrappers below can hand out `raw`/`to_h` without a caller being
  # able to mutate internal state (which, via memoization, could otherwise
  # desync `violations`/`incomplete` from `raw`). Idempotent and cheap on the
  # slimmed payload we carry back.
  module DeepFreeze
    module_function

    def call(obj)
      case obj
      when Hash
        obj.each { |k, v| [k, v].each { |o| call(o) } }
      when Array
        obj.each { |v| call(v) }
      end
      obj.freeze
    end
  end

  # Wraps the (slimmed) payload returned by axe.run. We deliberately only carry
  # `violations` and `incomplete` across the CDP boundary plus a little metadata
  # — the full results object (with `passes`/`inapplicable`) can be huge.
  #
  # The wrappers are read-only: `@raw` is deep-frozen at construction, so `raw`
  # and `to_h` expose the live underlying hash safely (callers cannot mutate it).
  #
  # Ownership note: `Results` (and the nested `Violation`/`Node`/`ContrastData`
  # wrappers) **take ownership of the hash passed in and deep-freeze it in place**
  # — they do not copy first. For the internal flow this is safe (the payload
  # comes fresh off the CDP boundary), but if you construct `Results.new(hash)`
  # yourself, don't pass — or hold onto — a hash you intend to mutate afterward,
  # or you'll hit a `FrozenError`. Dup it first if you need a mutable copy.
  class Results
    attr_reader :raw

    def initialize(raw)
      @raw = DeepFreeze.call(raw || {})
    end

    def violations
      @violations ||= Array(@raw["violations"]).map { |v| Violation.new(v) }
    end

    # Nodes axe could not decide on (needs review). Surfaced but never fails.
    def incomplete
      @incomplete ||= Array(@raw["incomplete"]).map { |v| Violation.new(v) }
    end

    def passes?
      violations.empty?
    end
    alias clean? passes?

    def url
      @raw["url"]
    end

    def timestamp
      @raw["timestamp"]
    end

    def test_engine
      @raw["testEngine"]
    end

    def to_h
      @raw
    end
  end

  # A single axe rule violation, with one or more offending nodes.
  class Violation
    attr_reader :raw

    def initialize(raw)
      @raw = DeepFreeze.call(raw || {})
    end

    def id
      @raw["id"]
    end

    def impact
      @raw["impact"]
    end

    def description
      @raw["description"]
    end

    def help
      @raw["help"]
    end

    def help_url
      @raw["helpUrl"]
    end

    def tags
      Array(@raw["tags"])
    end

    def nodes
      @nodes ||= Array(@raw["nodes"]).map { |n| Node.new(n) }
    end

    def color_contrast?
      id == "color-contrast"
    end
  end

  # A single offending DOM node within a violation.
  class Node
    attr_reader :raw

    def initialize(raw)
      @raw = DeepFreeze.call(raw || {})
    end

    # axe gives `target` as an array of CSS selectors (one per frame depth).
    def target
      Array(@raw["target"])
    end

    def selector
      target.join(" ")
    end

    # The offending element's outer HTML (already truncated by axe).
    def html
      @raw["html"]
    end

    def failure_summary
      @raw["failureSummary"]
    end

    # The check results that caused/contributed to the failure.
    def any
      Array(@raw["any"])
    end

    def all
      Array(@raw["all"])
    end

    def none
      Array(@raw["none"])
    end

    # For color-contrast violations axe stores rich data under any[].data.
    # Returns a ContrastData (or nil if this node has no contrast data).
    def contrast_data
      check = any.find { |c| c.is_a?(Hash) && c["data"].is_a?(Hash) && c["data"].key?("contrastRatio") }
      return nil unless check

      ContrastData.new(check["data"])
    end
  end

  # Typed view over a color-contrast check's `data` hash.
  class ContrastData
    attr_reader :raw

    def initialize(raw)
      @raw = DeepFreeze.call(raw || {})
    end

    def fg_color
      @raw["fgColor"]
    end

    def bg_color
      @raw["bgColor"]
    end

    def contrast_ratio
      @raw["contrastRatio"]
    end

    def expected_contrast_ratio
      @raw["expectedContrastRatio"]
    end

    def font_size
      @raw["fontSize"]
    end

    def font_weight
      @raw["fontWeight"]
    end
  end
end
