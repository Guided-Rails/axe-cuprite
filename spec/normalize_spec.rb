# frozen_string_literal: true

require "spec_helper"

RSpec.describe AxeCuprite::Normalize do
  it "normalizes rule ids (underscores <-> hyphens)" do
    expect(described_class.rule(:color_contrast)).to eq("color-contrast")
    expect(described_class.rule("color-contrast")).to eq("color-contrast")
    expect(described_class.rules([:color_contrast, "image-alt"])).to eq(%w[color-contrast image-alt])
  end

  it "normalizes tags" do
    expect(described_class.tag(:wcag2aa)).to eq("wcag2aa")
    expect(described_class.tag(:best_practice)).to eq("best-practice")
    expect(described_class.tags([:wcag2aa, :best_practice])).to eq(%w[wcag2aa best-practice])
  end
end
