# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "logger"

RSpec.describe AxeCuprite::RSpec::BeAxeClean do
  it "passes on an accessible page" do
    visit "/passing"
    expect(page).to be_axe_clean
  end

  it "is also available as be_accessible" do
    visit "/passing"
    expect(page).to be_accessible
  end

  describe "color-contrast (the headline case)" do
    it "detects the opacity-induced failure with actionable output" do
      visit "/bad_contrast"
      matcher = be_axe_clean.checking_only(:color_contrast)

      expect(matcher.matches?(page)).to be(false)

      msg = matcher.failure_message
      aggregate_failures do
        expect(msg).to include("color-contrast")
        expect(msg).to match(/contrast \d+(\.\d+)?:1/)
        expect(msg).to include("needs 4.5:1")
        expect(msg).to include("fg #")
        expect(msg.downcase).to include("on bg #ffffff")
        expect(msg).to include("#faded")
        expect(msg).to match(/serious|moderate/) # impact label
      end
    end

    it "accepts the hyphenated axe id" do
      visit "/bad_contrast"
      expect(page).not_to be_axe_clean.checking_only("color-contrast")
    end
  end

  describe "scoping and rule-selection DSL" do
    before { visit "/mixed" }

    it "within a clean region passes" do
      expect(page).to be_axe_clean.within("#good")
    end

    it "within a bad region fails" do
      expect(page).not_to be_axe_clean.within("#bad")
    end

    it "excluding the bad region passes" do
      expect(page).to be_axe_clean.excluding("#bad")
    end

    it "skipping the failing rule passes" do
      expect(page).to be_axe_clean.skipping(:color_contrast)
    end

    it "according_to(:best_practice) passes (no best-practice violations)" do
      expect(page).to be_axe_clean.according_to(:best_practice)
    end

    it "according_to(:wcag2aa) fails (contrast is a wcag2aa rule)" do
      expect(page).not_to be_axe_clean.according_to(:wcag2aa)
    end

    it "rejects combining checking_only and according_to" do
      expect do
        be_axe_clean.checking_only(:color_contrast).according_to(:wcag2aa).matches?(page)
      end.to raise_error(ArgumentError, /not both/)
    end

    it "accepts multiple within selectors (include-array branch)" do
      expect(page).to be_axe_clean.within("#good", "h1")
    end

    it "fails when any of multiple within selectors is offending" do
      expect(page).not_to be_axe_clean.within("#good", "#bad")
    end

    it "combines within and excluding (dual-key context)" do
      expect(page).to be_axe_clean.within("main").excluding("#bad")
    end

    it "still fails when excluding leaves the offending region in scope" do
      expect(page).not_to be_axe_clean.within("main").excluding("#good")
    end
  end

  describe "raw options and timeout chaining" do
    it "with_options injects raw axe options (disabling a rule)" do
      visit "/bad_contrast"
      expect(page).to be_axe_clean.with_options(rules: { "color-contrast" => { enabled: false } })
    end

    it "with_options can scope the run via a raw runOnly" do
      visit "/bad_contrast"
      expect(page).not_to be_axe_clean.with_options(
        runOnly: { type: "rule", values: ["color-contrast"] }
      )
    end

    it "with_timeout overrides the axe timeout for the assertion" do
      visit "/bad_contrast"
      expect do
        be_axe_clean.with_timeout(0.001).matches?(page)
      end.to raise_error(AxeCuprite::TimeoutError, /did not finish within/)
    end
  end

  describe "negation" do
    it "fails (with a clear message) when negated on a clean page" do
      visit "/passing"
      expect do
        expect(page).not_to be_axe_clean
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /clean/)
    end
  end

  describe "report_only mode" do
    it "passes but logs violations instead of failing the example" do
      io = StringIO.new
      AxeCuprite.configure do |c|
        c.report_only = true
        c.logger = Logger.new(io)
      end

      visit "/bad_contrast"
      expect(page).to be_axe_clean.checking_only(:color_contrast)

      expect(io.string).to include("report_only")
      expect(io.string).to include("color-contrast")
    end
  end

  describe "include_html config" do
    before { visit "/bad_contrast" }

    it "includes the offending element's HTML snippet in failure messages by default" do
      matcher = be_axe_clean.checking_only(:color_contrast)
      expect(matcher.matches?(page)).to be(false)

      msg = matcher.failure_message
      aggregate_failures do
        expect(msg).to include("#faded")          # selector — always present
        expect(msg).to match(/<\w+/)              # an HTML tag snippet
      end
    end

    it "suppresses HTML snippets when include_html = false" do
      AxeCuprite.configure { |c| c.include_html = false }

      matcher = be_axe_clean.checking_only(:color_contrast)
      expect(matcher.matches?(page)).to be(false)

      msg = matcher.failure_message
      aggregate_failures do
        expect(msg).to include("#faded")          # selector still shown
        expect(msg).to include("color-contrast")  # rule id still shown
        expect(msg).not_to match(/<\w+/)          # but no raw HTML tag
      end
    end

    it "suppresses HTML snippets in report_only logs when include_html = false" do
      io = StringIO.new
      AxeCuprite.configure do |c|
        c.report_only  = true
        c.include_html = false
        c.logger       = Logger.new(io)
      end

      expect(page).to be_axe_clean.checking_only(:color_contrast)

      aggregate_failures do
        expect(io.string).to include("color-contrast")
        expect(io.string).not_to match(/<\w+/)
      end
    end
  end
end
