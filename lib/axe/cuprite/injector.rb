# frozen_string_literal: true

module AxeCuprite
  # Handles getting axe-core onto the page and running it — entirely through
  # Capybara's driver-neutral JS API, with a Ferrum fast-path for Cuprite.
  #
  # This is the make-or-break class. Two things are easy to get wrong:
  #
  #   1. The async-callback convention. Ferrum's `evaluate_async` (and Capybara's
  #      `evaluate_async_script`, which Cuprite delegates to it) wraps your
  #      expression in a Promise and appends the resolve callback as the LAST
  #      entry of `arguments`. So we resolve via `arguments[arguments.length - 1]`.
  #
  #   2. The timeout. Ferrum wraps the promise in a `setTimeout(reject, wait*1000)`.
  #      Through `evaluate_async_script` that `wait` is Capybara.default_max_wait_time
  #      (often 2s) — far too short for `axe.run` on a real page. So on Cuprite we
  #      call Ferrum's `page.evaluate_async(expr, explicit_wait, *args)` DIRECTLY
  #      with our own timeout, decoupled from default_max_wait_time entirely.
  class Injector
    # JS run inside Ferrum's promise wrapper. `arguments[0]` is the axe context,
    # `arguments[1]` the run options, and the LAST argument is the resolve
    # callback Ferrum appended. We slim the result down to a JSON-safe payload —
    # never returning the full results object (passes/inapplicable can be huge).
    RUN_JS = <<~JS
      var ctx = arguments[0];
      var opts = arguments[1] || {};
      var done = arguments[arguments.length - 1];
      if (typeof window.axe === 'undefined' || typeof window.axe.run !== 'function') {
        done({ error: 'axe-core is not present on the page' });
        return;
      }
      var promise = ctx ? window.axe.run(ctx, opts) : window.axe.run(opts);
      promise.then(function (results) {
        done({
          violations: results.violations,
          incomplete: results.incomplete,
          url: results.url,
          timestamp: results.timestamp,
          testEngine: results.testEngine
        });
      }).catch(function (err) {
        done({ error: (err && err.message) ? err.message : String(err) });
      });
    JS

    # JS expression that reports whether axe is loaded and runnable.
    PRESENCE_JS = "typeof window.axe !== 'undefined' && typeof window.axe.run === 'function'"

    # Dedicated timeout classes that mean "the evaluation timed out" regardless
    # of message. Matched by name (not constant) so we keep no hard dependency on
    # ferrum/selenium — both are dev-only deps. Covers Ferrum's own timeouts (the
    # Cuprite fast-path, via page.evaluate_async) and the script-timeout classes
    # the non-Ferrum fallback surfaces through Selenium's evaluate_async_script.
    # See #timeout_error?.
    TIMEOUT_ERROR_CLASS_NAMES = [
      "Ferrum::TimeoutError",
      "Ferrum::ScriptTimeoutError",
      "Selenium::WebDriver::Error::ScriptTimeoutError",
      "Selenium::WebDriver::Error::TimeoutError"
    ].freeze

    def initialize(page, configuration = AxeCuprite.configuration)
      @page = page
      @config = configuration
    end

    # Is axe-core present and runnable on the current page?
    def injected?
      @page.evaluate_script(PRESENCE_JS) == true
    end

    # Ensure axe is present. Idempotent: does nothing if already injected
    # (so repeated assertions on one page don't re-send ~500KB), unless force:.
    # Returns true if it actually injected, false if it was already there.
    def ensure_injected!(force: false)
      return false if !force && injected?

      inject_source!
      true
    end

    # Inject the vendored axe-core source into the page. Primary path is
    # Capybara's driver-neutral execute_script (which, on Cuprite, runs via
    # CDP Runtime.evaluate and is not subject to the page's CSP). If that path
    # fails to land axe — e.g. a strict Content-Security-Policy — we fall back
    # to Ferrum's add_script_tag.
    def inject_source!
      source = AxeCuprite.axe_source
      errors = {}

      begin
        @page.execute_script(source)
      rescue StandardError => e
        errors["execute_script"] = e
      end
      return true if injected?

      begin
        try_add_script_tag(source)
      rescue StandardError => e
        errors["add_script_tag"] = e
      end
      return true if injected?

      raise InjectionError, injection_failure_message(errors)
    end

    # Run axe and return a Results object. Injects on demand if needed.
    def run(context:, options:, timeout: nil)
      timeout ||= @config.timeout
      ensure_present!

      raw = evaluate_axe(context, options, timeout)
      raise AxeRunError, "axe.run failed: #{raw["error"]}" if raw.is_a?(Hash) && raw["error"]

      Results.new(raw)
    end

    private

    # Guarantee axe is on the page before running. Honors the auto_inject toggle:
    # when disabled, the caller is responsible for injecting first.
    def ensure_present!
      if @config.auto_inject
        ensure_injected!(force: false)
      elsif !injected?
        raise InjectionError,
              "axe-core is not present and auto_inject is disabled. Call Runner#inject! " \
              "(or AxeCuprite.configure { |c| c.auto_inject = true })."
      end
    end

    # Run axe asynchronously with an explicit timeout decoupled from
    # Capybara.default_max_wait_time. Uses Ferrum's evaluate_async directly when
    # available (Cuprite), else falls back to Capybara's evaluate_async_script
    # under a temporarily-bumped wait time for other drivers.
    def evaluate_axe(context, options, timeout)
      fpage = ferrum_page
      if fpage
        fpage.evaluate_async(RUN_JS, timeout, context, options)
      else
        Capybara.using_wait_time(timeout) do
          @page.evaluate_async_script(RUN_JS, context, options)
        end
      end
    rescue StandardError => e
      if timeout_error?(e)
        raise TimeoutError,
              "axe.run did not finish within #{timeout}s. Increase the timeout " \
              "(AxeCuprite.configure { |c| c.timeout = N } or the matcher/runner timeout:), " \
              "or scope the run with .within(selector). Underlying: #{e.message}"
      end
      raise
    end

    # The underlying Ferrum::Page, if this Capybara session is driven by Cuprite
    # (or any Ferrum-based driver). nil for non-Ferrum drivers.
    def ferrum_page
      driver = @page.driver
      return nil unless driver.respond_to?(:browser)

      browser = driver.browser
      return nil unless browser.respond_to?(:page)

      fpage = browser.page
      return nil unless fpage.respond_to?(:evaluate_async)

      fpage
    rescue StandardError
      nil
    end

    # Best-effort CSP fallback via Ferrum's add_script_tag(content:). Returns
    # false when no Ferrum add_script_tag is available (non-Ferrum drivers); lets
    # a genuine injection failure propagate so inject_source! can report it.
    def try_add_script_tag(source)
      fpage = ferrum_page
      return false unless fpage.respond_to?(:add_script_tag)

      fpage.add_script_tag(content: source)
      true
    end

    # Build the InjectionError message, appending whatever the injection paths
    # actually raised so a non-CSP failure (dead browser, dead CDP session,
    # misconfigured driver) isn't silently blamed on Content-Security-Policy.
    def injection_failure_message(errors)
      message = "axe-core did not load after injection. The page may be blocking " \
                "script injection (e.g. a strict Content-Security-Policy)."
      return message if errors.empty?

      detail = errors.map { |path, e| "#{path}: #{e.class}: #{e.message}" }.join("; ")
      "#{message}\nUnderlying errors: #{detail}"
    end

    # Did `evaluate_axe` fail because axe.run genuinely timed out (so the
    # "increase the timeout / scope the run" guidance is right), or did it hit a
    # real page-side error that must propagate untouched?
    #
    # Classification is driven by error CLASS, not message. A message that merely
    # mentions a timeout is deliberately NOT sufficient: a real Ferrum::JavaScriptError
    # from axe or the app whose text happens to contain "timeout" must not be
    # rewritten as an AxeCuprite::TimeoutError with misleading guidance.
    #
    # The one message check is narrow and class-gated: Ferrum reports its own
    # async-evaluation timeout (page.evaluate_async) as a generic JavaScriptError
    # carrying a "timed out promise" message, so for that class — and only that
    # class — the message is what tells a timeout apart from a real JS error.
    def timeout_error?(error)
      name = error.class.name.to_s
      return true if TIMEOUT_ERROR_CLASS_NAMES.include?(name)

      name == "Ferrum::JavaScriptError" && error.message.to_s.match?(/timed out promise/i)
    end
  end
end
