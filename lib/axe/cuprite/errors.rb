# frozen_string_literal: true

module AxeCuprite
  # Base class for all axe-cuprite errors.
  class Error < StandardError; end

  # Raised when axe.run does not resolve within the configured timeout.
  # Usually means the page is very large or axe is stuck — bump the timeout
  # via AxeCuprite.configure { |c| c.timeout = ... } or the matcher/runner.
  class TimeoutError < Error; end

  # Raised when axe-core itself reports an error while running (e.g. an
  # invalid context selector or run option).
  class AxeRunError < Error; end

  # Raised when axe could not be injected into the page (e.g. a strict
  # Content-Security-Policy blocked both inline injection and add_script_tag).
  class InjectionError < Error; end
end
