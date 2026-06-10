# frozen_string_literal: true

require "spec_helper"

RSpec.describe AxeCuprite::Runner do
  it "returns typed result objects with contrast data" do
    visit "/bad_contrast"
    results = described_class.new(page).run(
      options: { runOnly: { type: "rule", values: ["color-contrast"] } }
    )

    expect(results).to be_a(AxeCuprite::Results)
    expect(results.violations).not_to be_empty

    violation = results.violations.first
    expect(violation).to be_a(AxeCuprite::Violation)
    expect(violation.id).to eq("color-contrast")
    expect(violation.color_contrast?).to be(true)

    node = violation.nodes.first
    expect(node).to be_a(AxeCuprite::Node)
    expect(node.selector).to include("#faded")

    cd = node.contrast_data
    expect(cd).to be_a(AxeCuprite::ContrastData)
    expect(cd.contrast_ratio.to_f).to be < 4.5
    expect(cd.expected_contrast_ratio.to_f).to eq(4.5)
    expect(cd.bg_color.to_s.downcase).to include("#ffffff")
  end

  it "is clean on the passing fixture" do
    visit "/passing"
    expect(described_class.new(page).run.passes?).to be(true)
  end

  describe "idempotent injection" do
    it "injects axe only once across repeated runs on one page" do
      visit "/passing"
      calls = 0
      allow_any_instance_of(AxeCuprite::Injector)
        .to receive(:inject_source!).and_wrap_original do |original, *args|
          calls += 1
          original.call(*args)
        end

      runner = described_class.new(page)
      runner.run
      runner.run

      expect(runner.injected?).to be(true)
      expect(calls).to eq(1)
    end

    it "does not re-inject across two separate matcher assertions" do
      visit "/passing"
      calls = 0
      allow_any_instance_of(AxeCuprite::Injector)
        .to receive(:inject_source!).and_wrap_original do |original, *args|
          calls += 1
          original.call(*args)
        end

      expect(page).to be_axe_clean
      expect(page).to be_axe_clean

      expect(calls).to eq(1)
    end
  end

  describe "timeout handling" do
    it "uses its own timeout, decoupled from Capybara.default_max_wait_time" do
      visit "/passing"
      # A 1ms Capybara wait would time out evaluate_async_script; the Ferrum
      # fast-path uses our explicit 15s instead, so this still completes.
      Capybara.using_wait_time(0.001) do
        results = described_class.new(page).run(timeout: 15)
        expect(results.passes?).to be(true)
      end
    end

    it "raises TimeoutError when axe cannot finish within the timeout" do
      visit "/bad_contrast"
      expect do
        described_class.new(page).run(timeout: 0.001)
      end.to raise_error(AxeCuprite::TimeoutError, /did not finish within/)
    end
  end

  describe "incomplete (needs-review) results" do
    it "exposes nodes axe could not decide on, without failing" do
      visit "/incomplete"
      results = described_class.new(page).run(
        options: { runOnly: { type: "rule", values: ["color-contrast"] } }
      )

      # The gradient background can't be resolved, so color-contrast lands in
      # `incomplete` rather than `violations` — surfaced for review, never failed.
      expect(results.passes?).to be(true)
      expect(results.incomplete).not_to be_empty
      expect(results.incomplete.first).to be_a(AxeCuprite::Violation)
      expect(results.incomplete.map(&:id)).to include("color-contrast")
    end
  end

  describe "Content-Security-Policy" do
    it "still injects and detects violations under a strict CSP" do
      visit "/csp"
      results = described_class.new(page).run(
        options: { runOnly: { type: "rule", values: ["color-contrast"] } }
      )
      expect(results.violations.map(&:id)).to include("color-contrast")
    end
  end

  describe "global configuration" do
    it "applies a global skip-list" do
      AxeCuprite.configure { |c| c.skip_rules = [:color_contrast] }
      visit "/bad_contrast"
      expect(described_class.new(page).run.passes?).to be(true)
    end

    describe "default_tags" do
      it "scopes the run to the configured tags" do
        AxeCuprite.configure { |c| c.default_tags = [:best_practice] }
        visit "/bad_contrast"
        # color-contrast is a wcag2aa rule, not best-practice, so scoping the run
        # to best-practice tags leaves nothing failing on this page.
        expect(described_class.new(page).run.passes?).to be(true)
      end

      it "is ignored when the caller already scopes runOnly" do
        AxeCuprite.configure { |c| c.default_tags = [:best_practice] }
        visit "/bad_contrast"
        # The caller's rule-scoped runOnly takes precedence; default_tags is not
        # applied, so color-contrast still runs and fails.
        results = described_class.new(page).run(
          options: { runOnly: { type: "rule", values: ["color-contrast"] } }
        )
        expect(results.passes?).to be(false)
      end
    end

    describe "default_options" do
      it "merges beneath caller options, the caller winning on a conflicting key" do
        AxeCuprite.configure do |c|
          c.default_options = { runOnly: { type: "rule", values: ["color-contrast"] } }
        end
        visit "/bad_contrast"
        # The default would scope to (failing) color-contrast; the caller's runOnly
        # overrides it, scoping to a rule that can't fail on this page.
        results = described_class.new(page).run(
          options: { runOnly: { type: "rule", values: ["image-alt"] } }
        )
        expect(results.passes?).to be(true)
      end

      it "deep-merges nested option hashes rather than replacing them" do
        AxeCuprite.configure do |c|
          c.default_options = { rules: { "color-contrast" => { enabled: false } } }
        end
        visit "/bad_contrast"
        # The caller disables a different rule. A shallow merge would drop the
        # default's color-contrast entry and the page would fail; it passes only
        # if the nested `rules` hashes merge and both stay disabled.
        results = described_class.new(page).run(
          options: { rules: { "region" => { enabled: false } } }
        )
        expect(results.passes?).to be(true)
      end
    end

    it "raises InjectionError when auto_inject is off and axe is absent" do
      AxeCuprite.configure { |c| c.auto_inject = false }
      visit "/passing"
      expect do
        described_class.new(page).run
      end.to raise_error(AxeCuprite::InjectionError, /auto_inject is disabled/)
    end

    it "works when auto_inject is off but inject! was called explicitly" do
      AxeCuprite.configure { |c| c.auto_inject = false }
      visit "/passing"
      runner = described_class.new(page)
      runner.inject!
      expect(runner.run.passes?).to be(true)
    end
  end
end
