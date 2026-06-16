# frozen_string_literal: true

require "spec_helper"

RSpec.describe AxeCuprite::Injector do
  # timeout_error? decides whether an evaluation failure is rewritten as a
  # helpful AxeCuprite::TimeoutError or re-raised untouched. It is private; we
  # drive it directly because the distinction is subtle and class-driven.
  describe "#timeout_error? classification" do
    subject(:injector) { described_class.new(nil) }

    def classify(error)
      injector.send(:timeout_error?, error)
    end

    # A Ferrum::JavaScriptError carrying a given message. We stub #message rather
    # than drive Ferrum's constructor: how it derives a message from a CDP
    # response is a private detail that varies across ferrum patch releases, and
    # all timeout_error? looks at is the class name and the message.
    def ferrum_js_error(message)
      error = Ferrum::JavaScriptError.allocate
      allow(error).to receive(:message).and_return(message)
      error
    end

    it "treats Ferrum::TimeoutError as a timeout (the Cuprite fast-path)" do
      # Its own message even mentions a timeout, but the class is what counts.
      expect(classify(Ferrum::TimeoutError.new)).to be(true)
    end

    it "treats Ferrum::ScriptTimeoutError as a timeout (evaluate_async's own timeout)" do
      expect(classify(Ferrum::ScriptTimeoutError.new)).to be(true)
    end

    it "treats a Ferrum::JavaScriptError carrying 'timed out promise' as a timeout" do
      # This is how Ferrum surfaces its async-evaluation (evaluate_async) timeout.
      error = ferrum_js_error("Error: timed out promise")
      expect(classify(error)).to be(true)
    end

    it "does NOT treat a real JS error whose message merely contains 'timeout' as a timeout" do
      # The regression this issue is about: a genuine page-side error from axe or
      # the app whose text happens to mention a timeout must propagate as-is, not
      # get rewritten with misleading 'increase the timeout' guidance.
      error = ferrum_js_error("TypeError: Cannot read properties of null (reading 'timeout')")
      expect(classify(error)).to be(false)
    end

    it "does NOT treat an arbitrary StandardError mentioning 'timed out' as a timeout" do
      expect(classify(StandardError.new("the request timed out somewhere"))).to be(false)
    end
  end

  # The non-Ferrum fallback in #evaluate_axe is best-effort and unsupported (the
  # suite runs under Cuprite, where ferrum_page is always truthy), but it should
  # not silently break. A driver with no #browser makes the real ferrum_page
  # return nil, forcing the fallback; we then assert it routes through
  # evaluate_async_script under our explicit timeout rather than
  # Capybara.default_max_wait_time.
  describe "#evaluate_axe non-Ferrum fallback" do
    subject(:injector) { described_class.new(page) }

    let(:page) { instance_double(Capybara::Session, driver: non_ferrum_driver) }
    let(:non_ferrum_driver) { Object.new } # does not respond to #browser
    let(:context) { { include: [["#main"]] } }
    let(:options) { { runOnly: "color-contrast" } }
    let(:timeout) { 17 }

    def evaluate
      injector.send(:evaluate_axe, context, options, timeout)
    end

    it "falls back to evaluate_async_script with the run JS and args" do
      result = { "violations" => [], "incomplete" => [] }
      allow(page).to receive(:evaluate_async_script).and_return(result)

      expect(evaluate).to eq(result)
      expect(page).to have_received(:evaluate_async_script)
        .with(described_class::RUN_JS, context, options)
    end

    it "runs under the explicit timeout, not Capybara.default_max_wait_time" do
      Capybara.default_max_wait_time = 2
      observed_wait = nil
      allow(page).to receive(:evaluate_async_script) do
        observed_wait = Capybara.default_max_wait_time
        { "violations" => [], "incomplete" => [] }
      end

      evaluate

      expect(observed_wait).to eq(timeout)
      # And the temporary bump is restored afterwards.
      expect(Capybara.default_max_wait_time).to eq(2)
    end
  end
end
