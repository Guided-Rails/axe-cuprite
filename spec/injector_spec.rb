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

    # Ferrum reports a JS error from a Runtime.evaluate response.
    def ferrum_js_error(message)
      Ferrum::JavaScriptError.new("text" => message)
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
end
