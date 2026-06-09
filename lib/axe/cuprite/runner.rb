# frozen_string_literal: true

require "axe/cuprite/normalize"

module AxeCuprite
  # Framework-agnostic entry point. No RSpec required.
  #
  #   results = AxeCuprite::Runner.new(page).run(
  #     context: "#main",
  #     options: { runOnly: { type: "rule", values: ["color-contrast"] } }
  #   )
  #   results.violations  # => [AxeCuprite::Violation, ...]
  #
  # `page` is a Capybara session (e.g. the `page` in a Capybara test).
  class Runner
    attr_reader :page, :configuration

    def initialize(page, configuration: AxeCuprite.configuration)
      @page = page
      @configuration = configuration
      @injector = Injector.new(page, configuration)
    end

    # Inject axe if not already present, run axe.run(context, options) via the
    # async path, and return an AxeCuprite::Results.
    #
    # - context: axe context arg — a CSS selector String, or a Hash with
    #   :include / :exclude, or nil for the whole document.
    # - options: axe run options Hash (runOnly, rules, resultTypes, ...).
    #   Deep-merged on top of the configured default_options.
    # - timeout: override the configured axe timeout (seconds) for this run.
    def run(context: nil, options: {}, timeout: nil)
      merged = merge_options(options)
      @injector.run(context: normalize_context(context), options: merged, timeout: timeout)
    end

    # Force or ensure axe is injected (idempotent unless force: true). Useful
    # when auto_inject is disabled, or to re-inject after a navigation.
    def inject!(force: false)
      @injector.ensure_injected!(force: force)
    end

    # Is axe-core present on the current page?
    def injected?
      @injector.injected?
    end

    private

    # Apply global configuration (default_options, default_tags, skip_rules)
    # underneath the caller-supplied options, which always win on conflict.
    def merge_options(caller_options)
      opts = deep_stringify(@configuration.default_options)
      opts = deep_merge(opts, deep_stringify(caller_options))

      # default_tags become a tag-based runOnly, but only if nothing already
      # scopes runOnly (an explicit rule/tag selection takes precedence).
      tags = Normalize.tags(@configuration.default_tags)
      opts["runOnly"] = { "type" => "tag", "values" => tags } if !opts.key?("runOnly") && !tags.empty?

      # global skip_rules disable rules, without clobbering an explicit caller
      # setting for the same rule.
      skip = Normalize.rules(@configuration.skip_rules)
      unless skip.empty?
        rules = opts["rules"] || {}
        skip.each { |id| rules[id] ||= { "enabled" => false } }
        opts["rules"] = rules
      end

      opts
    end

    # axe accepts a selector string, or {include:, exclude:}. Stringify hash
    # keys so Ferrum serializes them predictably across CDP.
    def normalize_context(context)
      case context
      when nil, String then context
      when Hash then deep_stringify(context)
      else context
      end
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array
        value.map { |v| deep_stringify(v) }
      else
        value
      end
    end

    def deep_merge(base, override)
      base.merge(override) do |_key, a, b|
        a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge(a, b) : b
      end
    end
  end
end
