# frozen_string_literal: true

require "spec_helper"

RSpec.describe AxeCuprite::Injector do
  describe "#timeout_error?" do
    it "treats Ferrum::TimeoutError as a timeout" do
      error = Ferrum::TimeoutError.new
      injector = described_class.new(nil)

      result = injector.send(:timeout_error?, error)

      expect(result).to be(true)
    end

    it "treats Ferrum::ScriptTimeoutError as a timeout" do
      error = Ferrum::ScriptTimeoutError.new
      injector = described_class.new(nil)

      result = injector.send(:timeout_error?, error)

      expect(result).to be(true)
    end

    it "treats a Ferrum::JavaScriptError carrying 'timed out promise' as a timeout" do
      error = ferrum_js_error("Error: timed out promise")
      injector = described_class.new(nil)

      result = injector.send(:timeout_error?, error)

      expect(result).to be(true)
    end

    it "does NOT treat a real JS error whose message merely contains 'timeout' as a timeout" do
      error = ferrum_js_error("TypeError: Cannot read properties of null (reading 'timeout')")
      injector = described_class.new(nil)

      result = injector.send(:timeout_error?, error)

      expect(result).to be(false)
    end

    it "does NOT treat an arbitrary StandardError mentioning 'timed out' as a timeout" do
      error = StandardError.new("the request timed out somewhere")
      injector = described_class.new(nil)

      result = injector.send(:timeout_error?, error)

      expect(result).to be(false)
    end
  end

  describe "#evaluate_axe" do
    it "falls back to evaluate_async_script with the run JS and args" do
      page = instance_double(Capybara::Session, driver: Object.new)
      expected_result = { "violations" => [], "incomplete" => [] }
      allow(page).to receive(:evaluate_async_script).and_return(expected_result)
      injector = described_class.new(page)

      result = injector.send(
        :evaluate_axe,
        { include: [["#main"]] },
        { runOnly: "color-contrast" },
        17
      )

      expect(result).to eq(expected_result)
      expect(page).to have_received(:evaluate_async_script)
        .with(
          described_class::RUN_JS,
          { include: [["#main"]] },
          { runOnly: "color-contrast" }
        )
    end

    it "runs under the explicit timeout, not Capybara.default_max_wait_time" do
      page = instance_double(Capybara::Session, driver: Object.new)
      Capybara.default_max_wait_time = 2
      observed_wait = nil
      allow(page).to receive(:evaluate_async_script) do
        observed_wait = Capybara.default_max_wait_time
        { "violations" => [], "incomplete" => [] }
      end
      injector = described_class.new(page)

      injector.send(
        :evaluate_axe,
        { include: [["#main"]] },
        { runOnly: "color-contrast" },
        17
      )

      expect(observed_wait).to eq(17)
      expect(Capybara.default_max_wait_time).to eq(2)
    end
  end

  def ferrum_js_error(message)
    error = Ferrum::JavaScriptError.allocate
    allow(error).to receive(:message).and_return(message)
    error
  end
end
