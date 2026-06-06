# frozen_string_literal: true

require "axe/cuprite/version"
require "axe/cuprite/errors"
require "axe/cuprite/configuration"
require "axe/cuprite/results"
require "axe/cuprite/injector"
require "axe/cuprite/runner"

# axe-cuprite drives the axe-core accessibility engine through Capybara's
# driver-neutral JavaScript API, so it works with Cuprite (Ferrum/CDP) and any
# other real-browser Capybara driver — without ever touching Selenium internals.
#
# Quick start:
#
#   require "axe/cuprite"
#   require "axe/cuprite/rspec"   # in a spec_helper, to load the matchers
#
#   expect(page).to be_axe_clean.checking_only(:color_contrast)
#
module AxeCuprite
  class << self
    # The global configuration object. See AxeCuprite::Configuration.
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure axe-cuprite:
    #
    #   AxeCuprite.configure do |c|
    #     c.timeout = 30
    #     c.report_only = true
    #   end
    def configure
      yield configuration if block_given?
      configuration
    end

    # Reset configuration to defaults (mainly useful in tests).
    def reset_configuration!
      @configuration = Configuration.new
    end

    # Path to the vendored axe-core JavaScript engine.
    def axe_path
      File.expand_path("cuprite/vendor/axe.min.js", __dir__)
    end

    # The cached source of the vendored axe-core engine.
    def axe_source
      @axe_source ||= File.read(axe_path)
    end
  end
end
