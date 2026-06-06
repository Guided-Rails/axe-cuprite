# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "logger"

RSpec.describe "be_axe_clean matcher" do
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
        expect(msg).to match(/fg #/)
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

      expect(io.string).to match(/report_only/)
      expect(io.string).to include("color-contrast")
    end
  end
end
