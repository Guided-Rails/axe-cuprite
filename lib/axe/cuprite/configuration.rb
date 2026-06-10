# frozen_string_literal: true

require "logger"

module AxeCuprite
  # Global configuration for axe-cuprite. Accessed via AxeCuprite.configure.
  class Configuration
    # Maximum time (seconds) to wait for axe.run to resolve. This is decoupled
    # from Capybara.default_max_wait_time — see Injector. Default 30s because
    # axe.run on a large page routinely exceeds Capybara's 2s default.
    attr_accessor :timeout

    # Default axe run options merged into every run (e.g. { resultTypes: [...] }).
    # Caller / matcher options are deep-merged on top of these.
    attr_accessor :default_options

    # Default axe tags applied when no explicit rule/tag scoping is given,
    # e.g. ["wcag2a", "wcag2aa"]. Empty means "run all default rules".
    attr_accessor :default_tags

    # Global list of rule ids (or symbols) to disable on every run, e.g.
    # [:color_contrast, "region"]. Normalized underscores -> hyphens.
    attr_accessor :skip_rules

    # When true, axe is (re)injected on every #run if missing. Injection is
    # always idempotent (guarded on `typeof window.axe`), so this mainly
    # controls whether a stale axe (after navigation) is re-injected.
    attr_accessor :auto_inject

    # When true, the matcher logs violations instead of failing the example.
    # Eases incremental adoption on an existing app.
    attr_accessor :report_only

    # Logger used for report_only output and warnings.
    attr_accessor :logger

    # When true (default), failure messages and report_only logs include a
    # truncated outer-HTML snippet of each offending element. Set to false to
    # suppress those snippets (rule id + selector + check message only) on
    # suites that render sensitive data, so page content can't leak into CI
    # logs. See BeAxeClean#format_node.
    attr_accessor :include_html

    def initialize
      @timeout         = 30
      @default_options = {}
      @default_tags    = []
      @skip_rules      = []
      @auto_inject     = true
      @report_only     = false
      @include_html    = true
      @logger          = default_logger
    end

    private

    def default_logger
      Logger.new($stdout).tap do |log|
        log.progname = "axe-cuprite"
        log.formatter = proc { |severity, _time, progname, msg| "[#{progname}] #{severity}: #{msg}\n" }
      end
    end
  end
end
