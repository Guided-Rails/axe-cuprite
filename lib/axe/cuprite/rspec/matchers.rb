# frozen_string_literal: true

require "axe/cuprite"
require "axe/cuprite/normalize"

module AxeCuprite
  module RSpec
    # The matcher behind `be_axe_clean` / `be_accessible`.
    #
    #   expect(page).to be_axe_clean
    #   expect(page).to be_axe_clean.checking_only(:color_contrast).within("#main")
    #   expect(page).to be_axe_clean.according_to(:wcag2aa).excluding(".third-party")
    #   expect(page).to be_axe_clean.skipping(:region)
    #
    # All chainers return self so they compose in any order.
    class BeAxeClean
      # Cap how many offending elements we print per rule, to keep failure
      # messages readable on noisy pages.
      MAX_NODES = 5
      # Cap HTML snippet length per node.
      HTML_SNIPPET = 200

      def initialize
        @includes   = []
        @excludes   = []
        @only_rules = []
        @skip_rules = []
        @tags       = []
        @run_options = {}
        @timeout = nil
      end

      # --- chainable DSL ----------------------------------------------------

      # Scope the run to one or more selectors (axe context "include").
      def within(*selectors)
        @includes.concat(selectors.flatten)
        self
      end

      # Exclude one or more selectors from the run (axe context "exclude").
      def excluding(*selectors)
        @excludes.concat(selectors.flatten)
        self
      end

      # Run ONLY these rules. Accepts symbols or axe ids; underscores -> hyphens.
      def checking_only(*rules)
        @only_rules.concat(rules.flatten)
        self
      end

      # Disable these rules for this run (merged with the global skip-list).
      def skipping(*rules)
        @skip_rules.concat(rules.flatten)
        self
      end

      # Restrict the run to axe tags, e.g. :wcag2aa, :wcag21aa, :best_practice.
      def according_to(*tags)
        @tags.concat(tags.flatten)
        self
      end

      # Escape hatch: merge raw axe run options (deep-merged, wins on conflict).
      def with_options(options)
        @run_options = deep_merge(@run_options, options)
        self
      end

      # Override the axe timeout (seconds) for this assertion only.
      def with_timeout(seconds)
        @timeout = seconds
        self
      end

      # --- RSpec protocol ---------------------------------------------------

      def matches?(page)
        run!(page)

        if config.report_only && !@violations.empty?
          config.logger.warn("report_only: #{summary_line}\n#{details}")
          return true
        end

        @violations.empty?
      end

      # Negation ignores report_only: `to_not be_axe_clean` passes iff there
      # really are violations.
      def does_not_match?(page)
        run!(page)
        !@violations.empty?
      end

      def failure_message
        "#{summary_line}\n\n#{details}"
      end

      def failure_message_when_negated
        "expected page to have axe-core accessibility violations, but it was clean " \
          "(0 violations for the selected rules/scope)."
      end

      def description
        "be free of axe-core accessibility violations"
      end

      # Exposed so callers/tests can inspect the full result after matching.
      attr_reader :results, :violations

      private

      def run!(page)
        @results = Runner.new(page, configuration: config).run(
          context: build_context,
          options: build_options,
          timeout: @timeout
        )
        @violations = @results.violations
      end

      def config
        AxeCuprite.configuration
      end

      # --- context / options builders --------------------------------------

      def build_context
        if @excludes.empty?
          return nil if @includes.empty?

          @includes.length == 1 ? @includes.first : { include: @includes }
        else
          ctx = { exclude: @excludes }
          ctx[:include] = @includes unless @includes.empty?
          ctx
        end
      end

      def build_options
        if !@only_rules.empty? && !@tags.empty?
          raise ArgumentError,
                "Use either .checking_only (specific rules) or .according_to (tags), not both."
        end

        opts = {}
        if !@only_rules.empty?
          opts[:runOnly] = { type: "rule", values: Normalize.rules(@only_rules) }
        elsif !@tags.empty?
          opts[:runOnly] = { type: "tag", values: Normalize.tags(@tags) }
        end

        unless @skip_rules.empty?
          opts[:rules] = Normalize.rules(@skip_rules).to_h do |id|
            [id, { enabled: false }]
          end
        end

        deep_merge(opts, @run_options)
      end

      # --- failure message formatting --------------------------------------

      def summary_line
        rule_count = @violations.length
        node_count = @violations.sum { |v| v.nodes.length }
        "expected page to be axe-clean, but found #{rule_count} " \
          "#{pluralize(rule_count, "violation")} across #{node_count} " \
          "#{pluralize(node_count, "element")}:"
      end

      def details
        @violations.map { |v| format_violation(v) }.join("\n\n")
      end

      def format_violation(violation)
        lines = []
        impact = violation.impact || "n/a"
        lines << "  ● [#{impact}] #{violation.id} — #{violation.help} " \
                 "(#{violation.nodes.length} #{pluralize(violation.nodes.length, "element")})"
        lines << "    #{violation.help_url}" if violation.help_url

        violation.nodes.first(MAX_NODES).each do |node|
          lines.concat(format_node(node))
        end

        remaining = violation.nodes.length - MAX_NODES
        lines << "      … and #{remaining} more #{pluralize(remaining, "element")}" if remaining.positive?
        lines.join("\n")
      end

      def format_node(node)
        lines = ["      - #{node.selector}"]
        lines << "        #{truncate(node.html)}" if node.html

        if (cd = node.contrast_data)
          lines << "        contrast #{cd.contrast_ratio}:1 (needs #{cd.expected_contrast_ratio}:1) — " \
                   "fg #{cd.fg_color} on bg #{cd.bg_color}, font #{cd.font_size}/#{cd.font_weight}"
        elsif (msg = first_check_message(node))
          lines << "        #{msg}"
        end
        lines
      end

      def first_check_message(node)
        (node.any + node.none).map { |c| c["message"] if c.is_a?(Hash) }.compact.first
      end

      def truncate(text)
        text = text.to_s.gsub(/\s+/, " ").strip
        text.length > HTML_SNIPPET ? "#{text[0, HTML_SNIPPET]}…" : text
      end

      def pluralize(count, word)
        count == 1 ? word : "#{word}s"
      end

      def deep_merge(base, override)
        base.merge(override) do |_key, a, b|
          a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge(a, b) : b
        end
      end
    end
  end
end
