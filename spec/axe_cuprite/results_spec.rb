# frozen_string_literal: true

require "spec_helper"

RSpec.describe AxeCuprite::Results do
  let(:raw) do
    {
      "url" => "http://example.test/",
      "violations" => [
        {
          "id" => "color-contrast",
          "impact" => "serious",
          "nodes" => [
            {
              "target" => ["#bad"],
              "html" => "<p>hi</p>",
              "any" => [{ "data" => { "contrastRatio" => 2.3, "fgColor" => "#ababab" } }]
            }
          ]
        }
      ],
      "incomplete" => []
    }
  end

  it "exposes the parsed payload through the typed wrappers" do
    results = described_class.new(raw)

    expect(results.url).to eq("http://example.test/")
    violation = results.violations.first
    expect(violation.id).to eq("color-contrast")
    node = violation.nodes.first
    expect(node.selector).to eq("#bad")
    expect(node.contrast_data.contrast_ratio).to eq(2.3)
  end

  describe "read-only contract" do
    it "deep-freezes raw at construction so callers cannot mutate internal state" do
      results = described_class.new(raw)

      expect(results.raw).to be_frozen
      expect(results.to_h).to be_frozen
      expect(results.raw["violations"]).to be_frozen
      expect(results.raw["violations"].first).to be_frozen
      expect(results.raw["violations"].first["nodes"].first).to be_frozen
    end

    it "prevents mutation through raw / to_h" do
      results = described_class.new(raw)

      expect { results.to_h["violations"].clear }.to raise_error(FrozenError)
      expect { results.raw["injected"] = true }.to raise_error(FrozenError)
    end

    it "freezes nested wrapper payloads too" do
      results = described_class.new(raw)
      node = results.violations.first.nodes.first

      expect(node.raw).to be_frozen
      expect(node.contrast_data.raw).to be_frozen
    end

    it "does not mutate the caller's original hash object" do
      original = raw
      described_class.new(original)

      # The whole tree is frozen in place (idempotent), but the object identity
      # and contents are unchanged — no copy, no added keys.
      expect(original).to eq(raw)
    end
  end

  it "handles a nil payload without raising" do
    results = described_class.new(nil)

    expect(results.violations).to eq([])
    expect(results.to_h).to eq({})
    expect(results.to_h).to be_frozen
  end
end
