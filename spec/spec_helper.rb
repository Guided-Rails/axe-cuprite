# frozen_string_literal: true

require "bundler/setup"

require "axe/cuprite"
require "axe/cuprite/rspec"

require "capybara/rspec"
require "capybara/cuprite"

require_relative "support/fixture_app"

Capybara.app = FixtureApp.new
Capybara.server = :puma, { Silent: true }

# Deliberately short, to prove our axe timeout is decoupled from this value.
Capybara.default_max_wait_time = 2

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1200, 900],
    headless: true,
    process_timeout: 30,
    timeout: 30
  )
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include Capybara::DSL

  config.before { AxeCuprite.reset_configuration! }
  config.after  { Capybara.reset_sessions! }

  config.order = :defined
end
